import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_page.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'device_health_test_support.dart';
import 'water_test_support.dart';

void main() {
  late FakeDeviceHealthSource source;
  late WaterTestSession session;
  setUp(() {
    source = FakeDeviceHealthSource();
    session = WaterTestSession();
  });
  tearDown(() => session.dispose());
  Future<void> open(WidgetTester tester, {ThemeData? theme}) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: theme,
          home: DeviceHealthPage(
            reader: DeviceHealthReader(source: source),
            now: () => DateTime(2026, 11, 18, 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    final finder = find.text(text);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 200, maxScrolls: 30);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('no automatic reading, empty results are not demo or zero', (
    tester,
  ) async {
    await open(tester);
    expect(source.reads, 0);
    expect(source.requests, 0);
    expect(find.text('Henüz cihazdan veri okunmadı.'), findsOneWidget);
    await tap(tester, 'Bugünün verilerini oku');
    expect(source.reads, 5);
    for (final metric in DeviceHealthMetric.values) {
      await tester.scrollUntilVisible(find.text(metric.label), 200);
      final card = find.ancestor(
        of: find.text(metric.label),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Bugün için kayıt bulunamadı.'),
        ),
        findsOneWidget,
      );
    }
    expect(find.textContaining('0 adım'), findsNothing);
    expect(find.textContaining('0.0 kcal'), findsNothing);
  });
  testWidgets('permission request alone never reads health records', (
    tester,
  ) async {
    source.permissions[HealthDataType.STEPS] = false;
    await open(tester);
    await tap(tester, 'Okuma izinlerini iste');
    expect(source.requested, [HealthDataType.STEPS]);
    expect(source.reads, 0);
    expect(find.textContaining('İzin isteği tamamlandı.'), findsOneWidget);
  });
  testWidgets(
    'loading never displays fake zero and duplicate taps are locked',
    (tester) async {
      final pending = Completer<List<DeviceHealthSample>>();
      source.pending = pending.future;
      await open(tester);
      await tap(tester, 'Bugünün verilerini oku', settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Bugün için kayıt bulunamadı.'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        null,
      );
      pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  testWidgets('unsupported device and installation required are distinct', (
    tester,
  ) async {
    source.support = DeviceHealthAvailability.unsupported;
    await open(tester);
    await tap(tester, 'Bugünün verilerini oku');
    expect(
      find.text('Bu cihazda sağlık verisi okuma desteklenmiyor.'),
      findsOneWidget,
    );
    expect(source.reads, 0);
    source.support = DeviceHealthAvailability.installRequired;
    await tap(tester, 'Okuma izinlerini iste');
    expect(
      find.text('Health Connect kurulmalı veya güncellenmeli.'),
      findsOneWidget,
    );
    await tap(tester, 'Health Connect kur / güncelle');
    expect(source.installs, 1);
    expect(source.requests, 0);
  });
  testWidgets('iOS empty never claims READ denial or granted permission', (
    tester,
  ) async {
    source.isIOS = true;
    await open(tester);
    await tap(tester, 'Bugünün verilerini oku');
    for (final metric in DeviceHealthMetric.values) {
      await tester.scrollUntilVisible(find.text(metric.label), 200);
      final card = find.ancestor(
        of: find.text(metric.label),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Veri yok veya okuma izni kapalı.'),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Okuma izni verilmedi veya geri alındı.'), findsNothing);
  });
  testWidgets('real source records disappear on account change', (
    tester,
  ) async {
    source.rows[HealthDataType.STEPS] = [
      healthSample(
        start: DateTime(2026, 11, 18, 10),
        source: 'Synthetic Watch',
      ),
    ];
    await open(tester);
    await tap(tester, 'Bugünün verilerini oku');
    expect(find.textContaining('123 adım · Synthetic Watch'), findsOneWidget);
    session.changeOwner();
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic Watch'), findsNothing);
    expect(
      find.text('Bu ekranı mevcut hesabınızla yeniden açın.'),
      findsOneWidget,
    );
    expect(source.reads, 5);
  });
  testWidgets('logout during a read discards late results and next queries', (
    tester,
  ) async {
    final pending = Completer<List<DeviceHealthSample>>();
    source.pending = pending.future;
    await open(tester);
    await tap(tester, 'Bugünün verilerini oku', settle: false);
    session.end();
    await tester.pump();
    pending.complete([healthSample(source: 'old.account')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('old.account'), findsNothing);
    expect(source.reads, 1);
  });
  testWidgets(
    'background clears records, resume does not automatically reread',
    (tester) async {
      source.rows[HealthDataType.STEPS] = [
        healthSample(
          start: DateTime(2026, 11, 18, 10),
          source: 'Synthetic Watch',
        ),
      ];
      await open(tester);
      await tap(tester, 'Bugünün verilerini oku');
      expect(find.textContaining('Synthetic Watch'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic Watch'), findsNothing);
      expect(source.reads, 5);
    },
  );
  testWidgets('provider errors shown with explicit manual retry', (
    tester,
  ) async {
    source.errors[HealthDataType.STEPS] = StateError('synthetic');
    await open(tester);
    await tap(tester, 'Bugünün verilerini oku');
    expect(find.text('Veri okunamadı. Yeniden deneyin.'), findsOneWidget);
    source.errors.clear();
    await tap(tester, 'Bugünün verilerini oku');
    expect(find.text('Veri okunamadı. Yeniden deneyin.'), findsNothing);
    expect(source.reads, 10);
  });
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('small screen and large text fit ${theme.brightness}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, theme: theme);
      await tap(tester, 'Bugünün verilerini oku');
      await tester.scrollUntilVisible(find.text('Nabız'), 200, maxScrolls: 30);
      expect(tester.takeException(), null);
    });
  }
}
