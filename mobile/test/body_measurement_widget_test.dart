import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_form_page.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_detail_page.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/measurement_chart.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'body_measurement_test_support.dart';

void main() {
  late BodyTestSession session;
  late BodyTestApi api;
  setUp(() {
    session = BodyTestSession();
    api = BodyTestApi(session);
  });
  tearDown(() => session.dispose());
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool settle = true,
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    final navigator = GlobalKey<NavigatorState>();
    final route =
        child is BodyMeasurementFormPage || child is BodyMeasurementDetailPage;
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(body: route ? const SizedBox() : child),
        ),
      ),
    );
    if (route) {
      unawaited(
        navigator.currentState!.push<bool>(
          MaterialPageRoute(builder: (_) => child),
        ),
      );
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, String text) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final target = find.text(
      text == 'Kaydet'
          ? (find.text('Ölçümümü kaydet').evaluate().isNotEmpty
                ? 'Ölçümümü kaydet'
                : 'Değişiklikleri kaydet')
          : text,
    );
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test(
    'chart points omit unknown measurements and preserve real dates, zero fat and order',
    () {
      final rows = [
        bodySample(weight: null, waist: 84, at: DateTime.utc(2026, 11, 19)),
        bodySample(weight: 73, at: DateTime.utc(2026, 11, 1)),
        bodySample(weight: 72, at: DateTime.utc(2026, 11, 10)),
      ];
      final points = measurementPoints(rows, 'weightKg');
      expect(points.map((p) => p.value), [73, 72]);
      expect(points.first.at, DateTime.utc(2026, 11, 1));
      expect(measurementPoints(rows, 'chestCm'), isEmpty);
      expect(
        measurementPoints([
          bodySample(weight: null, fat: 0),
        ], 'bodyFatPercent').single.value,
        0,
      );
    },
  );
  testWidgets('new user has a true empty state and no charts or fake zero', (
    tester,
  ) async {
    await pump(tester, ProgressPage(api: api));
    expect(
      find.text('Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.'),
      findsOneWidget,
    );
    expect(find.byType(MeasurementChart), findsNothing);
    expect(find.text('0 kg'), findsNothing);
  });
  testWidgets('loading hides previous records and errors have manual retry', (
    tester,
  ) async {
    final pending = Completer<List<BodyMeasurement>>();
    api.pendingHistory = pending.future;
    await pump(tester, ProgressPage(api: api), settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Henüz ölçüm'), findsNothing);
    pending.completeError(
      const BodyMeasurementApiException('Sentetik ağ hatası'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sentetik ağ hatası'), findsOneWidget);
    api.pendingHistory = null;
    await tap(tester, 'Ölçümleri yenile');
    expect(find.textContaining('Henüz ölçüm'), findsOneWidget);
  });
  testWidgets(
    'graphs show only available fields and late data is removed at account change',
    (tester) async {
      api.rows = [
        bodySample(weight: 73),
        bodySample(
          id: '33333333-3333-4333-8333-333333333333',
          weight: null,
          waist: 84,
          at: DateTime.utc(2026, 11, 20),
        ),
      ];
      await pump(tester, ProgressPage(api: api));
      expect(
        find.byKey(const ValueKey('measurement-chart-weightKg')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('measurement-chart-chestCm')),
        findsNothing,
      );
      final pending = Completer<List<BodyMeasurement>>();
      api.pendingHistory = pending.future;
      await tester.scrollUntilVisible(
        find.text('Ölçümleri yenile'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Ölçümleri yenile'));
      await tester.pump();
      final previous = api.rows;
      api.rows = [];
      api.pendingHistory = null;
      session.changeOwner();
      await tester.pump();
      pending.complete(previous);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('measurement-chart-weightKg')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'logout and inactive tabs clear charts and do not fetch in background',
    (tester) async {
      api.rows = [bodySample()];
      await pump(tester, ProgressPage(api: api, active: false));
      expect(api.reads, 0);
      await pump(tester, ProgressPage(api: api));
      expect(api.reads, 1);
      session.end();
      await tester.pumpAndSettle();
      expect(find.byType(MeasurementChart), findsNothing);
    },
  );
  testWidgets(
    'form requires a measurement and validates positive values and percentages',
    (tester) async {
      await pump(tester, BodyMeasurementFormPage(api: api));
      await tap(tester, 'Kaydet');
      expect(find.text('En az bir ölçüm girin.'), findsOneWidget);
      expect(api.creates, 0);
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-weightKg')),
        '-1',
      );
      await tap(tester, 'Kaydet');
      expect(find.text('Sıfırdan büyük bir ölçüm girin.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-weightKg')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-bodyFatPercent')),
        '101',
      );
      await tap(tester, 'Kaydet');
      expect(find.text('0–100 arasında bir yüzde girin.'), findsOneWidget);
      expect(api.creates, 0);
    },
  );
  testWidgets('partial editing sends only changed fields and explicit null', (
    tester,
  ) async {
    final row = bodySample(waist: 84, note: 'Sentetik not');
    api.rows = [row];
    await pump(tester, BodyMeasurementFormPage(api: api, initial: row));
    await tester.enterText(
      find.byKey(const ValueKey('measurement-field-waistCm')),
      '',
    );
    await tester.enterText(find.byKey(const ValueKey('measurement-note')), '');
    await tap(tester, 'Kaydet');
    expect(api.updates, 1);
    expect(api.changes, {'waistCm': null, 'note': null});
    expect(api.rows.single.weightKg, row.weightKg);
  });
  testWidgets(
    'confirmed delete removes a measurement but cancellation never sends DELETE',
    (tester) async {
      api.rows = [bodySample()];
      await pump(tester, BodyMeasurementDetailPage(id: bodyId, api: api));
      await tap(tester, 'Ölçümü sil');
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(api.deletes, 0);
      await tap(tester, 'Ölçümü sil');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(api.deletes, 1);
      expect(api.rows, isEmpty);
    },
  );
  testWidgets(
    'uncertain write blocks resubmission and account change clears form values',
    (tester) async {
      api.failure = const BodyMeasurementApiException(
        'Yanıt doğrulanamadı',
        uncertain: true,
      );
      await pump(tester, BodyMeasurementFormPage(api: api));
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-weightKg')),
        '73,5',
      );
      await tap(tester, 'Kaydet');
      expect(api.creates, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ölçümümü kaydet'),
            )
            .onPressed,
        isNull,
      );
      session.changeOwner();
      await tester.pumpAndSettle();
      expect(find.text('73,5'), findsNothing);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('real charts support large text and ${brightness.name} theme', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      api.rows = [
        bodySample(),
        bodySample(
          id: '33333333-3333-4333-8333-333333333333',
          weight: 72,
          waist: 84,
          at: DateTime.utc(2026, 11, 20),
        ),
      ];
      await pump(tester, ProgressPage(api: api));
      await tap(tester, 'Ölçümleri yenile');
      expect(tester.takeException(), isNull);
    });
  }
}
