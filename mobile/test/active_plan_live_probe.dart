// Opt-in real API test: flutter test test/active_plan_live_probe.dart.
// The caller provisions/cleans only disposable SNP_PLAN_* accounts and Mailpit messages.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/api_config.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';

void main() {
  test(
    'real HTTPS: web-cookie assignment and version change become mobile active plan; end clears it',
    () async {
      String input(String key) {
        final value = Platform.environment['SNP_PLAN_$key'];
        if (value == null || value.isEmpty) {
          throw StateError('Missing disposable input: $key');
        }
        return value;
      }

      final origin = ApiConfig.validate(input('ORIGIN'), allowLocalHttp: false);
      expect(origin.host, 'localhost');
      expect(input('CLIENT').startsWith('synthetic-plan-'), isTrue);
      final session = AuthSession(
        api: LoginApi(baseUri: origin),
        store: _Store(),
      );
      final web = _Web(origin);
      try {
        await session.initialize();
        expect(
          await session.signIn(
            email: input('CLIENT'),
            password: input('PASSWORD'),
          ),
          isTrue,
        );
        final api = NutritionPlanApi(session), links = DietitianApi(session);
        expect(await api.active(), isNull);
        final pending = await links.request(dietitianId: input('EXPERT_ID'));
        await web.login(input('EXPERT'), input('PASSWORD'));
        expect(
          (await web.send(
            'dietitian-relationships/${pending.id}/accept',
            method: 'POST',
          )).statusCode,
          200,
        );
        final permission = await links.setPermission(
          relationshipId: pending.id,
          isGranted: true,
        );
        final draft = await web.send(
          'nutrition-plans',
          method: 'POST',
          body: {
            'clientId': pending.clientId,
            'title': 'Sentetik atanmış program',
            'startDate': '2026-11-03',
            'items': [
              {
                'dayOfWeek': null,
                'mealType': 'breakfast',
                'description': 'Sentetik yulaf ve yoğurt 🥣',
                'recommendedQuantity': '1 kâse',
                'sortOrder': 0,
              },
              {
                'dayOfWeek': 1,
                'mealType': 'lunch',
                'description': 'Sentetik sebze öğünü',
                'recommendedQuantity': null,
                'sortOrder': 1,
              },
            ],
          },
        );
        expect(draft.statusCode, 201);
        final id = draft.body['id'] as String;
        expect(await api.active(), isNull); // Draft is not an assignment.
        expect(
          (await web.send(
            'nutrition-plans/$id/activate',
            method: 'POST',
          )).statusCode,
          200,
        );
        final active = (await api.active())!;
        expect(active.id, id);
        expect(active.dietitianId, input('EXPERT_ID'));
        expect(active.versionNumber, 1);
        expect(active.items.first.description, 'Sentetik yulaf ve yoğurt 🥣');
        expect(active.items.first.recommendedQuantity, '1 kâse');
        expect(active.items.last.dayOfWeek, 1);
        expect(active.dailyCaloriesTargetKcal, isNull);
        final edit = await session.authorizedRequest(
          path: '/api/v1/nutrition-plans/$id',
          method: 'PATCH',
          payload: {'title': 'Forbidden client edit'},
          profileContext: 'client',
        );
        expect(edit.statusCode, 403);
        expect(
          (await web.send(
            'nutrition-plans/$id',
            method: 'PATCH',
            body: {'title': 'Sentetik güncel program'},
          )).statusCode,
          200,
        );
        final updated = (await api.active())!;
        expect(updated.title, 'Sentetik güncel program');
        expect(updated.versionNumber, 2);
        expect(updated.versionId, isNot(active.versionId));
        await links.setPermission(
          relationshipId: pending.id,
          isGranted: false,
          current: permission,
        );
        expect(
          (await api.active())!.id,
          id,
        ); // Client access does not require expert-sharing consent.
        final relationship = (await links.relationships(
          status: 'active',
        )).items.single;
        await links.endRelationship(relationship);
        expect(await api.active(), isNull);
        final ownHistory = await session.authorizedRequest(
          path: '/api/v1/nutrition-plans/$id',
          profileContext: 'client',
        );
        expect(ownHistory.statusCode, 200);
        expect((ownHistory.body as Map)['status'], 'archived');
        expect((await web.send('nutrition-plans/$id')).statusCode, 404);
      } finally {
        await session.signOut();
        session.dispose();
        await web.close();
      }
    },
  );
}

class _Web {
  _Web(this.origin);
  final Uri origin;
  final _http = HttpClient(context: ApiConfig.developmentSecurityContext);
  final _cookies = <String, Cookie>{};
  bool _loggedIn = false;
  Future<({int statusCode, Map<String, dynamic> body})> send(
    String path, {
    String method = 'GET',
    Object? body,
    String? csrf,
  }) async {
    if (method != 'GET' && csrf == null) {
      csrf = (await send('auth/csrf')).body['requestToken'] as String;
    }
    final request = await _http.openUrl(
      method,
      origin.resolve('/api/v1/$path'),
    );
    request.followRedirects = false;
    request.cookies.addAll(_cookies.values);
    request.headers.set('X-Profile-Context', 'dietitian');
    if (method != 'GET') {
      request.headers.set('Origin', 'https://localhost:5173');
      request.headers.set('X-CSRF-TOKEN', csrf!);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie;
    }
    final text = await utf8.decoder.bind(response).join();
    return (
      statusCode: response.statusCode,
      body: text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<void> login(String email, String password) async {
    final response = await send(
      'auth/web-session',
      method: 'POST',
      body: {'email': email, 'password': password},
    );
    expect(response.statusCode, 200);
    _loggedIn = true;
  }

  Future<void> close() async {
    try {
      if (_loggedIn) await send('auth/web-session', method: 'DELETE');
    } finally {
      _http.close(force: true);
    }
  }
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
