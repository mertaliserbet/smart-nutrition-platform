import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';

const expertId = '11111111-1111-4111-8111-111111111111';
const clientId = '22222222-2222-4222-8222-222222222222';
const relationId = '33333333-3333-4333-8333-333333333333';
Map<String, Object?> relationship() => {
  'id': relationId,
  'clientId': clientId,
  'dietitianId': expertId,
  'status': 'pending',
  'requestedAt': '2026-11-02T10:00:00Z',
  'respondedAt': null,
  'endedAt': null,
};

void main() {
  late HttpServer server;
  late AuthSession session;
  late DietitianApi api;
  late _MemoryStore store;
  late DateTime refreshExpiry;
  late Future<void> Function(HttpRequest) resource;
  Future<void> Function(HttpRequest)? renewal;
  var renewals = 0;
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
  setUp(() async {
    renewals = 0;
    renewal = null;
    refreshExpiry = DateTime.now().toUtc().add(const Duration(days: 30));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (r) => reply(r, 200, {'items': [], 'totalCount': 0});
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': clientId,
            'displayName': 'Synthetic',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          renewals++;
          await r.drain<void>();
          if (renewal != null) {
            await renewal!(r);
          } else {
            await reply(r, 200, pair(1));
          }
        case '/api/v1/auth/logout':
          await r.drain<void>();
          r.response.statusCode = 204;
          await r.response.close();
        default:
          await resource(r);
      }
    });
    store = _MemoryStore();
    session = AuthSession(
      api: LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}')),
      store: store,
    );
    await session.initialize();
    expect(
      await session.signIn(
        email: 'synthetic@example.test',
        password: 'Synthetic password',
      ),
      isTrue,
    );
    api = DietitianApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });

  test(
    'search encodes Unicode and pagination; sends verified bearer without cookie or body',
    () async {
      resource = (r) async {
        expect(r.method, 'GET');
        expect(r.uri.path, '/api/v1/dietitians');
        expect(r.uri.queryParameters, {
          'page': '2',
          'pageSize': '10',
          'query': 'İpek & Özgür',
        });
        expect(
          r.headers.value('authorization'),
          'Bearer synthetic.version0.signature',
        );
        expect(r.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(r).join(), isEmpty);
        await reply(r, 200, {
          'items': [
            {'id': expertId, 'displayName': 'İpek Özgür'},
          ],
          'totalCount': 11,
        });
      };
      final result = await api.search(page: 2, query: ' İpek & Özgür ');
      expect(result.items.single.displayName, 'İpek Özgür');
      expect(result.totalCount, 11);
    },
  );
  test(
    'relationship reads explicitly select client context and pending pagination',
    () async {
      resource = (r) async {
        expect(r.uri.queryParameters, {
          'status': 'pending',
          'page': '2',
          'pageSize': '10',
        });
        expect(r.headers.value('x-profile-context'), 'client');
        await reply(r, 200, {
          'items': [relationship()],
          'totalCount': 11,
        });
      };
      expect(
        (await api.relationships(
          status: 'pending',
          page: 2,
        )).items.single.status,
        'pending',
      );
    },
  );
  for (final byCode in [false, true]) {
    test(
      'request sends exactly one approved field with bearer/client context (code=$byCode)',
      () async {
        resource = (r) async {
          expect(r.method, 'POST');
          expect(r.uri.path, '/api/v1/dietitian-relationships');
          expect(
            r.headers.value('authorization'),
            'Bearer synthetic.version0.signature',
          );
          expect(r.headers.value('cookie'), isNull);
          expect(r.headers.value('x-profile-context'), 'client');
          expect(
            jsonDecode(await utf8.decoder.bind(r).join()),
            byCode
                ? {'invitationCode': 'ABCDEFGH234567AB'}
                : {'dietitianId': expertId},
          );
          await reply(r, 201, relationship());
        };
        final result = byCode
            ? await api.request(invitationCode: ' abcdefgh234567ab ')
            : await api.request(dietitianId: expertId);
        expect(result.status, 'pending');
        expect(session.isAuthenticated, isTrue);
      },
    );
  }
  test('invalid or ambiguous selection never reaches transport', () async {
    var calls = 0;
    resource = (r) async {
      calls++;
      await reply(r, 500, {});
    };
    for (final action in <Future<Object?> Function()>[
      () => api.request(),
      () => api.request(
        dietitianId: expertId,
        invitationCode: 'ABCDEFGH234567AB',
      ),
      () => api.request(invitationCode: '0000'),
      () => api.request(dietitianId: 'invalid'),
    ]) {
      await expectLater(action(), throwsA(isA<DietitianApiException>()));
    }
    expect(calls, 0);
  });
  for (final (status, message) in [
    (409, 'Bekleyen isteğiniz'),
    (422, 'Seçilen diyetisyene'),
    (429, 'Çok fazla'),
    (500, 'servisi'),
    (403, 'erişim izniniz'),
    (400, 'İstek bilgileri'),
  ]) {
    test(
      'HTTP $status has a safe Turkish message and no write replay',
      () async {
        var calls = 0;
        resource = (r) async {
          calls++;
          await r.drain<void>();
          r.response.headers.set('Retry-After', '61');
          await reply(r, status, {
            'error': {
              'code': 'invalid_request',
              'message': 'private backend detail',
            },
            'requestId': 'synthetic',
          });
        };
        await expectLater(
          api.request(dietitianId: expertId),
          throwsA(
            isA<DietitianApiException>()
                .having((e) => e.message, 'message', contains(message))
                .having(
                  (e) => e.message,
                  'private details',
                  isNot(contains('private backend')),
                )
                .having(
                  (e) => e.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 61),
                ),
          ),
        );
        expect(calls, 1);
        expect(session.isAuthenticated, isTrue);
      },
    );
  }
  test('expired or consumed invitation has a specific safe message', () async {
    resource = (r) => reply(r, 422, {
      'error': {'code': 'validation_failed', 'message': 'private'},
      'requestId': 'synthetic',
    });
    await expectLater(
      api.request(invitationCode: 'ABCDEFGH234567AB'),
      throwsA(
        isA<DietitianApiException>().having(
          (e) => e.message,
          'message',
          contains('Davet kodu geçersiz'),
        ),
      ),
    );
  });
  test(
    'malformed directory, wrong relation status and fake successful acceptance are rejected',
    () async {
      resource = (r) => reply(r, 200, {
        'items': [
          {'id': expertId, 'displayName': 'Synthetic', 'isVerified': true},
        ],
        'totalCount': 1,
      });
      await expectLater(
        api.search(page: 1),
        throwsA(isA<DietitianApiException>()),
      );
      resource = (r) => reply(r, 200, {
        'items': [relationship()],
        'totalCount': 1,
      });
      await expectLater(
        api.relationships(status: 'active'),
        throwsA(isA<DietitianApiException>()),
      );
      resource = (r) => reply(r, 201, {
        ...relationship(),
        'status': 'active',
        'respondedAt': '2026-11-02T11:00:00Z',
      });
      await expectLater(
        api.request(dietitianId: expertId),
        throwsA(isA<DietitianApiException>()),
      );
    },
  );
  test(
    'concurrent 401 reads clear access immediately, share rotation and retry only reads',
    () async {
      final gate = Completer<void>();
      var challenged = 0;
      renewal = (r) async {
        await gate.future;
        await reply(r, 200, pair(1));
      };
      resource = (r) async {
        if (r.headers.value('authorization') ==
            'Bearer synthetic.version0.signature') {
          challenged++;
          await reply(r, 401, null);
        } else {
          await reply(r, 200, {'items': [], 'totalCount': 0});
        }
      };
      final one = api.search(page: 1);
      final two = api.relationships(status: 'pending');
      await until(() => renewals == 1 && challenged == 2);
      expect(session.isAuthenticated, isFalse);
      gate.complete();
      await Future.wait([one, two]);
      expect(renewals, 1);
      expect(session.isAuthenticated, isTrue);
      expect(store.value!.refreshToken, 'B' * 43);
    },
  );
  test(
    '401 mutation refreshes authentication without resending the mutation',
    () async {
      var writes = 0;
      resource = (r) async {
        writes++;
        await r.drain<void>();
        await reply(r, 401, null);
      };
      await expectLater(
        api.request(dietitianId: expertId),
        throwsA(
          isA<DietitianApiException>().having(
            (e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(writes, 1);
      expect(renewals, 1);
      expect(session.isAuthenticated, isTrue);
    },
  );
  test(
    'invalid refresh after 401 closes the gate and clears stored session',
    () async {
      renewal = (r) => reply(r, 401, null);
      resource = (r) => reply(r, 401, null);
      await expectLater(
        api.search(page: 1),
        throwsA(isA<DietitianApiException>()),
      );
      expect(session.isAuthenticated, isFalse);
      expect(store.value, isNull);
    },
  );
  test(
    'late response from a logged out account cannot enter a new session',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      resource = (r) async {
        started.complete();
        await release.future;
        await reply(r, 401, null);
      };
      final old = api.search(page: 1);
      final rejected = expectLater(old, throwsA(isA<DietitianApiException>()));
      await started.future;
      await session.signOut();
      expect(
        await session.signIn(
          email: 'other@example.test',
          password: 'Synthetic password',
        ),
        isTrue,
      );
      release.complete();
      await rejected;
      expect(session.isAuthenticated, isTrue);
      expect(renewals, 0);
    },
  );
  test(
    'connection failure preserves a verified session and gives no success',
    () async {
      await server.close(force: true);
      await expectLater(
        api.request(dietitianId: expertId),
        throwsA(
          isA<DietitianApiException>().having(
            (e) => e.message,
            'message',
            contains('Bağlantı'),
          ),
        ),
      );
      expect(session.isAuthenticated, isTrue);
      expect(store.value, isNotNull);
    },
  );
  test('redirects are not followed with the bearer credential', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var leaked = false;
    other.listen((r) async {
      leaked = true;
      await reply(r, 200, {});
    });
    resource = (r) async {
      r.response.statusCode = 307;
      r.response.headers.set(
        'Location',
        'http://127.0.0.1:${other.port}/external',
      );
      await r.response.close();
    };
    try {
      await expectLater(
        api.search(page: 1),
        throwsA(isA<DietitianApiException>()),
      );
      expect(leaked, isFalse);
    } finally {
      await other.close(force: true);
    }
  });
}

Future<void> reply(HttpRequest r, int code, Object? body) async {
  r.response.statusCode = code;
  r.response.headers.contentType = ContentType.json;
  if (body != null) r.response.write(jsonEncode(body));
  await r.response.close();
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Test synchronization failed');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _MemoryStore implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken record) async {
    value = record;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
