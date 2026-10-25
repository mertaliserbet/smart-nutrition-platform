/// Synthetic presentation fixtures only: no API DTOs, persistence or advice.
/// Targets illustrate the design and do not define the open target contract.
abstract final class DashboardDemo {
  static const disclaimer =
      'Tüm değerler örnektir; size ait veri veya kişisel hedef önerisi değildir.';
  static const dateLabel = '24 Ekim 2026 · Örnek gün';

  static const calories = DashboardDemoMetric('Kalori', 1680, 2200, 'kcal');
  static const macros = [
    DashboardDemoMetric('Protein', 84, 110, 'g'),
    DashboardDemoMetric('Karbonhidrat', 192, 260, 'g'),
    DashboardDemoMetric('Yağ', 64, 72, 'g'),
  ];
  static const water = DashboardDemoMetric('Su', 1250, 2500, 'mL');
  static const mealLogs = [
    DashboardDemoMealLogPreview(
      mealLabel: 'Ara öğün',
      timeLabel: '16.00',
      displayName: 'Yoğurt, meyve ve ceviz',
      caloriesKcal: 480,
    ),
    DashboardDemoMealLogPreview(
      mealLabel: 'Öğle',
      timeLabel: '12.45',
      displayName: 'Sebzeli bulgur ve yoğurt',
      caloriesKcal: 720,
    ),
    DashboardDemoMealLogPreview(
      mealLabel: 'Kahvaltı',
      timeLabel: '08.30',
      displayName: 'Yumurta ve tam tahıllı ekmek',
      caloriesKcal: 480,
    ),
  ];

  static const personal = DashboardDemoData(
    calories: calories,
    macros: macros,
    water: water,
    mealLogs: mealLogs,
    nutritionPlanTitle: 'Günlük denge',
    nutritionPlanDescription: 'Ana ve ara öğünler için örnek bir günlük düzen.',
  );

  static const assigned = DashboardDemoData(
    calories: calories,
    macros: macros,
    water: water,
    mealLogs: mealLogs,
    nutritionPlanTitle: 'Dengeli gün örneği',
    nutritionPlanDescription: 'Diyetisyen tarafından atanan örnek program.',
    dietitianDisplayName: 'Örnek Diyetisyen',
  );
}

class DashboardDemoData {
  const DashboardDemoData({
    required this.calories,
    required this.macros,
    required this.water,
    required this.mealLogs,
    required this.nutritionPlanTitle,
    required this.nutritionPlanDescription,
    this.dietitianDisplayName,
  });

  final DashboardDemoMetric calories;
  final List<DashboardDemoMetric> macros;
  final DashboardDemoMetric water;
  final List<DashboardDemoMealLogPreview> mealLogs;
  final String nutritionPlanTitle;
  final String nutritionPlanDescription;
  final String? dietitianDisplayName;
}

class DashboardDemoMetric {
  const DashboardDemoMetric(this.label, this.value, this.target, this.unit);

  final String label;
  final int value;
  final int target;
  final String unit;

  double get progress => (value / target).clamp(0.0, 1.0);
  int get percentage => (value / target * 100).round();
}

class DashboardDemoMealLogPreview {
  const DashboardDemoMealLogPreview({
    required this.mealLabel,
    required this.timeLabel,
    required this.displayName,
    required this.caloriesKcal,
  });

  final String mealLabel;
  final String timeLabel;
  final String displayName;
  final int caloriesKcal;
}
