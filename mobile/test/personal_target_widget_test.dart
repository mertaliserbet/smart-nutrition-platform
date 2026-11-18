import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/personal_nutrition_target_api.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/personal_nutrition_target_page.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/target_progress.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'personal_target_test_support.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late TargetTestApi api;
  setUp(() {
    session = WaterTestSession();
    api = TargetTestApi(session);
  });
  tearDown(() => session.dispose());
  Finder field(String key) => find.byKey(ValueKey(key));
  Future<void> open(
    WidgetTester tester, {
    bool settle = true,
    ThemeData? theme,
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => PersonalNutritionTargetPage(api: api),
                    ),
                  );
                  if (context.mounted && saved == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hedefler kaydedildi.')),
                    );
                  }
                },
                child: const Text('Hedefleri aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hedefleri aç'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final button = find.text(text);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('clearing all existing targets submits five explicit nulls', (
    tester,
  ) async {
    api.value = targetResponse({
      for (final f in personalTargetFields) f.key: 100,
    });
    await open(tester);
    for (final f in personalTargetFields) {
      await tester.enterText(field(f.key), '');
    }
    await tap(tester, 'Hedefleri kaydet');
    expect(api.writes.single, {
      for (final f in personalTargetFields) f.key: null,
    });
  });
  for (final dark in [false, true]) {
    testWidgets(
      'target form fits a narrow screen with large text in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await open(tester, theme: dark ? AppTheme.dark : AppTheme.light);
        for (final f in personalTargetFields) {
          await tester.ensureVisible(field(f.key));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.enterText(field('dailyWaterTargetMl'), '2000,5');
        await tap(tester, 'Hedefleri kaydet');
        expect(api.writes.single, {'dailyWaterTargetMl': 2000.5});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'new user has five empty fields with no automatic values or writes',
    (tester) async {
      await open(tester);
      expect(find.byType(TextFormField), findsNWidgets(5));
      for (final f in personalTargetFields) {
        expect(tester.widget<TextFormField>(field(f.key)).controller!.text, '');
      }
      await tap(tester, 'Hedefleri kaydet');
      expect(api.writes, isEmpty);
      expect(find.text('Değişiklik bulunmuyor.'), findsOneWidget);
    },
  );
  testWidgets(
    'partial edit sends only changed numeric fields and explicit clear nulls',
    (tester) async {
      api.value = targetResponse({
        for (final f in personalTargetFields) f.key: 100,
      });
      await open(tester);
      await tester.enterText(field('dailyProteinTargetGrams'), '125,5');
      await tester.enterText(field('dailyWaterTargetMl'), '');
      await tap(tester, 'Hedefleri kaydet');
      expect(api.writes.single, {
        'dailyProteinTargetGrams': 125.5,
        'dailyWaterTargetMl': null,
      });
      expect(find.byType(PersonalNutritionTargetPage), findsNothing);
      expect(find.text('Hedefler kaydedildi.'), findsOneWidget);
    },
  );
  testWidgets('zero, negative, overflow, NaN and non-numbers never submit', (
    tester,
  ) async {
    await open(tester);
    for (final value in ['0', '-1', '10001', 'NaN', 'Infinity', 'abc']) {
      await tester.enterText(field('dailyCaloriesTargetKcal'), value);
      await tap(tester, 'Hedefleri kaydet');
      expect(
        find.text('0’dan büyük, en fazla 10000 kcal girin.'),
        findsOneWidget,
      );
      expect(api.writes, isEmpty);
    }
  });
  testWidgets(
    'GET loading and error do not display empty targets; retry restores real state',
    (tester) async {
      final read = Completer<PersonalNutritionTargetResponse>();
      api.pendingRead = read.future;
      await open(tester, settle: false);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      read.completeError(
        const PersonalNutritionTargetApiException('Sentetik bağlantı hatası'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      api.pendingRead = null;
      await tap(tester, 'Hedefleri yeniden yükle');
      expect(find.byType(TextFormField), findsNWidgets(5));
    },
  );
  testWidgets(
    'uncertain PATCH blocks repeat until a fresh GET and does not resend',
    (tester) async {
      await open(tester);
      await tester.enterText(field('dailyWaterTargetMl'), '2000');
      api.writeFailure = const PersonalNutritionTargetApiException(
        'Sonuç bilinmiyor',
        uncertain: true,
      );
      await tap(tester, 'Hedefleri kaydet');
      expect(api.writes, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Hedefleri kaydet'),
            )
            .onPressed,
        isNull,
      );
      api.value = const PersonalNutritionTargetResponse(
        dailyWaterTargetMl: 2000,
      );
      api.writeFailure = null;
      await tap(tester, 'Hedefleri yeniden yükle');
      expect(api.writes, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(field('dailyWaterTargetMl'))
            .controller!
            .text,
        '2000',
      );
    },
  );
  testWidgets('late GET after account switch cannot expose previous targets', (
    tester,
  ) async {
    final read = Completer<PersonalNutritionTargetResponse>();
    api.pendingRead = read.future;
    await open(tester, settle: false);
    session.changeOwner();
    await tester.pump();
    read.complete(
      const PersonalNutritionTargetResponse(dailyCaloriesTargetKcal: 2345),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('2345'), findsNothing);
    expect(find.textContaining('Hesap değiştiyse'), findsOneWidget);
  });
  testWidgets(
    'logout erases form values and late PATCH does not navigate or replay',
    (tester) async {
      api.value = const PersonalNutritionTargetResponse(
        dailyCaloriesTargetKcal: 2222,
      );
      await open(tester);
      await tester.enterText(field('dailyCaloriesTargetKcal'), '2400');
      final write = Completer<PersonalNutritionTargetResponse>();
      api.pendingWrite = write.future;
      final save = find.text('Hedefleri kaydet');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      session.end();
      await tester.pump();
      write.complete(
        const PersonalNutritionTargetResponse(dailyCaloriesTargetKcal: 2400),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Hedefler kaydedildi.'), findsNothing);
      expect(api.writes, hasLength(1));
    },
  );
  testWidgets('successful background save stays locked until explicit close', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('dailyWaterTargetMl'), '2000');
    final write = Completer<PersonalNutritionTargetResponse>();
    api.pendingWrite = write.future;
    final save = find.text('Hedefleri kaydet');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    write.complete(
      const PersonalNutritionTargetResponse(dailyWaterTargetMl: 2000),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    await tap(tester, 'Hedefler kaydedildi · Ekranı kapat');
    expect(find.byType(PersonalNutritionTargetPage), findsNothing);
  });
  test(
    'source priority is per field, personal programs stay separate, failed priority never falls back',
    () {
      final personal = AsyncSnapshot.withData(
        ConnectionState.done,
        const PersonalNutritionTargetResponse(
          dailyCaloriesTargetKcal: 1800,
          dailyWaterTargetMl: 2100,
          dailyProteinTargetGrams: 80,
        ),
      );
      NutritionPlanResponse program({
        String? dietitian,
        num? calories,
        num? water,
      }) => NutritionPlanResponse(
        id: waterId,
        clientId: waterClientId,
        dietitianId: dietitian,
        title: 'Sentetik program',
        startDate: '2026-11-18',
        endDate: null,
        dailyCaloriesTargetKcal: calories,
        dailyWaterTargetMl: water,
        createdAt: DateTime.utc(2026, 11, 18),
        versionId: waterId,
        versionNumber: 1,
        items: [],
      );
      final assigned = AsyncSnapshot<NutritionPlanResponse?>.withData(
        ConnectionState.done,
        program(dietitian: waterId, calories: 2400),
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyCaloriesTargetKcal',
          personal,
          plan: assigned,
        ).value,
        2400,
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyCaloriesTargetKcal',
          personal,
          plan: assigned,
        ).source,
        'Diyetisyen programı',
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyWaterTargetMl',
          personal,
          plan: assigned,
        ).value,
        2100,
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyProteinTargetGrams',
          personal,
        ).value,
        80,
      );
      final own = AsyncSnapshot<NutritionPlanResponse?>.withData(
        ConnectionState.done,
        program(calories: 9000, water: 9000),
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyCaloriesTargetKcal',
          personal,
          plan: own,
        ).value,
        1800,
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyCaloriesTargetKcal',
          personal,
          plan: const AsyncSnapshot.waiting(),
        ).loading,
        isTrue,
      );
      expect(
        EffectiveNutritionTarget.resolve(
          'dailyCaloriesTargetKcal',
          personal,
          plan: AsyncSnapshot.withError(ConnectionState.done, 'hata'),
        ).failed,
        isTrue,
      );
    },
  );
  testWidgets(
    'progress handles over-target values and incomplete consumption honestly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NutritionTargetProgress(
              target: EffectiveNutritionTarget(
                value: 2000,
                source: 'Kişisel hedef',
              ),
              unit: 'mL',
              consumed: 3000,
            ),
          ),
        ),
      );
      expect(find.textContaining('%150'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NutritionTargetProgress(
              target: EffectiveNutritionTarget(
                value: 100,
                source: 'Kişisel hedef',
              ),
              unit: 'g',
              consumed: 10,
              complete: false,
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('ilerleme hesaplanamıyor'), findsOneWidget);
    },
  );
}
