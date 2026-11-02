import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';

const planId = '11111111-1111-4111-8111-111111111111';
const clientId = '22222222-2222-4222-8222-222222222222';
const expertId = '33333333-3333-4333-8333-333333333333';
Map<String, Object?> item(int number, {int? day, String? group}) => {
  'id': '44444444-4444-4444-8444-${number.toString().padLeft(12, '0')}',
  'nutritionPlanId': planId,
  'dayOfWeek': day,
  'mealType': 'breakfast',
  'description': 'Yulaf ve yoğurt 🥣',
  'recommendedQuantity': '1 kâse',
  'sortOrder': number,
  'recipeId': null,
  'alternativeGroupId': group,
};
Map<String, Object?> program() => {
  'id': planId,
  'clientId': clientId,
  'dietitianId': expertId,
  'title': 'Sentetik haftalık program',
  'status': 'active',
  'startDate': '2026-11-03',
  'endDate': null,
  'dailyCaloriesTargetKcal': null,
  'dailyWaterTargetMl': 2000,
  'createdAt': '2026-11-02T10:00:00Z',
  'versionId': '55555555-5555-4555-8555-555555555555',
  'versionNumber': 1,
  'items': [item(1)],
};
void main() {
  late HttpServer server;
  late AuthSession session;
  late NutritionPlanApi api;
  late _Store store;
  late Future<void> Function(HttpRequest) resource;
  late DateTime refreshExpiry;
  var renewals = 0, rejectRefresh = false;
  setUp(() async {
    renewals = 0;
    rejectRefresh = false;
    refreshExpiry = DateTime.now().toUtc().add(const Duration(days: 30));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
    resource = (r) => reply(r, 200, program());
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': clientId,
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          renewals++;
          await r.drain<void>();
          await reply(
            r,
            rejectRefresh ? 401 : 200,
            rejectRefresh ? null : pair(1),
          );
        default:
          await resource(r);
      }
    });
    store = _Store();
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
    api = NutritionPlanApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'active GET uses bearer/client context without query, body, cookie or clientId',
    () async {
      resource = (r) async {
        expect(r.method, 'GET');
        expect(r.uri.toString(), '/api/v1/nutrition-plans/active');
        expect(
          r.headers.value('authorization'),
          'Bearer synthetic.version0.signature',
        );
        expect(r.headers.value('x-profile-context'), 'client');
        expect(r.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(r).join(), isEmpty);
        await reply(r, 200, program());
      };
      final result = (await api.active())!;
      expect(result.dietitianId, expertId);
      expect(result.items.single.description, 'Yulaf ve yoğurt 🥣');
      expect(result.items.single.dayOfWeek, isNull);
      expect(result.dailyCaloriesTargetKcal, isNull);
      expect(result.versionNumber, 1);
      expect(result.dailyWaterTargetMl, 2000);
    },
  );
  test('404 is an empty state even with a missing error body', () async {
    resource = (r) => reply(r, 404, null);
    expect(await api.active(), isNull);
    expect(session.isAuthenticated, isTrue);
  });
  test(
    'personal program and supported day/alternative fields remain unmodified',
    () async {
      const group = '66666666-6666-4666-8666-666666666666';
      resource = (r) => reply(r, 200, {
        ...program(),
        'dietitianId': null,
        'items': [item(2, day: 7, group: group), item(1, day: 7, group: group)],
      });
      final result = (await api.active())!;
      expect(result.dietitianId, isNull);
      expect(result.items.map((i) => i.sortOrder), [1, 2]);
      expect(result.items.first.dayOfWeek, 7);
      expect(result.items.first.alternativeGroupId, group);
    },
  );
  test(
    'valid full program larger than 64 KiB is not truncated by the small Auth cap',
    () async {
      final items = List.generate(
        100,
        (i) => {...item(i + 1), 'description': 'a' * 800},
      );
      final body = {...program(), 'items': items};
      expect(utf8.encode(jsonEncode(body)).length, greaterThan(65536));
      resource = (r) => reply(r, 200, body);
      expect((await api.active())!.items.length, 100);
    },
  );
  for (final status in [401, 403, 429, 500]) {
    test(
      'HTTP $status gives a safe error and never exposes an earlier plan',
      () async {
        resource = (r) => reply(r, status, {
          'error': {'code': 'forbidden', 'message': 'private detail'},
          'requestId': 'synthetic',
        });
        if (status == 401) rejectRefresh = true;
        await expectLater(
          api.active(),
          throwsA(
            isA<NutritionPlanApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.message,
                  'private details',
                  isNot(contains('private detail')),
                ),
          ),
        );
        expect(session.isAuthenticated, status != 401);
        if (status == 401) expect(store.value, isNull);
      },
    );
  }
  test(
    '401 read uses the existing single rotation and retries only with verified new bearer',
    () async {
      var reads = 0;
      resource = (r) async {
        reads++;
        await reply(
          r,
          r.headers.value('authorization') ==
                  'Bearer synthetic.version0.signature'
              ? 401
              : 200,
          program(),
        );
      };
      expect((await api.active())!.id, planId);
      expect(renewals, 1);
      expect(reads, 2);
      expect(session.isAuthenticated, isTrue);
    },
  );
  final badPrograms = <String, Map<String, Object?> Function()>{
    'archived': () => {...program(), 'status': 'archived'},
    'draft': () => {...program(), 'status': 'draft'},
    'missing nullable': () => program()..remove('endDate'),
    'wrong ownership reference': () => {
      ...program(),
      'items': [
        {...item(1), 'nutritionPlanId': expertId},
      ],
    },
    'invalid day': () => {
      ...program(),
      'items': [item(1, day: 8)],
    },
    'unknown meal': () => {
      ...program(),
      'items': [
        {...item(1), 'mealType': 'unknown'},
      ],
    },
    'unapproved food structure': () => {...program(), 'foods': []},
    'single alternative': () => {
      ...program(),
      'items': [item(1, group: expertId)],
    },
    'duplicate item': () => {
      ...program(),
      'items': [item(1), item(1)],
    },
    'invalid date': () => {...program(), 'startDate': '2026-02-30'},
    'negative target': () => {...program(), 'dailyCaloriesTargetKcal': -1},
    'invalid version': () => {...program(), 'versionNumber': 0},
  };
  for (final entry in badPrograms.entries) {
    test(
      'rejects ${entry.key} instead of displaying a malformed active program',
      () async {
        resource = (r) => reply(r, 200, entry.value());
        await expectLater(
          api.active(),
          throwsA(isA<NutritionPlanApiException>()),
        );
      },
    );
  }
  test('connection failure preserves the stored session', () async {
    await server.close(force: true);
    await expectLater(
      api.active(),
      throwsA(
        isA<NutritionPlanApiException>().having(
          (e) => e.message,
          'message',
          contains('Bağlantı'),
        ),
      ),
    );
    expect(session.isAuthenticated, isTrue);
    expect(store.value, isNotNull);
  });
}

Future<void> reply(HttpRequest r, int status, Object? body) async {
  r.response.statusCode = status;
  r.response.headers.contentType = ContentType.json;
  if (body != null) r.response.write(jsonEncode(body));
  await r.response.close();
}

class _Store implements RefreshTokenStore {
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
