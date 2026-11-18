import '../nutrition/meal_log_api.dart';

class NutrientTotal {
  const NutrientTotal(this.value, this.known, this.missing);
  final num value;
  final int known, missing;
  factory NutrientTotal.from(Iterable<num?> values) {
    num total = 0;
    var known = 0, missing = 0;
    for (final value in values) {
      if (value == null) {
        missing++;
      } else {
        total += value;
        known++;
      }
    }
    if (!total.isFinite || total < 0) throw const MealLogApiException.invalid();
    return NutrientTotal(total, known, missing);
  }
  String label(String unit) => missing == 0
      ? '${dashboardNumber(value)} $unit'
      : known == 0
      ? 'Belirtilmemiş'
      : '${dashboardNumber(value)} $unit · Bilinen toplam';
}

class DashboardMeals {
  DashboardMeals(this.records)
    : calories = NutrientTotal.from(
        records.expand((row) => row.items).map((item) => item.caloriesKcal),
      ),
      protein = NutrientTotal.from(
        records.expand((row) => row.items).map((item) => item.proteinGrams),
      ),
      carbs = NutrientTotal.from(
        records.expand((row) => row.items).map((item) => item.carbsGrams),
      ),
      fat = NutrientTotal.from(
        records.expand((row) => row.items).map((item) => item.fatGrams),
      );
  final List<MealLog> records;
  final NutrientTotal calories, protein, carbs, fat;
}

String dashboardNumber(num number) =>
    number.toString().replaceFirst(RegExp(r'\.0$'), '').replaceAll('.', ',');
