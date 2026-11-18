import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_comparison_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_comparison_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'meal_comparison_test_support.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late _Plans plans;
  late _Comparison api;
  setUp(() {
    session = WaterTestSession();
    plans = _Plans(session);
    api = _Comparison(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(
    WidgetTester tester, {
    bool settle = true,
    bool dark = false,
    Size size = const Size(400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: MealComparisonPage(
            planApi: plans,
            api: api,
            initialDate: DateTime(2026, 11, 18),
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

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'planned alternatives and actual summaries remain distinct in small ${dark ? 'dark' : 'light'} view',
      (tester) async {
        await open(tester, dark: dark, size: const Size(320, 700));
        expect(find.text('Aktif atanmış program · Sürüm 1'), findsOneWidget);
        await tap(tester, 'Karşılaştırmayı yenile');
        expect(api.versions, [1, 1]);
        await tester.scrollUntilVisible(
          find.textContaining('Kalori: 125,5 kcal bilinen toplam').first,
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Protein: Belirtilmemiş').first,
          findsOneWidget,
        );
        expect(
          find.textContaining('Kalori farkı hesaplanamıyor').first,
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Yulaf'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Alternatif 1'), findsNWidgets(2));
        expect(find.text('Yoğurt'), findsOneWidget);
        expect(find.text('1 kâse'), findsNothing);
        expect(find.text('Miktar: 1 kâse'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'loading never displays zero or previous consumption; refresh re-resolves active version',
    (tester) async {
      final pending = Completer<NutritionPlanMealComparisonResponse>();
      api.pending = pending.future;
      await open(tester, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Kalori: 0'), findsNothing);
      pending.complete(comparisonResponse(comparisonPlan(), api.days.single));
      await tester.pumpAndSettle();
      api.pending = null;
      plans.value = comparisonPlan(version: 2);
      api.complete = true;
      await tap(tester, 'Karşılaştırmayı yenile');
      expect(api.versions, [1, 2]);
      expect(find.text('Aktif atanmış program · Sürüm 1'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Kaydedilen kalori − program hedefi:'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('-874,5 kcal'), findsOneWidget);
    },
  );
  testWidgets('empty consumption is not a day with zero nutrients', (
    tester,
  ) async {
    api.empty = true;
    await open(tester);
    expect(find.textContaining('Kalori: 0'), findsNothing);
    expect(find.textContaining('Protein: 0'), findsNothing);
    expect(find.text('Öğün kaydı yok'), findsWidgets);
  });
  for (final kind in ['none', 'personal', 'outside']) {
    testWidgets('$kind program state does not request a comparison', (
      tester,
    ) async {
      plans.value = kind == 'none'
          ? null
          : comparisonPlan(
              personal: kind == 'personal',
              endDate: kind == 'outside' ? '2026-11-17' : null,
            );
      await open(tester);
      expect(api.versions, isEmpty);
      expect(
        find.textContaining(
          kind == 'outside' ? 'tarih aralığı dışında' : 'Henüz aktif atanmış',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Kalori: 0'), findsNothing);
    });
  }
  for (final status in [403, 404, 422, 500]) {
    testWidgets('error $status clears prior data and allows explicit retry', (
      tester,
    ) async {
      await open(tester);
      api.failure = MealComparisonApiException(
        'Sentetik hata $status',
        statusCode: status,
      );
      await tap(tester, 'Karşılaştırmayı yenile');
      expect(find.text('Sentetik atanmış program'), findsNothing);
      expect(find.text('Sentetik hata $status'), findsOneWidget);
      api.failure = null;
      await tap(tester, 'Yeniden dene');
      expect(find.text('Sentetik atanmış program'), findsOneWidget);
      expect(api.versions, hasLength(3));
    });
  }
  testWidgets(
    'new date ignores late previous-day response and sends local midnight range',
    (tester) async {
      final pending = Completer<NutritionPlanMealComparisonResponse>();
      api.pending = pending.future;
      await open(tester, settle: false);
      await tester.tap(find.text('Gün seç: 18.11.2026'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('17').last);
      api.pending = null;
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(api.days.last.from.day, 17);
      expect(api.days.last.from.hour, 0);
      expect(api.days.last.to.day, 18);
      pending.complete(
        comparisonResponse(comparisonPlan(version: 9), api.days.first),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aktif atanmış program · Sürüm 9'), findsNothing);
      expect(find.text('Gün seç: 17.11.2026'), findsOneWidget);
    },
  );
  testWidgets(
    'account change and logout clear comparison and discard late private result',
    (tester) async {
      final pending = Completer<NutritionPlanMealComparisonResponse>();
      api.pending = pending.future;
      await open(tester, settle: false);
      plans.value = null;
      session.changeOwner();
      await tester.pumpAndSettle();
      pending.complete(comparisonResponse(comparisonPlan(), api.days.first));
      await tester.pumpAndSettle();
      expect(find.text('Sentetik atanmış program'), findsNothing);
      expect(find.textContaining('Henüz aktif atanmış'), findsOneWidget);
      session.end();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Program ve tüketim'), findsNothing);
    },
  );
  testWidgets(
    'assigned program view exposes comparison without affecting meal actions',
    (tester) async {
      await tester.pumpWidget(
        AuthSessionScope(
          session: session,
          child: MaterialApp(
            home: Scaffold(body: NutritionPage(api: plans)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Program ve tüketimi karşılaştır'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Program ve tüketimi karşılaştır'), findsOneWidget);
    },
  );
}

class _Plans extends NutritionPlanApi {
  _Plans(super.session);
  NutritionPlanResponse? value = comparisonPlan();
  @override
  Future<NutritionPlanResponse?> active() async => value;
}

class _Comparison extends MealComparisonApi {
  _Comparison(super.session);
  final versions = <int>[];
  final days = <WaterDayRange>[];
  Future<NutritionPlanMealComparisonResponse>? pending;
  MealComparisonApiException? failure;
  bool empty = false, complete = false;
  @override
  Future<NutritionPlanMealComparisonResponse> get(
    NutritionPlanResponse plan,
    WaterDayRange day,
  ) async {
    versions.add(plan.versionNumber);
    days.add(day);
    if (failure != null) {
      throw failure!;
    }
    return pending ??
        comparisonResponse(plan, day, empty: empty, complete: complete);
  }
}
