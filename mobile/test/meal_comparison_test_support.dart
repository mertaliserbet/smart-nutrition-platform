import 'dart:convert';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_comparison_api.dart';

const comparisonPlanId = '11111111-1111-4111-8111-111111111111';
const comparisonClientId = '22222222-2222-4222-8222-222222222222';
const comparisonExpertId = '33333333-3333-4333-8333-333333333333';
NutritionPlanResponse comparisonPlan({
  int version = 1,
  String? endDate,
  bool personal = false,
}) => NutritionPlanResponse(
  id: comparisonPlanId,
  clientId: comparisonClientId,
  dietitianId: personal ? null : comparisonExpertId,
  title: 'Sentetik atanmış program',
  startDate: '2026-01-01',
  endDate: endDate,
  dailyCaloriesTargetKcal: 1000,
  dailyWaterTargetMl: null,
  createdAt: DateTime.utc(2026, 1, 1),
  versionId: '55555555-5555-4555-8555-${version.toString().padLeft(12, '0')}',
  versionNumber: version,
  items: [
    for (var i = 1; i <= 2; i++)
      NutritionPlanItem(
        id: '44444444-4444-4444-8444-${i.toString().padLeft(12, '0')}',
        nutritionPlanId: comparisonPlanId,
        dayOfWeek: null,
        mealType: 'breakfast',
        description: i == 1 ? 'Yulaf' : 'Yoğurt',
        recommendedQuantity: i == 1 ? '1 kâse' : null,
        sortOrder: i,
        alternativeGroupId: '66666666-6666-4666-8666-666666666666',
      ),
  ],
);
Map<String, Object?> comparisonItemJson(NutritionPlanItem item) => {
  'id': item.id,
  'nutritionPlanId': item.nutritionPlanId,
  'dayOfWeek': item.dayOfWeek,
  'mealType': item.mealType,
  'description': item.description,
  'recommendedQuantity': item.recommendedQuantity,
  'sortOrder': item.sortOrder,
  'recipeId': null,
  'alternativeGroupId': item.alternativeGroupId,
};
Map<String, Object?> comparisonPlanJson(NutritionPlanResponse plan) => {
  'id': plan.id,
  'clientId': plan.clientId,
  'dietitianId': plan.dietitianId,
  'title': plan.title,
  'status': 'active',
  'startDate': plan.startDate,
  'endDate': plan.endDate,
  'dailyCaloriesTargetKcal': plan.dailyCaloriesTargetKcal,
  'dailyWaterTargetMl': plan.dailyWaterTargetMl,
  'createdAt': plan.createdAt.toIso8601String(),
  'versionId': plan.versionId,
  'versionNumber': plan.versionNumber,
  'items': plan.items.map(comparisonItemJson).toList(),
};
Map<String, dynamic> comparisonJson(
  NutritionPlanResponse plan,
  WaterDayRange day, {
  bool empty = false,
  bool complete = false,
}) {
  Map<String, Object> nutrient(num value, int missing) => {
    'knownTotal': value,
    'missingItemCount': missing,
  };
  Map<String, Object> summary(bool recorded) => {
    'mealLogCount': recorded ? 1 : 0,
    'itemCount': recorded ? 2 : 0,
    'estimatedItemCount': recorded ? 1 : 0,
    'caloriesKcal': nutrient(
      recorded ? 125.5 : 0,
      recorded && !complete ? 1 : 0,
    ),
    'proteinGrams': nutrient(0, recorded ? 2 : 0),
    'carbsGrams': nutrient(recorded ? 30 : 0, 0),
    'fatGrams': nutrient(0, 0),
  };
  return jsonDecode(
        jsonEncode({
          'clientId': plan.clientId,
          'nutritionPlanVersion': {
            'id': plan.versionId,
            'nutritionPlanId': plan.id,
            'versionNumber': plan.versionNumber,
            'createdAt': '2026-01-01T00:00:00Z',
            'snapshot': {
              'title': plan.title,
              'startDate': plan.startDate,
              'endDate': plan.endDate,
              'dailyCaloriesTargetKcal': plan.dailyCaloriesTargetKcal,
              'dailyWaterTargetMl': plan.dailyWaterTargetMl,
              'items': plan.items.map(comparisonItemJson).toList(),
            },
          },
          'date': day.from.toIso8601String().substring(0, 10),
          'from': day.from.toUtc().toIso8601String(),
          'to': day.to.toUtc().toIso8601String(),
          'actual': summary(!empty),
          'caloriesDifferenceKcal': !empty && complete ? -874.5 : null,
          'meals': [
            for (final type in nutritionMealLabels.keys)
              {
                'mealType': type,
                'plannedItems': plan.items
                    .where(
                      (item) =>
                          item.mealType == type &&
                          (item.dayOfWeek == null ||
                              item.dayOfWeek == day.from.weekday),
                    )
                    .map(comparisonItemJson)
                    .toList(),
                'actual': summary(!empty && type == 'lunch'),
              },
          ],
        }),
      )
      as Map<String, dynamic>;
}

NutritionPlanMealComparisonResponse comparisonResponse(
  NutritionPlanResponse plan,
  WaterDayRange day, {
  bool empty = false,
  bool complete = false,
}) {
  MealLogNutritionSummary summary(bool recorded) => MealLogNutritionSummary(
    recorded ? 1 : 0,
    recorded ? 2 : 0,
    recorded ? 1 : 0,
    {
      'caloriesKcal': NutritionValueSummary(
        recorded ? 125.5 : 0,
        recorded && !complete ? 1 : 0,
      ),
      'proteinGrams': NutritionValueSummary(0, recorded ? 2 : 0),
      'carbsGrams': NutritionValueSummary(recorded ? 30 : 0, 0),
      'fatGrams': const NutritionValueSummary(0, 0),
    },
  );
  return NutritionPlanMealComparisonResponse(
    plan: plan,
    versionCreatedAt: DateTime.utc(2026, 1, 1),
    day: day,
    actual: summary(!empty),
    caloriesDifferenceKcal: !empty && complete ? -874.5 : null,
    meals: [
      for (final type in nutritionMealLabels.keys)
        NutritionPlanMealComparison(
          type,
          plan.items
              .where(
                (item) =>
                    item.mealType == type &&
                    (item.dayOfWeek == null ||
                        item.dayOfWeek == day.from.weekday),
              )
              .toList(),
          summary(!empty && type == 'lunch'),
        ),
    ],
  );
}
