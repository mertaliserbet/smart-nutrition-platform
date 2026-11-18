import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/home/dashboard_data.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'water_test_support.dart';

MealLog meal({
  num? calories = 125,
  num? protein = 10,
  String name = 'Sentetik öğün',
}) => MealLog(
  id: waterId,
  clientId: waterClientId,
  mealType: 'lunch',
  consumedAt: DateTime(2026, 11, 17, 10),
  createdAt: DateTime.utc(2026, 11, 17),
  source: 'manual',
  items: [
    MealLogItem(
      id: waterId,
      mealLogId: waterId,
      displayName: name,
      isEstimated: false,
      caloriesKcal: calories,
      proteinGrams: protein,
      carbsGrams: 20,
      fatGrams: 5,
    ),
  ],
);

class _Meals extends MealLogApi {
  _Meals(super.session);
  List<MealLog> rows = [];
  Future<List<MealLog>>? result;
  MealLogApiException? failure;
  final ranges = <({DateTime from, DateTime to})>[];
  @override
  Future<List<MealLog>> forRange({
    required DateTime from,
    required DateTime to,
  }) async {
    ranges.add((from: from, to: to));
    if (failure != null) throw failure!;
    return result ?? rows;
  }
}

class _Plans extends NutritionPlanApi {
  _Plans(super.session);
  NutritionPlanResponse? value;
  Future<NutritionPlanResponse?>? result;
  NutritionPlanApiException? failure;
  int reads = 0;
  @override
  Future<NutritionPlanResponse?> active() async {
    reads++;
    if (failure != null) throw failure!;
    return result ?? value;
  }
}

void main() {
  late WaterTestSession session;
  late _Meals meals;
  late _Plans plans;
  late WaterTestApi water;
  late DateTime now;
  setUp(() {
    session = WaterTestSession();
    meals = _Meals(session);
    plans = _Plans(session);
    water = WaterTestApi(session);
    now = DateTime(2026, 11, 17, 12);
  });
  tearDown(() => session.dispose());
  Future<void> pump(
    WidgetTester tester, {
    Widget? page,
    bool settle = true,
    bool active = true,
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body:
                page ??
                HomePage(
                  onViewNutrition: () {},
                  mealApi: meals,
                  planApi: plans,
                  waterApi: water,
                  now: () => now,
                  active: active,
                ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final action = find.text(label);
    await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  test('empty totals are zero, unknown nutrients remain unknown', () {
    expect(DashboardMeals([]).calories.label('kcal'), '0 kcal');
    expect(NutrientTotal.from([null]).label('g'), 'Belirtilmemiş');
    expect(NutrientTotal.from([0, null]).label('g'), '0 g · Bilinen toplam');
    expect(NutrientTotal.from([10, 2.5]).label('g'), '12,5 g');
  });
  testWidgets(
    'new user sees genuine zero consumption and no invented records or goals',
    (tester) async {
      await pump(tester);
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('Protein: 0 g'), findsOneWidget);
      expect(find.text('Karbonhidrat: 0 g'), findsOneWidget);
      expect(find.text('Yağ: 0 g'), findsOneWidget);
      expect(find.text('0 mL'), findsOneWidget);
      expect(find.text('Henüz hedef belirlenmedi'), findsWidgets);
      expect(
        find.text('Henüz aktif bir beslenme programınız bulunmuyor.'),
        findsOneWidget,
      );
      expect(
        find.text('Henüz öğün kaydı yok. İlk öğününüzü ekleyebilirsiniz.'),
        findsOneWidget,
      );
      for (final fake in [
        '1680',
        '2200',
        '1250 mL',
        '2500 mL',
        'Örnek Diyetisyen',
        'Yoğurt, meyve ve ceviz',
      ]) {
        expect(find.textContaining(fake), findsNothing);
      }
      expect(meals.ranges.single.from, DateTime(2026, 11, 17));
      expect(meals.ranges.single.to, DateTime(2026, 11, 18));
    },
  );
  testWidgets(
    'real recorded values are summed; missing values are never counted as zero',
    (tester) async {
      meals.rows = [
        meal(),
        meal(calories: null, protein: null, name: 'Besin değeri eksik'),
      ];
      water.total = 750;
      await pump(tester);
      expect(find.text('125 kcal · Bilinen toplam'), findsOneWidget);
      expect(find.text('Protein: 10 g · Bilinen toplam'), findsOneWidget);
      expect(find.text('Karbonhidrat: 40 g'), findsOneWidget);
      expect(find.text('Yağ: 10 g'), findsOneWidget);
      expect(find.text('750 mL'), findsOneWidget);
      expect(find.text('Besin değeri eksik'), findsOneWidget);
      expect(
        find.textContaining('tam tüketim toplamı bilinmiyor'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'loading and failed reads never appear as empty data; retries restore real zeros',
    (tester) async {
      final mealResponse = Completer<List<MealLog>>();
      final planResponse = Completer<NutritionPlanResponse?>();
      final waterResponse = Completer<num>();
      meals.result = mealResponse.future;
      plans.result = planResponse.future;
      water.pendingTotal = waterResponse.future;
      await pump(tester, settle: false);
      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('0 mL'), findsNothing);
      expect(find.text('Henüz hedef belirlenmedi'), findsNothing);
      expect(find.textContaining('Henüz öğün kaydı yok'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      mealResponse.completeError(
        const MealLogApiException('Sentetik öğün bağlantı hatası'),
      );
      planResponse.completeError(
        const NutritionPlanApiException('Sentetik program bağlantı hatası'),
      );
      waterResponse.completeError(
        const WaterLogApiException('Sentetik su bağlantı hatası'),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('0 mL'), findsNothing);
      expect(find.text('Henüz hedef belirlenmedi'), findsNothing);
      expect(find.text('Hedef bilgisi alınamadı.'), findsOneWidget);
      meals.result = null;
      plans.result = null;
      water.pendingTotal = null;
      await tap(tester, 'Öğünleri yenile');
      await tap(tester, 'Programı yenile');
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('Henüz hedef belirlenmedi'), findsWidgets);
    },
  );
  testWidgets(
    'assigned program uses API title and targets without an invented dietitian',
    (tester) async {
      plans.value = NutritionPlanResponse(
        id: waterId,
        clientId: session.owner,
        dietitianId: waterClientId,
        title: 'Gerçek API programı',
        startDate: '2026-11-17',
        endDate: null,
        dailyCaloriesTargetKcal: 1800,
        dailyWaterTargetMl: 2100,
        createdAt: now,
        versionId: waterId,
        versionNumber: 2,
        items: [],
      );
      var opened = false;
      await pump(
        tester,
        page: HomePage(
          onViewNutrition: () => opened = true,
          mealApi: meals,
          planApi: plans,
          waterApi: water,
          now: () => now,
        ),
      );
      expect(find.text('Program hedefi: 1800 kcal'), findsOneWidget);
      expect(find.text('Gerçek API programı'), findsOneWidget);
      expect(find.text('Programdaki su hedefi: 2100 mL'), findsOneWidget);
      expect(
        find.text('Diyetisyeniniz tarafından atanmış program · Salt okunur'),
        findsOneWidget,
      );
      expect(find.text('Örnek Diyetisyen'), findsNothing);
      await tap(tester, 'Beslenmeye göz at');
      expect(opened, isTrue);
    },
  );
  testWidgets(
    'owner change ignores late data, logout and login never retain previous consumption',
    (tester) async {
      final previousMeals = Completer<List<MealLog>>();
      final previousPlan = Completer<NutritionPlanResponse?>();
      final previousWater = Completer<num>();
      meals.result = previousMeals.future;
      plans.result = previousPlan.future;
      water.pendingTotal = previousWater.future;
      await pump(tester, settle: false);
      meals.result = null;
      plans.result = null;
      water.pendingTotal = null;
      session.changeOwner();
      await tester.pumpAndSettle();
      previousMeals.complete([
        meal(calories: 999, name: 'Önceki kullanıcının öğünü'),
      ]);
      previousPlan.complete(null);
      previousWater.complete(999);
      await tester.pumpAndSettle();
      expect(find.textContaining('999'), findsNothing);
      expect(find.textContaining('Önceki kullanıcının'), findsNothing);
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('0 mL'), findsOneWidget);
      meals.rows = [meal(calories: 321)];
      water.total = 321;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('321 kcal'), findsOneWidget);
      session.end();
      await tester.pumpAndSettle();
      expect(find.textContaining('321'), findsNothing);
      expect(find.text('0 kcal'), findsNothing);
      meals.rows = [];
      water.total = 0;
      session.authenticated = true;
      session.changeOwner();
      await tester.pumpAndSettle();
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('0 mL'), findsOneWidget);
    },
  );
  testWidgets(
    'day rollover discards previous day totals and inactive tab clears snapshots',
    (tester) async {
      now = DateTime(2026, 11, 17, 23, 59, 59);
      meals.rows = [meal()];
      water.total = 250;
      await pump(tester);
      expect(find.text('125 kcal'), findsOneWidget);
      now = DateTime(2026, 11, 18);
      meals.rows = [];
      water.total = 0;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(meals.ranges.last.from, DateTime(2026, 11, 18));
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('0 mL'), findsOneWidget);
      await pump(tester, active: false);
      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('0 mL'), findsNothing);
      await pump(tester);
      expect(find.text('0 kcal'), findsOneWidget);
    },
  );
  testWidgets(
    'profile uses authenticated identity and clears it at logout; progress stays empty',
    (tester) async {
      await pump(tester, page: const ProfilePage());
      expect(find.text('synthetic@example.test'), findsOneWidget);
      expect(find.text('Diyetisyen Bul'), findsOneWidget);
      expect(find.text('Diyetisyen Profili ve Başvuru'), findsNothing);
      session.end();
      await tester.pumpAndSettle();
      expect(find.text('synthetic@example.test'), findsNothing);
      await pump(tester, page: const ProgressPage());
      expect(
        find.text(
          'Ölçüm geçmişiniz ve gelişim grafikleriniz burada yer alacak.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ProgressIndicator), findsNothing);
    },
  );
}
