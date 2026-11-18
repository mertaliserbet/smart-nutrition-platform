import 'dart:async';
import 'dart:io';

import '../auth/auth_session.dart';
import '../auth/login_api.dart';
import '../water/water_log_api.dart';
import 'nutrition_plan_api.dart';

const comparisonNutrients = {
  'caloriesKcal': ('Kalori', 'kcal'),
  'proteinGrams': ('Protein', 'g'),
  'carbsGrams': ('Karbonhidrat', 'g'),
  'fatGrams': ('Yağ', 'g'),
};

class NutritionValueSummary {
  const NutritionValueSummary(this.knownTotal, this.missingItemCount);
  final num knownTotal;
  final int missingItemCount;
}

class MealLogNutritionSummary {
  const MealLogNutritionSummary(
    this.mealLogCount,
    this.itemCount,
    this.estimatedItemCount,
    this.nutrients,
  );
  final int mealLogCount, itemCount, estimatedItemCount;
  final Map<String, NutritionValueSummary> nutrients;
}

class NutritionPlanMealComparison {
  const NutritionPlanMealComparison(
    this.mealType,
    this.plannedItems,
    this.actual,
  );
  final String mealType;
  final List<NutritionPlanItem> plannedItems;
  final MealLogNutritionSummary actual;
}

class NutritionPlanMealComparisonResponse {
  const NutritionPlanMealComparisonResponse({
    required this.plan,
    required this.versionCreatedAt,
    required this.day,
    required this.actual,
    required this.caloriesDifferenceKcal,
    required this.meals,
  });
  final NutritionPlanResponse plan;
  final DateTime versionCreatedAt;
  final WaterDayRange day;
  final MealLogNutritionSummary actual;
  final num? caloriesDifferenceKcal;
  final List<NutritionPlanMealComparison> meals;
}

class MealComparisonApi {
  MealComparisonApi(this.session);
  final AuthSession session;
  Future<NutritionPlanMealComparisonResponse> get(
    NutritionPlanResponse plan,
    WaterDayRange day,
  ) async {
    final owner = session.user?.id;
    try {
      final query = Uri(queryParameters: day.query).query;
      final response = await session.authorizedRequest(
        path:
            '/api/v1/nutrition-plans/${plan.id}/versions/${plan.versionId}/meal-comparison?$query',
        profileContext: 'client',
        maxResponseBytes: 2 * 1024 * 1024,
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw const MealComparisonApiException(
          'Oturum değişti. Lütfen tekrar giriş yapın.',
          statusCode: 401,
        );
      }
      if (response.statusCode != 200) {
        throw MealComparisonApiException(switch (response.statusCode) {
          401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
          403 => 'Bu karşılaştırmaya erişim izniniz doğrulanamadı.',
          404 =>
            'Program veya sürüm bulunamadı. Aktif programı yeniden yükleyin.',
          422 =>
            'Seçilen gün veya besin toplamları için karşılaştırma hesaplanamadı.',
          _ => 'Karşılaştırma yüklenemedi. Lütfen yeniden deneyin.',
        }, statusCode: response.statusCode);
      }
      return _parse(response.body, plan, day);
    } on LoginApiException catch (error) {
      throw MealComparisonApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
      );
    } on TimeoutException {
      throw const MealComparisonApiException(
        'Karşılaştırma isteği zaman aşımına uğradı. Yeniden deneyin.',
      );
    } on IOException {
      throw const MealComparisonApiException(
        'Güvenli bağlantı kurulamadı veya kesildi. Yeniden deneyin.',
      );
    } on FormatException {
      throw const MealComparisonApiException.invalid();
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const MealComparisonApiException.invalid();
    }
    return value;
  }

  static bool _count(Object? value) =>
      value is int && value >= 0 && value <= 2147483647;
  static DateTime _instant(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(value)) {
      throw const MealComparisonApiException.invalid();
    }
    return DateTime.tryParse(value)?.toUtc() ??
        (throw const MealComparisonApiException.invalid());
  }

  static void _items(Object? value, List<NutritionPlanItem> expected) {
    if (value is! List || value.length != expected.length) {
      throw const MealComparisonApiException.invalid();
    }
    for (var i = 0; i < expected.length; i++) {
      final row = _object(value[i], const [
        'id',
        'nutritionPlanId',
        'dayOfWeek',
        'mealType',
        'description',
        'recommendedQuantity',
        'sortOrder',
        'recipeId',
        'alternativeGroupId',
      ]);
      final item = expected[i];
      if (row['id'] != item.id ||
          row['nutritionPlanId'] != item.nutritionPlanId ||
          row['dayOfWeek'] != item.dayOfWeek ||
          row['mealType'] != item.mealType ||
          row['description'] != item.description ||
          row['recommendedQuantity'] != item.recommendedQuantity ||
          row['sortOrder'] != item.sortOrder ||
          row['recipeId'] != null ||
          row['alternativeGroupId'] != item.alternativeGroupId) {
        throw const MealComparisonApiException.invalid();
      }
    }
  }

  static MealLogNutritionSummary _summary(Object? value) {
    final row = _object(value, [
      'mealLogCount',
      'itemCount',
      'estimatedItemCount',
      ...comparisonNutrients.keys,
    ]);
    if (!_count(row['mealLogCount']) ||
        !_count(row['itemCount']) ||
        !_count(row['estimatedItemCount'])) {
      throw const MealComparisonApiException.invalid();
    }
    final count = row['itemCount'] as int,
        logs = row['mealLogCount'] as int,
        estimated = row['estimatedItemCount'] as int;
    if (logs > count || estimated > count || (logs == 0 && count != 0)) {
      throw const MealComparisonApiException.invalid();
    }
    final nutrients = <String, NutritionValueSummary>{};
    for (final key in comparisonNutrients.keys) {
      final nutrient = _object(row[key], const [
        'knownTotal',
        'missingItemCount',
      ]);
      final total = nutrient['knownTotal'],
          missing = nutrient['missingItemCount'];
      if (total is! num ||
          !total.isFinite ||
          total < 0 ||
          !_count(missing) ||
          (missing as int) > count ||
          (missing == count && total != 0)) {
        throw const MealComparisonApiException.invalid();
      }
      nutrients[key] = NutritionValueSummary(total, missing);
    }
    return MealLogNutritionSummary(
      logs,
      count,
      estimated,
      Map.unmodifiable(nutrients),
    );
  }

  static NutritionPlanMealComparisonResponse _parse(
    Object? value,
    NutritionPlanResponse plan,
    WaterDayRange day,
  ) {
    final row = _object(value, const [
      'clientId',
      'nutritionPlanVersion',
      'date',
      'from',
      'to',
      'actual',
      'caloriesDifferenceKcal',
      'meals',
    ]);
    final date = day.from.toIso8601String().substring(0, 10);
    final version = _object(row['nutritionPlanVersion'], const [
      'id',
      'nutritionPlanId',
      'versionNumber',
      'createdAt',
      'snapshot',
    ]);
    final snapshot = _object(version['snapshot'], const [
      'title',
      'startDate',
      'endDate',
      'dailyCaloriesTargetKcal',
      'dailyWaterTargetMl',
      'items',
    ]);
    if (row['clientId'] != plan.clientId ||
        row['date'] != date ||
        _instant(row['from']) != day.from.toUtc() ||
        _instant(row['to']) != day.to.toUtc() ||
        version['id'] != plan.versionId ||
        version['nutritionPlanId'] != plan.id ||
        version['versionNumber'] != plan.versionNumber ||
        snapshot['title'] != plan.title ||
        snapshot['startDate'] != plan.startDate ||
        snapshot['endDate'] != plan.endDate ||
        snapshot['dailyCaloriesTargetKcal'] != plan.dailyCaloriesTargetKcal ||
        snapshot['dailyWaterTargetMl'] != plan.dailyWaterTargetMl) {
      throw const MealComparisonApiException.invalid();
    }
    _items(snapshot['items'], plan.items);
    final actual = _summary(row['actual']);
    final difference = row['caloriesDifferenceKcal'];
    final canCalculate =
        actual.itemCount > 0 &&
        actual.nutrients['caloriesKcal']!.missingItemCount == 0 &&
        plan.dailyCaloriesTargetKcal != null;
    if ((difference != null && (difference is! num || !difference.isFinite)) ||
        (canCalculate != (difference != null))) {
      throw const MealComparisonApiException.invalid();
    }
    final groups = row['meals'];
    if (groups is! List || groups.length != nutritionMealLabels.length) {
      throw const MealComparisonApiException.invalid();
    }
    final meals = <NutritionPlanMealComparison>[];
    for (var i = 0; i < groups.length; i++) {
      final group = _object(groups[i], const [
        'mealType',
        'plannedItems',
        'actual',
      ]);
      final type = nutritionMealLabels.keys.elementAt(i);
      if (group['mealType'] != type) {
        throw const MealComparisonApiException.invalid();
      }
      final expected =
          plan.items
              .where(
                (item) =>
                    item.mealType == type &&
                    (item.dayOfWeek == null ||
                        item.dayOfWeek == day.from.weekday),
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _items(group['plannedItems'], expected);
      meals.add(
        NutritionPlanMealComparison(
          type,
          List.unmodifiable(expected),
          _summary(group['actual']),
        ),
      );
    }
    if (meals.fold(0, (sum, meal) => sum + meal.actual.mealLogCount) !=
            actual.mealLogCount ||
        meals.fold(0, (sum, meal) => sum + meal.actual.itemCount) !=
            actual.itemCount ||
        meals.fold(0, (sum, meal) => sum + meal.actual.estimatedItemCount) !=
            actual.estimatedItemCount ||
        comparisonNutrients.keys.any(
          (key) =>
              meals.fold(
                0,
                (sum, meal) =>
                    sum + meal.actual.nutrients[key]!.missingItemCount,
              ) !=
              actual.nutrients[key]!.missingItemCount,
        )) {
      throw const MealComparisonApiException.invalid();
    }
    return NutritionPlanMealComparisonResponse(
      plan: plan,
      versionCreatedAt: _instant(version['createdAt']),
      day: day,
      actual: actual,
      caloriesDifferenceKcal: difference as num?,
      meals: List.unmodifiable(meals),
    );
  }
}

class MealComparisonApiException implements Exception {
  const MealComparisonApiException(this.message, {this.statusCode});
  const MealComparisonApiException.invalid()
    : message =
          'Karşılaştırma yanıtı doğrulanamadı. Aktif programı yeniden yükleyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  @override
  String toString() => 'MealComparisonApiException';
}
