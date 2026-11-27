import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_form_page.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_summary_card.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late WaterTestApi api;
  late DateTime now;
  setUp(() {
    session = WaterTestSession();
    api = WaterTestApi(session);
    now = DateTime(2026, 11, 17, 10);
  });
  tearDown(() => session.dispose());
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool settle = true,
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> form(WidgetTester tester, {WaterLog? initial}) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => WaterLogFormPage(
                  api: api,
                  now: () => now,
                  initial: initial,
                ),
              ),
            );
            if (context.mounted && saved == true) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Kaydedildi')));
            }
          },
          child: const Text('Başlat'),
        ),
      ),
    );
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Dashboard shows actual total without a water target and refreshes after adding water',
    (tester) async {
      api.total = 725;
      await pump(
        tester,
        HomePage(onViewNutrition: () {}, waterApi: api, now: () => now),
      );
      expect(find.text('725 ml'), findsOneWidget);
      expect(find.textContaining('2500 mL'), findsNothing);
      expect(find.textContaining('Örnek su hedefi'), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey('day-water-add')));
      expect(api.creates, 1);
      expect(find.text('975 ml'), findsOneWidget);
      expect(api.lastAmount, 250);
      expect(api.days.length, 2);
    },
  );
  testWidgets(
    'history add/edit/delete refreshes both total and history; deletion needs confirmation',
    (tester) async {
      await pump(tester, WaterHistoryPage(api: api, now: () => now));
      expect(find.text('Henüz su kaydı yok.'), findsOneWidget);
      await tapVisible(tester, find.text('Su kaydet'));
      await tapVisible(tester, find.widgetWithText(ActionChip, '250 mL'));
      await tapVisible(tester, find.text('Kaydet'));
      expect(find.text('250 mL'), findsNWidgets(2));
      expect(api.pages.length, 2);
      await tapVisible(tester, find.text('Düzenle'));
      await tester.enterText(amountField, '375,5');
      await tapVisible(tester, find.text('Kaydet'));
      expect(api.updates, 1);
      expect(api.lastAmount, 375.5);
      expect(find.text('375.5 mL'), findsNWidgets(2));
      await tapVisible(tester, find.text('Kaydı sil'));
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(api.deletes, 0);
      await tapVisible(tester, find.text('Kaydı sil'));
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(api.deletes, 1);
      expect(find.text('0 mL'), findsOneWidget);
      expect(find.text('Henüz su kaydı yok.'), findsOneWidget);
      expect(api.pages.length, 4);
      expect(api.days.length, 4);
    },
  );
  testWidgets(
    'validates positive amounts and saves comma decimal exactly once',
    (tester) async {
      await form(tester);
      for (final input in ['', '0', '-1', 'NaN', 'Infinity', '1e3', '1,2,3']) {
        await tester.enterText(amountField, input);
        await tapVisible(tester, find.text('Kaydet'));
        expect(
          find.text('Sıfırdan büyük bir su miktarı girin.'),
          findsOneWidget,
        );
      }
      final pending = Completer<WaterLog>();
      api.pendingWrite = pending.future;
      await tester.enterText(amountField, '125,5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Kaydet'));
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      expect(api.creates, 1);
      expect(api.lastAmount, 125.5);
      expect(api.lastTime, now);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull,
      );
      pending.complete(waterSample(amount: 125.5));
      await tester.pumpAndSettle();
      expect(find.text('Kaydedildi'), findsOneWidget);
    },
  );
  testWidgets(
    'uncertain save cannot be retried automatically or by a duplicate tap',
    (tester) async {
      api.failure = const WaterLogApiException(
        'Bağlantı kesildi.',
        uncertain: true,
      );
      await form(tester, initial: waterSample());
      await tapVisible(tester, find.text('Kaydet'));
      expect(api.updates, 1);
      expect(find.textContaining('Yeniden kaydetmeden önce'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'failed delete hides stale totals and rows until explicit refresh',
    (tester) async {
      api.rows = [waterSample()];
      api.total = 250;
      await pump(tester, WaterHistoryPage(api: api, now: () => now));
      api.failure = const WaterLogApiException(
        'Silme sonucu belirsiz.',
        uncertain: true,
      );
      await tapVisible(tester, find.text('Kaydı sil'));
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('250 mL'), findsNothing);
      expect(find.text('Kaydı sil'), findsNothing);
      expect(api.deletes, 1);
      api.failure = null;
      await tapVisible(tester, find.text('Su bilgilerini yenile'));
      expect(find.text('250 mL'), findsNWidgets(2));
      expect(api.pages.length, 2);
    },
  );
  testWidgets('loading is distinct from zero and read error supports retry', (
    tester,
  ) async {
    final pending = Completer<num>();
    api.pendingTotal = pending.future;
    await pump(
      tester,
      WaterSummaryCard(api: api, now: () => now),
      settle: false,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('0 mL'), findsNothing);
    pending.completeError(const WaterLogApiException('Su servisi kapalı.'));
    await tester.pumpAndSettle();
    expect(find.text('Su servisi kapalı.'), findsOneWidget);
    expect(find.text('0 mL'), findsNothing);
    api.pendingTotal = null;
    api.total = 0;
    await tapVisible(tester, find.text('Su bilgilerini yenile'));
    expect(find.text('0 mL'), findsOneWidget);
    expect(find.text('Bugün henüz su kaydınız yok.'), findsOneWidget);
  });
  testWidgets(
    'midnight timer loads a new local day without keeping yesterday total',
    (tester) async {
      now = DateTime(2026, 11, 17, 23, 59, 59);
      api.total = 250;
      await pump(tester, WaterSummaryCard(api: api, now: () => now));
      expect(api.days.single.from.day, 17);
      now = DateTime(2026, 11, 18);
      api.total = 0;
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(api.days.last.from.day, 18);
      expect(find.text('250 mL'), findsNothing);
      expect(find.text('0 mL'), findsOneWidget);
    },
  );
  testWidgets(
    'late response from yesterday is discarded and current day is fetched',
    (tester) async {
      final pending = Completer<num>();
      api.pendingTotal = pending.future;
      await pump(
        tester,
        WaterSummaryCard(api: api, now: () => now),
        settle: false,
      );
      now = DateTime(2026, 11, 18);
      api.pendingTotal = null;
      api.total = 750;
      pending.complete(250);
      await tester.pumpAndSettle();
      expect(api.days.length, 2);
      expect(find.text('250 mL'), findsNothing);
      expect(find.text('750 mL'), findsOneWidget);
    },
  );
  testWidgets(
    'account change, hidden tab and background clear private water totals',
    (tester) async {
      api.total = 250;
      await pump(
        tester,
        WaterSummaryCard(
          key: const ValueKey('water'),
          api: api,
          now: () => now,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('250 mL'), findsNothing);
      api.total = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('0 mL'), findsOneWidget);
      final old = Completer<num>();
      api.pendingTotal = old.future;
      await tester.tap(find.text('Su bilgilerini yenile'));
      await tester.pump();
      api.pendingTotal = null;
      api.total = 500;
      session.changeOwner();
      await tester.pump();
      old.complete(250);
      await tester.pumpAndSettle();
      expect(find.text('250 mL'), findsNothing);
      expect(find.text('500 mL'), findsOneWidget);
      session.end();
      await tester.pumpAndSettle();
      expect(find.text('500 mL'), findsNothing);
    },
  );
  testWidgets('save completed in background remains locked on return', (
    tester,
  ) async {
    final pending = Completer<WaterLog>();
    api.pendingWrite = pending.future;
    await form(tester, initial: waterSample());
    await tester.ensureVisible(find.text('Kaydet'));
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    pending.complete(waterSample());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.updates, 1);
    expect(find.textContaining('Su kaydı tamamlandı.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('history uses explicit pagination', (tester) async {
    api.rows = [waterSample()];
    api.total = 250;
    api.count = 11;
    await pump(tester, WaterHistoryPage(api: api, now: () => now));
    await tapVisible(tester, find.text('Sonraki sayfa'));
    expect(api.pages, [1, 2]);
    expect(find.text('11 kayıt · Sayfa 2'), findsOneWidget);
  });
  testWidgets(
    'hidden Dashboard tab does not fetch and clears its water total',
    (tester) async {
      api.total = 250;
      await pump(
        tester,
        WaterSummaryCard(
          key: const ValueKey('tab-water'),
          api: api,
          now: () => now,
          active: false,
        ),
      );
      expect(api.days, isEmpty);
      await pump(
        tester,
        WaterSummaryCard(
          key: const ValueKey('tab-water'),
          api: api,
          now: () => now,
        ),
      );
      expect(api.days.length, 1);
      expect(find.text('250 mL'), findsOneWidget);
      await pump(
        tester,
        WaterSummaryCard(
          key: const ValueKey('tab-water'),
          api: api,
          now: () => now,
          active: false,
        ),
      );
      expect(api.days.length, 1);
      expect(find.text('250 mL'), findsNothing);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'water card and form fit a narrow ${brightness.name} screen with large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pump(
          tester,
          SingleChildScrollView(
            child: WaterSummaryCard(api: api, now: () => now),
          ),
        );
        await tapVisible(tester, find.text('Su kaydet'));
        await tapVisible(tester, find.widgetWithText(ActionChip, '500 mL'));
        await tapVisible(tester, find.text('Kaydet'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder get amountField => find.byType(TextFormField);
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
