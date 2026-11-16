import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_history_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_detail_page.dart';
import 'meal_log_test_support.dart';

void main() {
  late MealTestSession session;
  late MealTestApi api;
  setUp(() {
    session = MealTestSession();
    api = MealTestApi(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final saved = await Navigator.of(
                    context,
                  ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
                  if (context.mounted && saved == true) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Kaydedildi')));
                  }
                },
                child: const Text('Başlat'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'validates type/name, gram positivity and nonnegative nutrient numbers',
    (tester) async {
      await open(tester, ManualMealLogPage(api: api));
      await tapVisible(tester, find.text('Kaydet'));
      expect(find.text('Bir öğün türü seçin.'), findsOneWidget);
      expect(find.text('Yemek adını girin.'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Öğle'));
      await tester.enterText(mealField('Yemek adı'), 'Sentetik öğün');
      for (final bad in ['0', '-1', 'NaN', 'Infinity', '1e3', '12,3,4']) {
        await tester.enterText(mealField('Miktar (gram)'), bad);
        await tapVisible(tester, find.text('Kaydet'));
        expect(find.textContaining('Sıfırdan büyük'), findsOneWidget);
      }
      await tester.enterText(mealField('Miktar (gram)'), '');
      await tester.enterText(mealField('Protein (g)'), '-1');
      await tapVisible(tester, find.text('Kaydet'));
      expect(
        find.text('Sıfır veya daha büyük bir sayı girin.'),
        findsOneWidget,
      );
      expect(api.creates, 0);
    },
  );
  testWidgets('creates once with comma numbers, nulls, UTC and no clientId', (
    tester,
  ) async {
    final pending = Completer<MealLog>();
    api.pendingCreate = pending.future;
    await open(tester, ManualMealLogPage(api: api));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Öğle'));
    await tester.enterText(mealField('Yemek adı'), 'Sentetik öğün');
    await tester.enterText(mealField('Miktar (gram)'), '125,5');
    await tester.enterText(mealField('Kalori (kcal)'), '0');
    await tester.enterText(mealField('Protein (g)'), '12,5');
    await tester.enterText(mealField('Not'), 'Sentetik not');
    await tester.ensureVisible(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(api.creates, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
          .onPressed,
      isNull,
    );
    final body = api.lastBody!;
    expect(body.containsKey('clientId'), isFalse);
    expect(body['source'], 'manual');
    expect(DateTime.parse(body['consumedAt'] as String).isUtc, isTrue);
    final item = (body['items'] as List).single as Map<String, Object?>;
    expect(item['quantityGrams'], 125.5);
    expect(item['caloriesKcal'], 0);
    expect(item['proteinGrams'], 12.5);
    expect(item['carbsGrams'], isNull);
    expect(body['note'], 'Sentetik not');
    pending.complete(sampleMeal());
    await tester.pumpAndSettle();
    expect(find.text('Kaydedildi'), findsOneWidget);
  });
  testWidgets(
    'edit preserves every existing item and omits source and unchanged items',
    (tester) async {
      await open(tester, ManualMealLogPage(api: api, initial: sampleMeal()));
      expect(find.text('Sentetik çorba'), findsOneWidget);
      await tester.enterText(mealField('Not'), 'Düzeltilen not');
      await tapVisible(tester, find.text('Kaydet'));
      expect(api.updates, 1);
      expect(api.lastBody!.containsKey('items'), isFalse);
      expect(api.lastBody!.containsKey('source'), isFalse);
      expect(api.lastBody!['note'], 'Düzeltilen not');
    },
  );
  testWidgets(
    'supports multiple items without dropping fields or unknown values',
    (tester) async {
      await open(tester, ManualMealLogPage(api: api));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Diğer'));
      await tester.enterText(mealField('Yemek adı'), 'İlk besin');
      await tapVisible(tester, find.text('Besin ekle'));
      await tester.enterText(mealField('Yemek adı').last, 'İkinci besin');
      await tapVisible(tester, find.text('Kaydet'));
      expect((api.lastBody!['items'] as List).length, 2);
      expect(api.lastBody!['mealType'], 'other');
      expect(
        ((api.lastBody!['items'] as List).first as Map)['quantityGrams'],
        isNull,
      );
    },
  );
  testWidgets(
    'ambiguous mutation does not replay and keeps duplicate submission disabled',
    (tester) async {
      api.failure = const MealLogApiException(
        'Bağlantı kesildi.',
        uncertain: true,
      );
      await open(tester, ManualMealLogPage(api: api, initial: sampleMeal()));
      await tapVisible(tester, find.text('Kaydet'));
      expect(api.updates, 1);
      expect(find.textContaining('İşlemin sonucu belirsiz'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull,
      );
      expect(find.text('Sentetik çorba'), findsOneWidget);
    },
  );
  testWidgets(
    'successful save finishing in background cannot be submitted twice',
    (tester) async {
      final pending = Completer<MealLog>();
      api.pendingCreate = pending.future;
      await open(tester, ManualMealLogPage(api: api));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Öğle'));
      await tester.enterText(mealField('Yemek adı'), 'Sentetik öğün');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Kaydet')),
        alignment: 0.5,
      );
      await tester.ensureVisible(find.text('Kaydet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      pending.complete(sampleMeal());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(find.textContaining('Öğün kaydedildi.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'changing account discards the earlier account history response',
    (tester) async {
      final pending = Completer<MealLogPage>();
      api.pendingList = pending.future;
      // Open without settling the pending loading animation.
      await tester.pumpWidget(
        AuthSessionScope(
          session: session,
          child: MaterialApp(home: MealLogHistoryPage(api: api)),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      api.pendingList = null;
      api.rows = [];
      session.changeOwner();
      await tester.pump();
      pending.complete((items: [sampleMeal()], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sentetik çorba'), findsNothing);
      expect(find.textContaining('Henüz öğün yok.'), findsOneWidget);
    },
  );
  testWidgets(
    'history shows real empty, error, retry and detail; delete refreshes list',
    (tester) async {
      await open(tester, MealLogHistoryPage(api: api));
      expect(find.textContaining('Sentetik çorba'), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.byType(MealLogDetailPage), findsOneWidget);
      expect(find.text('Kalori: 0 kcal'), findsOneWidget);
      expect(find.text('Miktar: Belirtilmemiş'), findsOneWidget);
      await tapVisible(tester, find.text('Öğünü sil'));
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(api.deletes, 0);
      await tapVisible(tester, find.text('Öğünü sil'));
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(api.deletes, 1);
      expect(find.textContaining('Henüz öğün yok.'), findsOneWidget);
      expect(api.pages.length, 2);
      api.failure = const MealLogApiException('Öğün servisi kapalı.');
      await tapVisible(tester, find.text('Geçmişi yenile'));
      expect(find.text('Öğün servisi kapalı.'), findsOneWidget);
      expect(find.textContaining('Henüz öğün yok.'), findsNothing);
      api.failure = null;
      await tapVisible(tester, find.text('Geçmişi yenile'));
      expect(find.textContaining('Henüz öğün yok.'), findsOneWidget);
    },
  );
  testWidgets(
    'delete failure hides old content and requires a new GET before retry',
    (tester) async {
      await open(tester, MealLogDetailPage(id: mealId, api: api));
      api.failure = const MealLogApiException(
        'Silme sonucu belirsiz.',
        uncertain: true,
      );
      await tapVisible(tester, find.text('Öğünü sil'));
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(api.deletes, 1);
      expect(find.text('Sentetik çorba'), findsNothing);
      expect(find.text('Öğünü sil'), findsNothing);
      api.failure = null;
      await tapVisible(tester, find.text('Durumu yenile'));
      expect(api.reads, 2);
      expect(find.text('Sentetik çorba'), findsOneWidget);
    },
  );
  testWidgets(
    'owner change rejects late history response and background hides health data',
    (tester) async {
      await open(tester, MealLogHistoryPage(api: api));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('Sentetik çorba'), findsNothing);
      final pending = Completer<MealLogPage>();
      api.pendingList = pending.future;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      session.end();
      await tester.pump();
      pending.complete((items: [sampleMeal()], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sentetik çorba'), findsNothing);
      expect(find.textContaining('oturumunuz doğrulanmalıdır'), findsOneWidget);
    },
  );
  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets(
        'form remains usable at $size ${brightness.name} with large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await open(tester, ManualMealLogPage(api: api));
          for (final label in [
            'Yemek adı',
            'Miktar (gram)',
            'Protein (g)',
            'Not',
          ]) {
            await tester.ensureVisible(mealField(label));
            await tester.pumpAndSettle();
            expect(mealField(label).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tapVisible(tester, find.text('Kaydet'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Finder mealField(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
