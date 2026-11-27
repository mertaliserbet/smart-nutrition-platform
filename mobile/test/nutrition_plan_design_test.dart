import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/plan_meal_card.dart';
import 'water_test_support.dart';
import 'meal_comparison_test_support.dart';

void main() {
  late WaterTestSession session;
  late _Plans plans;
  late _Meals meals;
  late _Experts experts;
  setUp(() {
    session = WaterTestSession();
    plans = _Plans(session);
    meals = _Meals(session);
    experts = _Experts(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: NutritionPage(
              api: plans,
              mealApi: meals,
              dietitianApi: experts,
              initialDate: DateTime(2026, 11, 27),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final (width, scale) in [(320.0, 2.0), (390.0, 1.0), (430.0, 1.3)]) {
    testWidgets(
      'approved plan layout and info sheet fit $width at scale $scale',
      (tester) async {
        await open(tester, width: width, scale: scale);
        expect(find.text('Planın hazır,\nadım adım.'), findsOneWidget);
        expect(find.text('Sentetik Uzman hazırladı'), findsOneWidget);
        expect(find.text('Kayıt var'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tap(tester, find.byTooltip('Planın hakkında'));
        expect(find.text('Planın hakkında'), findsOneWidget);
        expect(find.text('Aktif diyetisyen planı'), findsOneWidget);
        await tap(tester, find.text('Planıma dön'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'switching day clears record badge and ignores previous-day response',
    (tester) async {
      final late = Completer<List<MealLog>>();
      meals.pending = late.future;
      await open(tester);
      expect(find.text('Kayıt var'), findsNothing);
      meals.pending = null;
      meals.rows = [];
      await tap(tester, find.bySemanticsLabel('26 Kasım 2026 · Perşembe'));
      late.complete([_record]);
      await tester.pumpAndSettle();
      expect(find.text('Kayıt var'), findsNothing);
      expect(find.text('Günün öğünleri'), findsOneWidget);
      expect(meals.days.last, DateTime(2026, 11, 26));
    },
  );
  testWidgets(
    'record failure is separate from plan and retry restores true badge',
    (tester) async {
      meals.fail = true;
      await open(tester);
      expect(find.text('Günlük denge planı'), findsOneWidget);
      expect(find.text('Kayıt var'), findsNothing);
      meals.fail = false;
      await tap(tester, find.text('Tekrar yükle'));
      expect(find.text('Kayıt var'), findsOneWidget);
    },
  );
  testWidgets(
    'outside plan period has no recommendations or comparison action',
    (tester) async {
      await open(tester);
      await tap(tester, find.byTooltip('Sonraki hafta'));
      expect(find.text('Bu gün planının dışında.'), findsOneWidget);
      expect(find.byType(PlanMealCard), findsNothing);
      expect(find.text('Plan ve tüketimimi karşılaştır'), findsNothing);
      await tap(tester, find.byTooltip('Önceki hafta'));
      expect(find.byType(PlanMealCard), findsNWidgets(4));
    },
  );
  testWidgets('expert directory failure does not credit a different expert', (
    tester,
  ) async {
    experts.match = false;
    await open(tester);
    expect(find.text('Sentetik Uzman hazırladı'), findsNothing);
    expect(find.text('Diyetisyeninin hazırladığı plan'), findsOneWidget);
    expect(find.text('Başka Uzman hazırladı'), findsNothing);
  });
  testWidgets(
    'open plan info removes private snapshot after background and account change',
    (tester) async {
      await open(tester);
      await tap(tester, find.byTooltip('Planın hakkında'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        find.text('Günlük denge planı\nSana eşlik eden öğün önerilerin.'),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Bilgileri görüntülemek için planını yeniden aç.'),
        findsOneWidget,
      );
      session.changeOwner();
      await tester.pumpAndSettle();
      expect(find.text('Aktif diyetisyen planı'), findsNothing);
    },
  );
}

final _record = MealLog(
  id: 'synthetic-meal',
  clientId: comparisonClientId,
  mealType: 'breakfast',
  consumedAt: DateTime(2026, 11, 27, 8),
  createdAt: DateTime(2026, 11, 27, 8),
  source: 'manual',
  items: const [],
);
NutritionPlanResponse designPlan() => NutritionPlanResponse(
  id: comparisonPlanId,
  clientId: comparisonClientId,
  dietitianId: comparisonExpertId,
  title: 'Günlük denge planı',
  startDate: '2026-11-23',
  endDate: '2026-11-29',
  dailyCaloriesTargetKcal: 1700,
  dailyWaterTargetMl: 2000,
  createdAt: DateTime.utc(2026, 11, 23),
  versionId: '55555555-5555-4555-8555-555555555555',
  versionNumber: 1,
  items: [
    for (final (i, type) in ['breakfast', 'lunch', 'snack', 'dinner'].indexed)
      NutritionPlanItem(
        id: 'item-$i',
        nutritionPlanId: comparisonPlanId,
        dayOfWeek: null,
        mealType: type,
        description: [
          'Yoğurt ve yulaf',
          'Izgara tavuk ve bulgur',
          'Meyve ve badem',
          'Zeytinyağlı sebze',
        ][i],
        recommendedQuantity: '1 porsiyon',
        sortOrder: i,
        alternativeGroupId: null,
      ),
  ],
);

class _Plans extends NutritionPlanApi {
  _Plans(super.session);
  @override
  Future<NutritionPlanResponse?> active() async => designPlan();
}

class _Meals extends MealLogApi {
  _Meals(super.session);
  bool fail = false;
  List<MealLog> rows = [_record];
  Future<List<MealLog>>? pending;
  final days = <DateTime>[];
  @override
  Future<List<MealLog>> forRange({
    required DateTime from,
    required DateTime to,
  }) async {
    days.add(from);
    if (fail) throw StateError('Synthetic read failure');
    return pending ?? rows;
  }
}

class _Experts extends DietitianApi {
  _Experts(super.session);
  bool match = true;
  @override
  Future<DietitianPage<DietitianListItem>> search({
    required int page,
    String query = '',
  }) async => (
    items: [
      DietitianListItem(
        match ? comparisonExpertId : 'different-expert',
        match ? 'Sentetik Uzman' : 'Başka Uzman',
      ),
    ],
    totalCount: 1,
  );
}
