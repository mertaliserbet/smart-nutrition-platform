import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/personal_nutrition_target_api.dart';
import 'water_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late PersonalNutritionTargetApi api;
  late Future<void> Function(HttpRequest) resource;
  var refreshes = 0;
  Map<String, Object?> response() => {
    for (final f in personalTargetFields) f.key: null,
    'source': 'personal',
  };
  Future<void> reply(HttpRequest request, int status, Object? body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    if (body != null) request.response.write(jsonEncode(body));
    await request.response.close();
  }

  setUp(() async {
    refreshes = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (request) => reply(request, 200, response());
    final refreshExpiry = DateTime.now()
        .toUtc()
        .add(const Duration(days: 30))
        .toIso8601String();
    Map<String, Object?> pair(String marker) => {
      'accessToken': 'synthetic.$marker.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': marker * 43,
      'refreshTokenExpiresAt': refreshExpiry,
    };
    server.listen((request) async {
      switch (request.uri.path) {
        case '/api/v1/auth/login':
          await request.drain<void>();
          await reply(request, 200, pair('A'));
        case '/api/v1/auth/me':
          await reply(request, 200, {
            'id': waterClientId,
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          refreshes++;
          await request.drain<void>();
          await reply(request, 200, pair('B'));
        case '/api/v1/auth/logout':
          await request.drain<void>();
          await reply(request, 204, null);
        default:
          await resource(request);
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
    api = PersonalNutritionTargetApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  for (final method in ['GET', 'PATCH']) {
    test('late $method response cannot survive an ended session', () async {
      final started = Completer<void>(), release = Completer<void>();
      resource = (request) async {
        await request.drain<void>();
        started.complete();
        await release.future;
        await reply(request, 200, response()..['dailyWaterTargetMl'] = 2345);
      };
      final pending = method == 'GET'
          ? api.get()
          : api.patch({'dailyWaterTargetMl': 2345});
      await started.future;
      await session.signOut();
      release.complete();
      await expectLater(
        pending,
        throwsA(
          isA<PersonalNutritionTargetApiException>().having(
            (e) => e.statusCode,
            'owner rejected',
            401,
          ),
        ),
      );
      expect(session.isAuthenticated, isFalse);
    });
  }
  test(
    'GET and PATCH use current bearer and client context without clientId or cookies',
    () async {
      resource = (request) async {
        expect(request.uri.toString(), PersonalNutritionTargetApi.path);
        expect(
          request.headers.value('authorization'),
          startsWith('Bearer synthetic.'),
        );
        expect(request.headers.value('x-profile-context'), 'client');
        expect(request.headers.value('cookie'), isNull);
        final body = await utf8.decoder.bind(request).join();
        if (request.method == 'GET') {
          expect(body, isEmpty);
        } else {
          expect(request.method, 'PATCH');
          expect(jsonDecode(body), {
            'dailyWaterTargetMl': null,
            'dailyProteinTargetGrams': 125.5,
          });
        }
        await reply(
          request,
          200,
          response()..['dailyProteinTargetGrams'] = 125.5,
        );
      };
      expect((await api.get()).dailyWaterTargetMl, isNull);
      expect(
        (await api.patch({
          'dailyWaterTargetMl': null,
          'dailyProteinTargetGrams': 125.5,
        })).dailyProteinTargetGrams,
        125.5,
      );
    },
  );
  test('GET refreshes once while PATCH is never replayed after 401', () async {
    var requests = 0;
    resource = (request) async {
      requests++;
      await request.drain<void>();
      await reply(
        request,
        requests == 1 ? 401 : 200,
        requests == 1 ? null : response(),
      );
    };
    await api.get();
    expect(requests, 2);
    expect(refreshes, 1);
    requests = 0;
    await expectLater(
      api.patch({'dailyWaterTargetMl': 2000}),
      throwsA(isA<PersonalNutritionTargetApiException>()),
    );
    expect(requests, 1);
    expect(refreshes, 2);
  });
  test(
    'empty, ownership and invalid numeric writes are rejected before a request',
    () async {
      var requests = 0;
      resource = (request) async {
        requests++;
        await reply(request, 200, response());
      };
      for (final change in <Map<String, num?>>[
        {},
        {'clientId': null},
        {'source': null},
        for (final f in personalTargetFields) ...[
          {f.key: 0},
          {f.key: -1},
          {f.key: f.maximum + 0.001},
          {f.key: double.nan},
          {f.key: double.infinity},
        ],
      ]) {
        expect(
          () => api.patch(change),
          throwsA(isA<PersonalNutritionTargetApiException>()),
        );
      }
      expect(requests, 0);
    },
  );
  test(
    'unknown, missing, non-finite, out-of-bounds and wrong-source responses fail closed',
    () async {
      final malformed = <Map<String, Object?>>[
        response()..remove('dailyFatTargetGrams'),
        response()..['clientId'] = waterClientId,
        response()..['source'] = 'assigned',
        response()..['dailyWaterTargetMl'] = '2000',
        response()..['dailyProteinTargetGrams'] = 0,
        response()..['dailyCaloriesTargetKcal'] = 10001,
      ];
      for (final body in malformed) {
        resource = (request) => reply(request, 200, body);
        await expectLater(
          api.get(),
          throwsA(isA<PersonalNutritionTargetApiException>()),
        );
      }
      resource = (request) => reply(request, 200, response()..remove('source'));
      await expectLater(
        api.patch({'dailyWaterTargetMl': 2000}),
        throwsA(
          isA<PersonalNutritionTargetApiException>().having(
            (e) => e.uncertain,
            'write result uncertain',
            isTrue,
          ),
        ),
      );
    },
  );
  test(
    'server failure and disconnect are uncertain writes and never automatic retries',
    () async {
      var requests = 0;
      resource = (request) async {
        requests++;
        await request.drain<void>();
        await reply(request, 500, null);
      };
      await expectLater(
        api.patch({'dailyWaterTargetMl': 2000}),
        throwsA(
          isA<PersonalNutritionTargetApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      expect(requests, 1);
      resource = (request) async {
        requests++;
        final socket = await request.response.detachSocket();
        socket.destroy();
      };
      await expectLater(
        api.patch({'dailyWaterTargetMl': 2000}),
        throwsA(
          isA<PersonalNutritionTargetApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      expect(requests, 2);
    },
  );
}
