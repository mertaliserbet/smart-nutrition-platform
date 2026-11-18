import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_comparison_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'meal_comparison_test_support.dart';
import 'water_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late MealComparisonApi api;
  late Future<void> Function(HttpRequest) resource;
  final plan = comparisonPlan();
  final day = WaterDayRange.forDate(DateTime(2026, 11, 18));
  var refreshes = 0;
  Future<void> reply(HttpRequest request, int status, Object? body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    if (body != null) {
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  }

  setUp(() async {
    refreshes = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final refreshExpiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object> tokens(int version) => {
      'accessToken': 'synthetic.comparison$version.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'refreshToken': (version == 0 ? 'A' : 'B') * 43,
      'refreshTokenExpiresAt': refreshExpiry.toIso8601String(),
    };
    resource = (request) => reply(request, 200, comparisonJson(plan, day));
    server.listen((request) async {
      switch (request.uri.path) {
        case '/api/v1/auth/login':
          await request.drain<void>();
          await reply(request, 200, tokens(0));
        case '/api/v1/auth/me':
          await reply(request, 200, {
            'id': '99999999-9999-4999-8999-999999999999',
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          refreshes++;
          await request.drain<void>();
          await reply(request, 200, tokens(1));
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
        password: 'Synthetic comparison password',
      ),
      isTrue,
    );
    api = MealComparisonApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'GET uses active version, client JWT and encoded local midnight boundaries without clientId',
    () async {
      resource = (request) async {
        expect(request.method, 'GET');
        expect(
          request.uri.path,
          '/api/v1/nutrition-plans/${plan.id}/versions/${plan.versionId}/meal-comparison',
        );
        expect(request.uri.queryParameters, day.query);
        expect(request.headers.value('x-profile-context'), 'client');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic.comparison0.signature',
        );
        expect(request.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(request).join(), isEmpty);
        await reply(request, 200, comparisonJson(plan, day));
      };
      final result = await api.get(plan, day);
      expect(result.actual.nutrients['proteinGrams']!.missingItemCount, 2);
      expect(result.actual.nutrients['fatGrams']!.knownTotal, 0);
      expect(result.caloriesDifferenceKcal, isNull);
      expect(result.meals.first.plannedItems, hasLength(2));
    },
  );
  test('GET refreshes once on 401 and keeps client context', () async {
    var calls = 0;
    resource = (request) async {
      calls++;
      expect(request.headers.value('x-profile-context'), 'client');
      await reply(
        request,
        calls == 1 ? 401 : 200,
        calls == 1 ? null : comparisonJson(plan, day),
      );
    };
    await api.get(plan, day);
    expect(calls, 2);
    expect(refreshes, 1);
  });
  for (final status in [403, 404, 422, 500]) {
    test(
      'status $status remains an error and is not an empty or zero comparison',
      () async {
        var calls = 0;
        resource = (request) async {
          calls++;
          await reply(request, status, null);
        };
        await expectLater(
          api.get(plan, day),
          throwsA(
            isA<MealComparisonApiException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }
  for (final field in [
    'client',
    'version',
    'date',
    'from',
    'snapshot',
    'planned',
    'groups',
    'count',
    'missing',
    'negative',
    'difference',
  ]) {
    test('malformed or mismatched $field fails closed', () async {
      final body = comparisonJson(plan, day);
      switch (field) {
        case 'client':
          body['clientId'] = plan.id;
        case 'version':
          body['nutritionPlanVersion']['id'] = plan.id;
        case 'date':
          body['date'] = '2026-11-17';
        case 'from':
          body['from'] = '2026-11-18T00:00:00';
        case 'snapshot':
          body['nutritionPlanVersion']['snapshot']['title'] =
              'Different content';
        case 'planned':
          body['meals'][0]['plannedItems'] = [];
        case 'groups':
          (body['meals'] as List).removeLast();
        case 'count':
          body['actual']['mealLogCount'] = 2;
        case 'missing':
          body['actual']['proteinGrams']['missingItemCount'] = 3;
        case 'negative':
          body['actual']['fatGrams']['knownTotal'] = -1;
        case 'difference':
          body['caloriesDifferenceKcal'] = 0;
      }
      resource = (request) => reply(request, 200, body);
      await expectLater(
        api.get(plan, day),
        throwsA(isA<MealComparisonApiException>()),
      );
    });
  }
  test(
    'empty day and genuine complete calorie difference remain distinct',
    () async {
      resource = (request) =>
          reply(request, 200, comparisonJson(plan, day, empty: true));
      expect((await api.get(plan, day)).actual.itemCount, 0);
      resource = (request) =>
          reply(request, 200, comparisonJson(plan, day, complete: true));
      expect((await api.get(plan, day)).caloriesDifferenceKcal, -874.5);
    },
  );
  test('late previous-owner comparison cannot survive logout', () async {
    final started = Completer<void>(), release = Completer<void>();
    resource = (request) async {
      started.complete();
      await release.future;
      await reply(request, 200, comparisonJson(plan, day));
    };
    final pending = api.get(plan, day);
    await started.future;
    await session.signOut();
    release.complete();
    await expectLater(
      pending,
      throwsA(
        isA<MealComparisonApiException>().having(
          (e) => e.statusCode,
          'owner',
          401,
        ),
      ),
    );
  });
  test('independent midnight offsets support 23 and 25 hour days', () async {
    for (final spring in [true, false]) {
      final date = DateTime.utc(2026, spring ? 3 : 10, spring ? 29 : 25);
      final range = WaterDayRange.forDate(
        date,
        localDate: (year, month, number) => _OffsetDate(
          DateTime.utc(year, month, number),
          Duration(
            hours: number == date.day ? (spring ? 1 : 2) : (spring ? 2 : 1),
          ),
        ),
      );
      resource = (request) async {
        expect(request.uri.queryParameters, range.query);
        expect(request.uri.query, contains('%2B'));
        await reply(request, 200, comparisonJson(plan, range));
      };
      await api.get(plan, range);
      expect(
        range.to.toUtc().difference(range.from.toUtc()).inHours,
        spring ? 23 : 25,
      );
    }
  });
}

class _OffsetDate extends Fake implements DateTime {
  _OffsetDate(this.wall, this.offset);
  final DateTime wall;
  final Duration offset;
  @override
  bool get isUtc => false;
  @override
  Duration get timeZoneOffset => offset;
  @override
  int get weekday => wall.weekday;
  @override
  String toIso8601String() =>
      wall.toIso8601String().replaceFirst(RegExp(r'Z$'), '');
  @override
  DateTime toUtc() => wall.subtract(offset);
}
