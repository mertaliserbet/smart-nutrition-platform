// Synthetic, in-memory responses to the existing API contract. No network/DB.
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'water_test_support.dart';

class DayTestSession extends WaterTestSession {
  bool hasPlan = true, assigned = true, hasMeals = true, hasTargets = true;
  num water = 750;
  int waterCreates = 0;
  final requests = <String>[];
  final instant = DateTime.utc(2026, 11, 24, 8).toIso8601String();
  static const planId = '66666666-6666-4666-8666-666666666666';
  static const versionId = '77777777-7777-4777-8777-777777777777';

  @override
  CurrentUserResponse? get user => authenticated
      ? CurrentUserResponse(
          id: owner,
          displayName: 'Mert Ali Örnek',
          email: 'mert-ali@example.test',
          role: 'client',
          isEmailVerified: true,
        )
      : null;

  @override
  Future<JsonApiResponse> authorizedRequest({
    required String path,
    Map<String, Object?>? payload,
    String? profileContext,
    String? method,
    int maxResponseBytes = 65536,
  }) async {
    requests.add(path);
    final uri = Uri.parse(path);
    Object? body;
    var status = 200;
    if (uri.path == '/api/v1/nutrition-plans/active') {
      if (!hasPlan) {
        return (statusCode: 404, body: null, hasBody: false, retryAfter: null);
      }
      body = <String, dynamic>{
        'id': planId,
        'clientId': owner,
        'dietitianId': assigned ? waterClientId : null,
        'title': 'Dengeli gün planı',
        'status': 'active',
        'startDate': '2026-11-01',
        'endDate': null,
        'dailyCaloriesTargetKcal': 1700,
        'dailyWaterTargetMl': 2000,
        'createdAt': instant,
        'versionId': versionId,
        'versionNumber': 1,
        'items': [
          for (final (index, meal) in [
            ('breakfast', 'Yulaf, yoğurt ve meyve'),
            ('lunch', 'Izgara tavuk · Bulgur · Salata'),
            ('snack', 'Meyve ve badem'),
          ].indexed)
            <String, dynamic>{
              'id': '88888888-8888-4888-8888-88888888888$index',
              'nutritionPlanId': planId,
              'dayOfWeek': null,
              'mealType': meal.$1,
              'description': meal.$2,
              'recommendedQuantity': null,
              'recipeId': null,
              'sortOrder': index,
              'alternativeGroupId': null,
            },
        ],
      };
    } else if (uri.path == '/api/v1/meal-logs') {
      if (!hasMeals) {
        return (
          statusCode: 200,
          body: <String, dynamic>{'items': [], 'totalCount': 0},
          hasBody: true,
          retryAfter: null,
        );
      }
      final consumed = DateTime.parse(
        uri.queryParameters['from']!,
      ).add(const Duration(hours: 8)).toUtc().toIso8601String();
      body = <String, dynamic>{
        'totalCount': 1,
        'items': [
          <String, dynamic>{
            'id': waterId,
            'clientId': owner,
            'mealType': 'breakfast',
            'consumedAt': consumed,
            'createdAt': consumed,
            'source': 'manual',
            'note': null,
            'foodAnalysisId': null,
            'items': [
              <String, dynamic>{
                'id': waterClientId,
                'mealLogId': waterId,
                'displayName': 'Sentetik kahvaltı',
                'foodItemId': null,
                'recipeId': null,
                'quantityGrams': null,
                'caloriesKcal': 980,
                'proteinGrams': 62,
                'carbsGrams': 110,
                'fatGrams': 32,
                'isEstimated': false,
              },
            ],
          },
        ],
      };
    } else if (uri.path == '/api/v1/personal-nutrition-targets') {
      body = <String, dynamic>{
        'source': 'personal',
        'dailyCaloriesTargetKcal': hasTargets ? 1700 : null,
        'dailyProteinTargetGrams': hasTargets ? 110 : null,
        'dailyCarbsTargetGrams': hasTargets ? 180 : null,
        'dailyFatTargetGrams': hasTargets ? 60 : null,
        'dailyWaterTargetMl': hasTargets ? 2000 : null,
      };
    } else if (uri.path == '/api/v1/water-logs/daily-total') {
      body = <String, dynamic>{
        'from': DateTime.parse(
          uri.queryParameters['from']!,
        ).toUtc().toIso8601String(),
        'to': DateTime.parse(
          uri.queryParameters['to']!,
        ).toUtc().toIso8601String(),
        'totalAmountMl': water,
      };
    } else if (uri.path == '/api/v1/water-logs' && method == 'POST') {
      waterCreates++;
      water += payload!['amountMl'] as num;
      status = 201;
      body = <String, dynamic>{
        'id': waterId,
        'clientId': owner,
        'amountMl': payload['amountMl'],
        'consumedAt': DateTime.parse(
          payload['consumedAt']! as String,
        ).toUtc().toIso8601String(),
        'source': 'manual',
      };
    } else {
      body = <String, dynamic>{'items': [], 'totalCount': 0};
    }
    return (statusCode: status, body: body, hasBody: true, retryAfter: null);
  }
}
