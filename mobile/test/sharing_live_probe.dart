// Opt-in HTTPS check against a disposable PostgreSQL container only.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'real HTTPS: three independent sharing grants/revokes, active relationship and ownership',
    () async {
      final container = Platform.environment['SNP_SHARING_CONTAINER']!;
      expect(
        RegExp(r'^smart-nutrition-sharing-test-\d+$').hasMatch(container),
        isTrue,
      );
      final origin = Uri.parse('https://localhost:7101');
      final tag = DateTime.now().microsecondsSinceEpoch;
      final clientEmail = 'synthetic-sharing-client-$tag@example.test';
      final expertEmail = 'synthetic-sharing-expert-$tag@example.test';
      const password = 'Synthetic sharing integration password';
      Future<String> register(String email, bool expert) async {
        final response = await requestJson(
          method: 'POST',
          path: expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register',
          baseUri: origin,
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic sharing account',
            if (expert)
              'licenseInfo': 'Synthetic test license'
            else
              'role': 'client',
          },
          timeout: const Duration(seconds: 20),
        );
        expect(response.statusCode, 201);
        return (response.body as Map)['id'] as String;
      }

      final clientId = await register(clientEmail, false),
          expertUser = await register(expertEmail, true);
      expect(
        RegExp(r'^[a-f0-9-]{36}$').hasMatch(clientId) &&
            RegExp(r'^[a-f0-9-]{36}$').hasMatch(expertUser),
        isTrue,
      );
      // Match the backend integration fixtures: verification is restricted to our isolated synthetic users.
      final sql =
          "UPDATE users SET is_email_verified=true WHERE id IN ('$clientId','$expertUser'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='$expertUser'; SELECT id FROM dietitian_profiles WHERE user_id='$expertUser';";
      final seeded = await Process.run('docker', [
        'exec',
        container,
        'psql',
        '-U',
        'sharing_test',
        '-d',
        'sharing_test',
        '-Atc',
        sql,
      ]);
      expect(seeded.exitCode, 0);
      final expertId = seeded.stdout.toString().trim().split('\n').last.trim();
      final client = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      final expert = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      try {
        await client.initialize();
        await expert.initialize();
        expect(
          await client.signIn(email: clientEmail, password: password),
          isTrue,
        );
        expect(
          await expert.signIn(email: expertEmail, password: password),
          isTrue,
        );
        final api = DietitianApi(client), experts = DietitianApi(expert);
        final pending = await api.request(dietitianId: expertId);
        await expectLater(
          api.setPermission(
            relationshipId: pending.id,
            category: 'meal_logs',
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'pending',
              409,
            ),
          ),
        );
        final active = await experts.changeRelationship(
          pending,
          'accept',
          asDietitian: true,
        );
        expect(await api.permissions(active.id), isEmpty);
        var program = await api.setPermission(
          relationshipId: active.id,
          isGranted: true,
        );
        expect(
          (await api.permissions(
            active.id,
          )).any((p) => p.category == 'meal_logs'),
          isFalse,
        );
        var meals = await api.setPermission(
          relationshipId: active.id,
          category: 'meal_logs',
          isGranted: true,
        );
        expect(
          (await api.permissions(active.id)).where((p) => p.isGranted),
          hasLength(2),
        );
        expect(
          (await api.permissions(
            active.id,
          )).any((p) => p.category == 'body_measurements'),
          isFalse,
        );
        var measurements = await api.setPermission(
          relationshipId: active.id,
          category: 'body_measurements',
          isGranted: true,
        );
        expect(
          {
            for (final p in await api.permissions(active.id))
              p.category: p.isGranted,
          },
          {
            'nutrition_plans': true,
            'meal_logs': true,
            'body_measurements': true,
          },
        );
        measurements = await api.setPermission(
          relationshipId: active.id,
          category: 'body_measurements',
          current: measurements,
          isGranted: false,
        );
        expect(
          {
            for (final p in await api.permissions(active.id))
              p.category: p.isGranted,
          },
          {
            'nutrition_plans': true,
            'meal_logs': true,
            'body_measurements': false,
          },
        );
        measurements = await api.setPermission(
          relationshipId: active.id,
          category: 'body_measurements',
          current: measurements,
          isGranted: true,
        );
        program = await api.setPermission(
          relationshipId: active.id,
          current: program,
          isGranted: false,
        );
        expect(
          (await api.permissions(
            active.id,
          )).singleWhere((p) => p.category == 'meal_logs').isGranted,
          isTrue,
        );
        meals = await api.setPermission(
          relationshipId: active.id,
          category: 'meal_logs',
          current: meals,
          isGranted: false,
        );
        expect(
          {
            for (final p in await api.permissions(active.id))
              p.category: p.isGranted,
          },
          {
            'nutrition_plans': false,
            'meal_logs': false,
            'body_measurements': true,
          },
        );
        measurements = await api.setPermission(
          relationshipId: active.id,
          category: 'body_measurements',
          current: measurements,
          isGranted: false,
        );
        expect(
          (await api.permissions(active.id)).every((p) => !p.isGranted),
          isTrue,
        );
        expect(measurements.isGranted, isFalse);
        expect(program.isGranted, isFalse);
        expect(meals.isGranted, isFalse);
        await expectLater(
          experts.setPermission(
            relationshipId: active.id,
            category: 'meal_logs',
            current: meals,
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'expert cannot grant client consent',
              403,
            ),
          ),
        );
        await api.endRelationship(active);
        await expectLater(
          api.setPermission(
            relationshipId: active.id,
            category: 'meal_logs',
            current: meals,
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'ended',
              409,
            ),
          ),
        );
      } finally {
        if (client.isAuthenticated) await client.signOut();
        if (expert.isAuthenticated) await expert.signOut();
        client.dispose();
        expert.dispose();
      }
    },
    skip: Platform.environment['SNP_SHARING_LIVE'] != '1',
  );
}
