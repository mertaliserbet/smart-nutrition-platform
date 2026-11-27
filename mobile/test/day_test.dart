import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/home/day_plan_cards.dart';
import 'package:smart_nutrition_mobile/features/home/day_widgets.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_summary_card.dart';
import 'day_test_support.dart';
import 'water_test_support.dart';

void main() {
  testWidgets('greeting omits surname while retaining multiple given names', (
    tester,
  ) async {
    for (final (fullName, givenName) in [
      ('Mert Ali Örnek', 'Mert Ali'),
      ('  İpek   Şen  ', 'İpek'),
      ('Deniz', 'Deniz'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayHeader(day: DateTime(2026, 11, 25), name: fullName),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('$givenName, bugün kendine iyi gelecek bir adım seç.'),
        findsOneWidget,
      );
      expect(find.text('Günün, senin\nritminde.'), findsOneWidget);
      expect(find.textContaining('Günaydın'), findsNothing);
      expect(find.textContaining('iyi akşamlar'), findsNothing);
    }
  });
  test('today projection preserves dates, meal order and alternatives', () {
    NutritionPlanItem item(
      String id,
      String type,
      String text,
      int order, {
      int? day,
      String? alternative,
    }) => NutritionPlanItem(
      id: id,
      nutritionPlanId: 'plan',
      dayOfWeek: day,
      mealType: type,
      description: text,
      recommendedQuantity: null,
      sortOrder: order,
      alternativeGroupId: alternative,
    );
    final plan = NutritionPlanResponse(
      id: 'plan',
      clientId: 'client',
      dietitianId: 'dietitian',
      title: 'Sentetik',
      startDate: '2026-11-23',
      endDate: '2026-11-29',
      dailyCaloriesTargetKcal: null,
      dailyWaterTargetMl: null,
      createdAt: DateTime.utc(2026, 11, 23),
      versionId: 'version',
      versionNumber: 1,
      items: [
        item('1', 'lunch', 'Mercimek çorbası', 1, alternative: 'soups'),
        item('2', 'lunch', 'Sebze çorbası', 2, alternative: 'soups'),
        item('3', 'breakfast', 'Yulaf', 0),
        item('4', 'dinner', 'Perşembe öğünü', 3, day: 4),
      ],
    );
    final groups = dayPlanMeals(plan, DateTime(2026, 11, 23));
    expect(groups.map((group) => group.first.mealType), ['breakfast', 'lunch']);
    expect(
      dayMealDescription(groups.last),
      'Mercimek çorbası veya Sebze çorbası',
    );
    expect(dayPlanMeals(plan, DateTime(2026, 11, 22)), isEmpty);
    expect(dayPlanMeals(plan, DateTime(2026, 11, 30)), isEmpty);
  });
  Future<void> pump(
    WidgetTester tester,
    AuthSession session, {
    Widget child = const MainShell(),
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
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

  testWidgets(
    'approved day layout uses the account and real totals without invented appointments',
    (tester) async {
      final session = DayTestSession();
      addTearDown(session.dispose);
      await pump(tester, session);
      expect(
        find.text('Mert Ali, bugün kendine iyi gelecek bir adım seç.'),
        findsOneWidget,
      );
      expect(find.text('980 / 1.700 kcal'), findsOneWidget);
      expect(find.text('62 / 110 g'), findsOneWidget);
      expect(find.text('750 / 2.000 ml'), findsOneWidget);
      expect(find.byType(DayPlannedMeal), findsOneWidget);
      expect(find.text('Kayıt var'), findsOneWidget);
      expect(find.text('Saat belirtilmedi'), findsOneWidget);
      expect(find.text('Görüşme bilgisi bulunmuyor.'), findsOneWidget);
      expect(find.textContaining('18:30'), findsNothing);
      expect(find.textContaining('Uğur'), findsNothing);
      expect(find.text('Tamamlandı'), findsNothing);
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        nav.destinations.cast<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['Günüm', 'Ölçüm', 'Planım', 'Sohbet', 'Hesabım'],
      );
      await tap(tester, find.byKey(const ValueKey('day-water-add')));
      expect(session.waterCreates, 1);
      expect(find.text('1.000 / 2.000 ml'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('personal or missing plans do not advertise an assigned meal', (
    tester,
  ) async {
    final session = DayTestSession()..assigned = false;
    addTearDown(session.dispose);
    await pump(tester, session);
    expect(find.byType(DayPlannedMeal), findsNothing);
    expect(find.text('Kişisel programın · Salt okunur'), findsOneWidget);
    session.hasPlan = false;
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Günüm'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DayPlannedMeal), findsNothing);
    expect(
      find.text('Henüz aktif bir beslenme programın bulunmuyor.'),
      findsOneWidget,
    );
  });

  testWidgets('manual meal and avatar actions reach existing flows', (
    tester,
  ) async {
    final session = DayTestSession();
    addTearDown(session.dispose);
    await pump(tester, session);
    await tap(tester, find.text('Manuel'));
    expect(find.byType(ManualMealLogPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.text('MA'));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
  });

  testWidgets(
    'quick water prevents duplicate and uncertain writes until explicit refresh',
    (tester) async {
      final session = WaterTestSession();
      addTearDown(session.dispose);
      final api = WaterTestApi(session)..total = 750;
      final response = Completer<WaterLog>();
      api.pendingWrite = response.future;
      await pump(
        tester,
        session,
        child: WaterSummaryCard(api: api, limely: true),
      );
      final add = find.byKey(const ValueKey('day-water-add'));
      await tester.tap(add);
      await tester.pump();
      expect(api.creates, 1);
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      expect(find.text('750 ml'), findsOneWidget);
      response.completeError(
        const WaterLogApiException('Sonuç belirsiz.', uncertain: true),
      );
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      expect(find.text('750 ml'), findsNothing);
      expect(find.textContaining('Yeniden işlem yapmadan'), findsOneWidget);
      api.pendingWrite = null;
      api.total = 1000;
      await tap(tester, find.text('Su bilgilerini yenile'));
      expect(find.text('1.000 ml'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(add).onPressed, isNotNull);
      expect(api.creates, 1);
    },
  );

  testWidgets('late water write cannot restore totals after logout', (
    tester,
  ) async {
    final session = WaterTestSession();
    addTearDown(session.dispose);
    final response = Completer<WaterLog>();
    final api = WaterTestApi(session)
      ..total = 750
      ..pendingWrite = response.future;
    await pump(
      tester,
      session,
      child: WaterSummaryCard(api: api, limely: true),
    );
    await tester.tap(find.byKey(const ValueKey('day-water-add')));
    await tester.pump();
    session.end();
    await tester.pump();
    response.complete(waterSample());
    await tester.pumpAndSettle();
    expect(api.creates, 1);
    expect(api.days, hasLength(1));
    expect(find.byKey(const ValueKey('day-water-total')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('day-water-add')))
          .onPressed,
      isNull,
    );
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('day cards fit $width px at text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final session = DayTestSession();
        addTearDown(session.dispose);
        await pump(tester, session);
        for (final key in [
          find.text('Günlük enerji'),
          find.text('Su molası'),
          find.text('Öğünümü kaydet'),
          find.text('Bugünkü planım'),
        ]) {
          await tester.ensureVisible(key);
          await tester.pumpAndSettle();
          expect(key.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
