import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_comment_api.dart';
import 'meal_log_comment_test_support.dart';
import 'meal_log_test_support.dart';
import 'water_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late MealLogCommentApi api;
  late Future<void> Function(HttpRequest) resource;
  var renewals = 0;
  Future<void> reply(HttpRequest r, int status, Object? body) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    if (body != null) {
      r.response.write(jsonEncode(body));
    }
    await r.response.close();
  }

  Map<String, Object?> pageBody() => {
    'items': [commentJson(rootComment()), commentJson(clientReply())],
    'totalCount': 2,
  };
  setUp(() async {
    renewals = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final expiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object> pair(int version) => {
      'accessToken': 'synthetic.comment$version.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': (version == 0 ? 'A' : 'B') * 43,
      'refreshTokenExpiresAt': expiry.toIso8601String(),
    };
    resource = (r) => reply(r, 200, pageBody());
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': '44444444-4444-4444-8444-444444444444',
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          renewals++;
          await r.drain<void>();
          await reply(r, 200, pair(1));
        case '/api/v1/auth/logout':
          await r.drain<void>();
          await reply(r, 204, null);
        default:
          await resource(r);
      }
    });
    session = AuthSession(
      api: LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}')),
      store: WaterMemoryStore(),
    );
    await session.initialize();
    expect(
      await session.signIn(
        email: 'synthetic@example.test',
        password: 'Synthetic password',
      ),
      isTrue,
    );
    api = MealLogCommentApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'list uses ascending paged contract, client JWT and no cookie/body',
    () async {
      resource = (r) async {
        expect(r.uri.path, '/api/v1/meal-logs/$mealId/comments');
        expect(r.uri.queryParameters, {'page': '1', 'pageSize': '10'});
        expect(r.method, 'GET');
        expect(
          r.headers.value('authorization'),
          'Bearer synthetic.comment0.signature',
        );
        expect(r.headers.value('x-profile-context'), 'client');
        expect(r.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(r).join(), isEmpty);
        await reply(r, 200, pageBody());
      };
      final result = await api.list(mealId);
      expect(result.totalCount, 2);
      expect(result.items.first.isRoot, isTrue);
      expect(result.items.last.parentCommentId, rootCommentId);
    },
  );
  test(
    'reply only sends trimmed text and explicit root parent; server author is checked',
    () async {
      resource = (r) async {
        expect(r.method, 'POST');
        expect(r.headers.value('x-profile-context'), 'client');
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'text': 'Yanıt 10',
          'parentCommentId': rootCommentId,
        });
        await reply(r, 201, commentJson(clientReply(text: 'Yanıt 10')));
      };
      expect(
        (await api.reply(mealId, rootComment(), '  Yanıt 10  ')).text,
        'Yanıt 10',
      );
    },
  );
  for (final text in ['', ' \t\n', 'x' * 2001, 'bad\u0000text']) {
    test(
      'invalid reply text is rejected locally (${text.length} code units)',
      () async {
        var calls = 0;
        resource = (r) async {
          calls++;
          await reply(r, 201, commentJson(clientReply()));
        };
        await expectLater(
          api.reply(mealId, rootComment(), text),
          throwsA(isA<MealLogCommentApiException>()),
        );
        expect(calls, 0);
      },
    );
  }
  test(
    '2000 emoji scalars are valid and an existing reply or foreign parent cannot be answered',
    () async {
      final text = '🥣' * 2000;
      var calls = 0;
      resource = (r) async {
        calls++;
        await r.drain<void>();
        await reply(r, 201, commentJson(clientReply(text: text)));
      };
      expect(
        (await api.reply(mealId, rootComment(), text)).text.runes.length,
        2000,
      );
      for (final parent in [
        clientReply(),
        rootComment(meal: commentAuthorId),
      ]) {
        await expectLater(
          api.reply(mealId, parent, 'Sentetik'),
          throwsA(isA<MealLogCommentApiException>()),
        );
      }
      expect(calls, 1);
    },
  );
  for (final scenario in [
    'meal',
    'author',
    'parent',
    'date',
    'count',
    'duplicate',
    'order',
    'shape',
    'text',
  ]) {
    test('corrupt $scenario list fails closed', () async {
      final body = pageBody();
      final rows = body['items'] as List<Map<String, Object?>>;
      switch (scenario) {
        case 'meal':
          rows[0]['mealLogId'] = commentAuthorId;
        case 'author':
          rows[0]['authorUserId'] = 'invalid';
        case 'parent':
          rows[0]['parentCommentId'] = rootCommentId;
        case 'date':
          rows[0]['createdAt'] = '2026-11-18T12:00:00';
        case 'count':
          body['totalCount'] = 0;
        case 'duplicate':
          rows[1] = rows[0];
        case 'order':
          rows[0]['createdAt'] = '2026-11-19T12:00:00Z';
        case 'shape':
          rows[0].remove('parentCommentId');
        case 'text':
          rows[0]['text'] = '';
      }
      resource = (r) => reply(r, 200, body);
      await expectLater(
        api.list(mealId),
        throwsA(isA<MealLogCommentApiException>()),
      );
    });
  }
  for (final status in [401, 403, 404, 422, 500]) {
    test('POST $status is never replayed', () async {
      var calls = 0;
      resource = (r) async {
        calls++;
        await r.drain<void>();
        await reply(r, status, null);
      };
      await expectLater(
        api.reply(mealId, rootComment(), 'Sentetik'),
        throwsA(isA<MealLogCommentApiException>()),
      );
      expect(calls, 1);
      expect(renewals, status == 401 ? 1 : 0);
    });
  }
  test('GET refreshes once and then reads current comments', () async {
    var calls = 0;
    resource = (r) async {
      calls++;
      await reply(r, calls == 1 ? 401 : 200, calls == 1 ? null : pageBody());
    };
    expect((await api.list(mealId)).totalCount, 2);
    expect(calls, 2);
    expect(renewals, 1);
  });
  test(
    'invalid mutation response is uncertain and cannot claim another author or root',
    () async {
      for (final field in ['authorUserId', 'parentCommentId', 'text']) {
        final row = commentJson(clientReply());
        row[field] = field == 'authorUserId'
            ? commentAuthorId
            : field == 'text'
            ? 'different'
            : null;
        resource = (r) async {
          await r.drain<void>();
          await reply(r, 201, row);
        };
        await expectLater(
          api.reply(mealId, rootComment(), 'Sentetik danışan yanıtı'),
          throwsA(
            isA<MealLogCommentApiException>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
      }
    },
  );
  test('late old-user list is discarded on logout', () async {
    final entered = Completer<void>(), release = Completer<void>();
    resource = (r) async {
      entered.complete();
      await release.future;
      await reply(r, 200, pageBody());
    };
    final pending = api.list(mealId);
    await entered.future;
    await session.signOut();
    release.complete();
    await expectLater(
      pending,
      throwsA(
        isA<MealLogCommentApiException>().having(
          (e) => e.statusCode,
          'status',
          401,
        ),
      ),
    );
  });
}
