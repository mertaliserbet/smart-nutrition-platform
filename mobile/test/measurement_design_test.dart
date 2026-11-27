import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_form_page.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/measurement_chart.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'body_measurement_test_support.dart';

void main() {
  test(
    'small known values are not displayed as zero and large values remain readable',
    () {
      expect(measurementValue(.00001), '0,00001');
      expect(measurementValue(1e25), isNotEmpty);
      expect(measurementValue(0), '0');
    },
  );
  late BodyTestSession session;
  late BodyTestApi api;
  final now = DateTime(2026, 11, 27, 12);
  setUp(() {
    session = BodyTestSession();
    api = BodyTestApi(session);
    api.rows = [
      for (final (i, day) in [1, 6, 11, 16, 22, 27].indexed)
        bodySample(
          id: '11111111-1111-4111-8111-${(i + 1).toString().padLeft(12, '0')}',
          weight: [74, 73.7, 73.9, 73.2, 72.8, 72.4][i],
          waist: 84 - i * .4,
          hip: 100 - i * .3,
          chest: 97 - i * .2,
          fat: 23.5 - i * .22,
          at: DateTime(2026, 11, day, 8, 10),
        ),
    ];
  });
  tearDown(() => session.dispose());
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          home: Scaffold(
            body: ProgressPage(api: api, now: () => now),
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

  testWidgets(
    'approved summary uses real first and last measurements and filters dates and fields',
    (tester) async {
      await mount(tester);
      expect(find.text('Her adımın\nbir izi var.'), findsOneWidget);
      expect(find.text('72,4'), findsOneWidget);
      expect(find.text('−1,6 kg'), findsOneWidget);
      expect(find.text('Son 30 gün · 6 ölçüm'), findsOneWidget);
      await tap(tester, find.text('7 gün'));
      expect(find.text('Son 7 gün · 2 ölçüm'), findsOneWidget);
      expect(
        tester
            .widget<MeasurementChart>(find.byType(MeasurementChart))
            .rows
            .length,
        2,
      );
      await tap(
        tester,
        find.byKey(const ValueKey('measurement-metric-picker')),
      );
      await tester.tap(find.text('Bel').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MeasurementChart>(find.byType(MeasurementChart)).field,
        'waistCm',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history expands, preserves unknowns and exposes record management',
    (tester) async {
      api.rows = [bodySample(weight: 72.4, at: now)];
      await mount(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('measurement-record-$bodyId')),
      );
      expect(find.text('Belirtilmemiş'), findsNWidgets(4));
      expect(find.text('Kaydı yönet'), findsOneWidget);
      expect(find.text('0 cm'), findsNothing);
      expect(find.text('0 %'), findsNothing);
    },
  );

  testWidgets(
    'all history is available while initial preview shows three records',
    (tester) async {
      await mount(tester);
      Finder records() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'measurement-record-',
            ),
      );
      expect(records(), findsNWidgets(3));
      await tap(tester, find.text('Tümünü gör'));
      expect(records(), findsNWidgets(6));
      await tap(tester, find.text('Daha az göster'));
      expect(records(), findsNWidgets(3));
    },
  );

  testWidgets(
    'bottom sheet saves comma decimal through API and refreshes actual records',
    (tester) async {
      await mount(tester);
      await tap(tester, find.text('Yeni ölçüm ekle'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Yeni bir adım kaydet.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BodyMeasurementFormPage),
          matching: find.text('kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BodyMeasurementFormPage),
          matching: find.text('cm'),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byType(BodyMeasurementFormPage),
          matching: find.text('%'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-waistCm')),
        '81,5',
      );
      await tap(tester, find.text('Ölçümümü kaydet'));
      expect(api.creates, 1);
      expect(api.changes!['waistCm'], 81.5);
      expect(api.changes!['weightKg'], isNull);
      expect(find.byType(BodyMeasurementFormPage), findsNothing);
      expect(api.reads, 2);
      expect(find.text('72,4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain sheet write cannot be resubmitted and never displays success',
    (tester) async {
      await mount(tester);
      await tap(tester, find.text('Yeni ölçüm ekle'));
      api.failure = const BodyMeasurementApiException(
        'Yanıt doğrulanamadı',
        uncertain: true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-weightKg')),
        '72,2',
      );
      await tap(tester, find.text('Ölçümümü kaydet'));
      expect(api.creates, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ölçümümü kaydet'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Ölçüm işlemi tamamlandı.'), findsNothing);
    },
  );

  testWidgets(
    'pending sheet write blocks dismissal and account change hides draft',
    (tester) async {
      await mount(tester);
      await tap(tester, find.text('Yeni ölçüm ekle'));
      final pending = Completer<BodyMeasurement>();
      api.pendingWrite = pending.future;
      await tester.enterText(
        find.byKey(const ValueKey('measurement-field-weightKg')),
        '72,2',
      );
      await tester.ensureVisible(find.text('Ölçümümü kaydet'));
      await tester.tap(find.text('Ölçümümü kaydet'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BodyMeasurementFormPage), findsOneWidget);
      session.changeOwner();
      await tester.pump();
      expect(find.text('72,2'), findsNothing);
      pending.complete(bodySample());
      await tester.pumpAndSettle();
      expect(find.text('Ölçüm işlemi tamamlandı.'), findsNothing);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('measurement page and sheet fit $width px with large text', (
      tester,
    ) async {
      await mount(tester, width: width, scale: 2);
      await tap(tester, find.text('Ölçümleri yenile'));
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Yeni ölçüm ekle'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ölçümümü kaydet'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    });
  }
}
