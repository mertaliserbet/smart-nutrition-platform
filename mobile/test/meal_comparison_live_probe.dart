// Opt-in real HTTPS API check, restricted to the disposable test PostgreSQL.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_comparison_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'real HTTPS: assigned version, empty day, meal CRUD, missing macros and updated program',
    () async {
      final container = Platform.environment['SNP_SHARING_CONTAINER']!;
      expect(
        RegExp(r'^smart-nutrition-sharing-test-\d+$').hasMatch(container),
        isTrue,
      );
      final origin = Uri.parse('https://localhost:7101');
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final clientEmail = 'synthetic-sharing-client-$suffix@example.test';
      final expertEmail = 'synthetic-sharing-expert-$suffix@example.test';
      const password = 'Synthetic comparison integration password';
      Future<String> register(String email, bool expert) async {
        final response = await requestJson(
          timeout: const Duration(seconds: 20),
          method: 'POST',
          path: expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register',
          baseUri: origin,
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic comparison account',
            if (expert)
              'licenseInfo': 'Synthetic license'
            else
              'role': 'client',
          },
        );
        expect(response.statusCode, 201);
        return (response.body as Map)['id'] as String;
      }

      final userId = await register(clientEmail, false),
          expertUserId = await register(expertEmail, true);
      expect(
        RegExp(r'^[a-f0-9-]{36}$').hasMatch(userId) &&
            RegExp(r'^[a-f0-9-]{36}$').hasMatch(expertUserId),
        isTrue,
      );
      final seeded = await Process.run('docker', [
        'exec',
        container,
        'psql',
        '-U',
        'sharing_test',
        '-d',
        'sharing_test',
        '-Atc',
        "UPDATE users SET is_email_verified=true WHERE id IN ('$userId','$expertUserId'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='$expertUserId'; SELECT id FROM dietitian_profiles WHERE user_id='$expertUserId';",
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
        final connections = DietitianApi(client);
        final pending = await connections.request(dietitianId: expertId);
        final relation = await DietitianApi(
          expert,
        ).changeRelationship(pending, 'accept', asDietitian: true);
        await connections.setPermission(
          relationshipId: relation.id,
          isGranted: true,
        );
        final created = await expert.authorizedRequest(
          path: '/api/v1/nutrition-plans',
          method: 'POST',
          profileContext: 'dietitian',
          payload: {
            'clientId': relation.clientId,
            'title': 'Synthetic assigned comparison program',
            'startDate': '2026-01-01',
            'dailyCaloriesTargetKcal': 1000,
            'items': [
              for (var i = 0; i < 2; i++)
                {
                  'mealType': 'breakfast',
                  'description': 'Synthetic alternative $i',
                  'sortOrder': i,
                  'alternativeGroupId': '66666666-6666-4666-8666-666666666666',
                },
            ],
          },
        );
        expect(created.statusCode, 201);
        final planId = (created.body as Map)['id'] as String;
        final active = await expert.authorizedRequest(
          path: '/api/v1/nutrition-plans/$planId/activate',
          method: 'POST',
          profileContext: 'dietitian',
        );
        expect(active.statusCode, 200);
        final plans = NutritionPlanApi(client),
            comparison = MealComparisonApi(client),
            meals = MealLogApi(client);
        final day = WaterDayRange.forDate(DateTime(2026, 11, 18));
        var plan = (await plans.active())!;
        expect(plan.dietitianId, expertId);
        expect(plan.versionNumber, 1);
        expect((await comparison.get(plan, day)).actual.itemCount, 0);
        Map<String, Object?> food({num? calories = 125.5, num? protein}) => {
          'displayName': 'Synthetic meal',
          'isEstimated': false,
          'caloriesKcal': calories,
          'proteinGrams': protein,
          'carbsGrams': 20,
          'fatGrams': 0,
        };
        final meal = await meals.create({
          'mealType': 'lunch',
          'consumedAt': waterOffsetIso(DateTime(2026, 11, 18, 12)),
          'source': 'manual',
          'items': [food()],
        });
        var result = await comparison.get(plan, day);
        expect(result.caloriesDifferenceKcal, -874.5);
        expect(result.actual.nutrients['proteinGrams']!.missingItemCount, 1);
        expect(result.meals.first.plannedItems, hasLength(2));
        expect(result.meals[1].actual.itemCount, 1);
        expect(
          (await comparison.get(
            plan,
            WaterDayRange.forDate(DateTime(2026, 11, 19)),
          )).actual.itemCount,
          0,
        );
        await meals.update(meal.id, {
          'items': [food(calories: null, protein: 5)],
        });
        result = await comparison.get(plan, day);
        expect(result.caloriesDifferenceKcal, isNull);
        expect(result.actual.nutrients['caloriesKcal']!.missingItemCount, 1);
        expect(result.actual.nutrients['proteinGrams']!.knownTotal, 5);
        await meals.update(meal.id, {
          'items': [food(protein: 5)],
        });
        final changed = await expert.authorizedRequest(
          path: '/api/v1/nutrition-plans/$planId',
          method: 'PATCH',
          profileContext: 'dietitian',
          payload: {'dailyCaloriesTargetKcal': 2000},
        );
        expect(changed.statusCode, 200);
        final previous = plan.versionId;
        plan = (await plans.active())!;
        expect(plan.versionId, isNot(previous));
        expect(plan.versionNumber, 2);
        expect(
          (await comparison.get(plan, day)).caloriesDifferenceKcal,
          -1874.5,
        );
        // Own comparison works without granting meal sharing; expert access still requires both categories.
        final denied = await expert.authorizedRequest(
          path:
              '/api/v1/nutrition-plans/$planId/versions/${plan.versionId}/meal-comparison?${Uri(queryParameters: day.query).query}',
          profileContext: 'dietitian',
        );
        expect(denied.statusCode, 403);
        await meals.delete(meal.id);
        result = await comparison.get(plan, day);
        expect(result.actual.itemCount, 0);
        expect(result.caloriesDifferenceKcal, isNull);
      } finally {
        if (client.isAuthenticated) {
          await client.signOut();
        }
        if (expert.isAuthenticated) {
          await expert.signOut();
        }
        client.dispose();
        expert.dispose();
      }
    },
    skip: Platform.environment['SNP_COMPARISON_LIVE'] != '1',
  );
}
