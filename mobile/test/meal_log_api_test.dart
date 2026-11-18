import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'meal_log_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late MealLogApi api;
  late Future<void> Function(HttpRequest) resource;
  var refreshes = 0;
  setUp(() async {
    refreshes = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (request) => reply(request, 200, mealJson());
    final refreshExpiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object?> pair(int version) => {
      'accessToken': 'synthetic.version$version.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': (version == 0 ? 'A' : 'B') * 43,
      'refreshTokenExpiresAt': refreshExpiry.toIso8601String(),
    };
    server.listen((request) async {
      switch (request.uri.path) {
        case '/api/v1/auth/login':
          await request.drain<void>();
          await reply(request, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(request, 200, {
            'id': '44444444-4444-4444-8444-444444444444',
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          refreshes++;
          await request.drain<void>();
          await reply(request, 200, pair(1));
        default:
          await resource(request);
      }
    });
    session = AuthSession(
      api: LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}')),
      store: MealMemoryStore(),
    );
    await session.initialize();
    expect(
      await session.signIn(
        email: 'synthetic@example.test',
        password: 'Synthetic password',
      ),
      isTrue,
    );
    api = MealLogApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'GET uses client JWT and approved pagination without body, cookie or clientId',
    () async {
      resource = (request) async {
        expect(request.uri.toString(), '/api/v1/meal-logs?page=2&pageSize=10');
        expect(request.method, 'GET');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic.version0.signature',
        );
        expect(request.headers.value('x-profile-context'), 'client');
        expect(request.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(request).join(), isEmpty);
        await reply(request, 200, {
          'items': [mealJson()],
          'totalCount': 11,
        });
      };
      final page = await api.list(page: 2);
      expect(page.totalCount, 11);
      expect(page.items.single.items.single.caloriesKcal, 0);
      expect(page.items.single.items.single.quantityGrams, isNull);
      expect(page.items.single.clientId, mealClientId);
      expect(page.items.single.note, isNull);
    },
  );
  test(
    'create, detail, patch and delete use approved methods and fields',
    () async {
      final methods = <String>[];
      resource = (request) async {
        methods.add(request.method);
        expect(request.headers.value('x-profile-context'), 'client');
        if (request.method == 'POST' || request.method == 'PATCH') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body.containsKey('clientId'), isFalse);
          expect(body.containsKey('id'), isFalse);
          if (request.method == 'PATCH') {
            expect(body.containsKey('source'), isFalse);
          }
        }
        await reply(
          request,
          request.method == 'POST'
              ? 201
              : request.method == 'DELETE'
              ? 204
              : 200,
          request.method == 'DELETE' ? null : mealJson(),
        );
      };
      final body = {
        'mealType': 'lunch',
        'consumedAt': '2026-11-16T12:00:00Z',
        'source': 'manual',
        'items': [sampleMeal().items.single.toInput()],
      };
      expect((await api.create(body)).id, mealId);
      expect((await api.get(mealId)).id, mealId);
      await api.update(mealId, {'note': null});
      await api.delete(mealId);
      expect(methods, ['POST', 'GET', 'PATCH', 'DELETE']);
    },
  );
  test('GET recovers once after 401', () async {
    var calls = 0;
    resource = (request) async {
      calls++;
      await reply(
        request,
        calls == 1 ? 401 : 200,
        calls == 1 ? null : mealJson(),
      );
    };
    expect((await api.get(mealId)).id, mealId);
    expect(calls, 2);
    expect(refreshes, 1);
  });
  test(
    'daily interval reads every page with UTC filters before returning totals',
    () async {
      final from = DateTime.utc(2026, 11, 17), to = DateTime.utc(2026, 11, 18);
      Map<String, Object?> record(int index) {
        final row = mealJson();
        final id =
            '11111111-1111-4111-8111-${index.toString().padLeft(12, '0')}';
        row['id'] = id;
        row['consumedAt'] = '2026-11-17T12:00:00Z';
        ((row['items'] as List).single as Map)['mealLogId'] = id;
        return row;
      }

      final pages = <int>[];
      resource = (request) async {
        expect(request.uri.queryParameters['from'], from.toIso8601String());
        expect(request.uri.queryParameters['to'], to.toIso8601String());
        final page = int.parse(request.uri.queryParameters['page']!);
        pages.add(page);
        await reply(request, 200, {
          'items': page == 1 ? List.generate(10, record) : [record(10)],
          'totalCount': 11,
        });
      };
      final rows = await api.forRange(from: from, to: to);
      expect(rows, hasLength(11));
      expect(pages, [1, 2]);
      resource = (request) =>
          reply(request, 200, {'items': [], 'totalCount': 0});
      expect(await api.forRange(from: from, to: to), isEmpty);
    },
  );
  test(
    'changing pagination, duplicate IDs and out-of-day rows never become partial totals',
    () async {
      final from = DateTime.utc(2026, 11, 16), to = DateTime.utc(2026, 11, 17);
      resource = (request) =>
          reply(request, 200, {'items': [], 'totalCount': 1});
      await expectLater(
        api.forRange(from: from, to: to),
        throwsA(isA<MealLogApiException>()),
      );
      resource = (request) => reply(request, 200, {
        'items': [mealJson()],
        'totalCount': request.uri.queryParameters['page'] == '1' ? 2 : 3,
      });
      await expectLater(
        api.forRange(from: from, to: to),
        throwsA(isA<MealLogApiException>()),
      );
      resource = (request) => reply(request, 200, {
        'items': [mealJson()],
        'totalCount': 2,
      });
      await expectLater(
        api.forRange(from: from, to: to),
        throwsA(isA<MealLogApiException>()),
      );
      final outside = mealJson()..['consumedAt'] = '2026-11-17T00:00:00Z';
      resource = (request) => reply(request, 200, {
        'items': [outside],
        'totalCount': 1,
      });
      await expectLater(
        api.forRange(from: from, to: to),
        throwsA(isA<MealLogApiException>()),
      );
    },
  );
  for (final method in ['POST', 'PATCH', 'DELETE']) {
    test(
      '$method is never replayed after a 401 even when refresh succeeds',
      () async {
        var calls = 0;
        resource = (request) async {
          calls++;
          await request.drain<void>();
          await reply(request, 401, null);
        };
        final request = method == 'POST'
            ? api.create({})
            : method == 'PATCH'
            ? api.update(mealId, {})
            : api.delete(mealId);
        await expectLater(
          request,
          throwsA(
            isA<MealLogApiException>().having(
              (e) => e.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(calls, 1);
        expect(refreshes, 1);
        expect(session.isAuthenticated, isTrue);
      },
    );
  }
  test(
    'rejects malformed resources, cross-meal children and mixed owners',
    () async {
      for (final key in [
        'clientId',
        'mealType',
        'source',
        'consumedAt',
        'items',
      ]) {
        final row = mealJson();
        row[key] = 'invalid';
        resource = (request) => reply(request, 200, row);
        await expectLater(api.get(mealId), throwsA(isA<MealLogApiException>()));
      }
      final row = mealJson();
      final item = (row['items'] as List).single as Map<String, Object?>;
      item['mealLogId'] = mealClientId;
      resource = (request) => reply(request, 200, row);
      await expectLater(api.get(mealId), throwsA(isA<MealLogApiException>()));
      item['mealLogId'] = mealId;
      item['proteinGrams'] = '12.5';
      await expectLater(api.get(mealId), throwsA(isA<MealLogApiException>()));
      resource = (request) => reply(request, 200, {
        'items': [mealJson()],
        'totalCount': 0,
      });
      await expectLater(api.list(), throwsA(isA<MealLogApiException>()));
    },
  );
  test(
    'missing detail is an error, not an empty successful response',
    () async {
      resource = (request) => reply(request, 404, null);
      await expectLater(
        api.get(mealId),
        throwsA(
          isA<MealLogApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    },
  );
  test(
    'malformed successful mutation and server error are uncertain without exposing server text',
    () async {
      resource = (request) async {
        await request.drain<void>();
        await reply(request, 201, {'secret': 'Synthetic private server text'});
      };
      await expectLater(
        api.create({}),
        throwsA(
          isA<MealLogApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      resource = (request) async {
        await request.drain<void>();
        await reply(request, 500, {'message': 'Synthetic private server text'});
      };
      await expectLater(
        api.update(mealId, {}),
        throwsA(
          isA<MealLogApiException>()
              .having((e) => e.uncertain, 'uncertain', isTrue)
              .having(
                (e) => e.message,
                'message',
                isNot(contains('private server')),
              ),
        ),
      );
    },
  );
  test(
    'connection failure is uncertain for a mutation and preserves session',
    () async {
      await server.close(force: true);
      await expectLater(
        api.create({}),
        throwsA(
          isA<MealLogApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      expect(session.isAuthenticated, isTrue);
    },
  );
}

Future<void> reply(HttpRequest request, int status, Object? body) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  if (body != null) request.response.write(jsonEncode(body));
  await request.response.close();
}

class MealMemoryStore implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
