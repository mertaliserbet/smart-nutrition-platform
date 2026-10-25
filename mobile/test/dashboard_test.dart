import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/home/dashboard_demo_data.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';

void main() {
  testWidgets('clearly labels synthetic values and shows all daily summaries', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.pumpAndSettle();

    expect(find.text('Örnek veriler · Demo').hitTestable(), findsOneWidget);
    expect(find.text(DashboardDemo.disclaimer), findsOneWidget);
    expect(find.text('24 Ekim 2026 · Örnek gün'), findsOneWidget);
    expect(find.text('1680'), findsOneWidget);
    expect(find.text('Örnek hedef: 2200 kcal'), findsOneWidget);
    expect(find.text('84 / 110 g'), findsOneWidget);
    expect(find.text('192 / 260 g'), findsOneWidget);
    expect(find.text('64 / 72 g'), findsOneWidget);
    expect(find.text('1250 mL'), findsOneWidget);
    expect(find.text('Örnek hedef: 2500 mL · %50'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(1680 / 2200, 0.001),
    );
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    expect(find.text('Son öğünler'), findsOneWidget);
    expect(find.text('Yoğurt, meyve ve ceviz'), findsOneWidget);
    expect(
      find.text('Örnek kayıtlar · Kalori değerleri tahminidir'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal program works without a dietitian connection', (
    tester,
  ) async {
    var viewedNutrition = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: HomePage(onViewNutrition: () => viewedNutrition = true),
        ),
      ),
    );

    expect(find.text('Kişisel program · Örnek'), findsOneWidget);
    expect(find.text('Diyetisyensiz kullanım'), findsOneWidget);
    final action = find.text('Beslenmeye göz at');
    await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(action);

    expect(viewedNutrition, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assigned demo program identifies its source and read-only state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: HomePage(
            demoData: DashboardDemo.assigned,
            onViewNutrition: () {},
          ),
        ),
      ),
    );

    expect(find.text('Diyetisyen programı · Örnek'), findsOneWidget);
    expect(find.text('Örnek Diyetisyen'), findsOneWidget);
    expect(
      find.text(
        'Atanmış program ve hedefler salt okunurdur. Gerçek tüketim ayrı kaydedilir.',
      ),
      findsOneWidget,
    );
    expect(find.text('Diyetisyensiz kullanım'), findsNothing);
    expect(find.text('Düzenle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick actions open dismissible previews without changing data', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());

    for (final label in ['Su ekle', 'Aktivite ekle', 'Tahlil ekle']) {
      final action = find.text(label);
      await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('$label · Demo'), findsOneWidget);
      expect(
        find.text('Bu demo önizlemesinde yeni kayıt oluşturulmaz.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('$label · Demo'), findsNothing);
      expect(find.text('1250 mL'), findsOneWidget);
      expect(find.text('1680'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('progress indicators expose units, targets and demo semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const SmartNutritionApp());
      for (final (label, value) in [
        ('Örnek kalori hedefi, 1680 / 2200 kcal', '76'),
        ('Örnek Protein hedefi, 84 / 110 g', '76'),
        ('Örnek Karbonhidrat hedefi, 192 / 260 g', '74'),
        ('Örnek Yağ hedefi, 64 / 72 g', '89'),
        ('Örnek su hedefi, 1250 / 2500 mL', '50'),
      ]) {
        final indicator = find.byWidgetPredicate(
          (widget) =>
              widget is ProgressIndicator && widget.semanticsLabel == label,
        );
        await Scrollable.ensureVisible(
          tester.element(indicator),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.getSemanticsData().value, value);
      }
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    for (final viewport in [
      (size: const Size(320, 640), scale: 2.0),
      (size: const Size(390, 844), scale: 1.0),
      (size: const Size(1024, 768), scale: 1.0),
      (size: const Size(1024, 768), scale: 2.0),
    ]) {
      testWidgets(
        'dashboard adapts to ${viewport.size} at ${viewport.scale}x in ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          await tester.pumpWidget(const SmartNutritionApp());
          await tester.pumpAndSettle();

          for (final title in [
            'Günlük enerji',
            'Makro dengesi',
            'Su tüketimi',
            'Hızlı işlemler',
            'Beslenme programı',
            'Son öğünler',
          ]) {
            final heading = find.text(title);
            await Scrollable.ensureVisible(
              tester.element(heading),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(heading.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }

          final action = find.text('Su ekle');
          await Scrollable.ensureVisible(
            tester.element(action),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(action);
          await tester.pumpAndSettle();
          final close = find.text('Kapat');
          await Scrollable.ensureVisible(tester.element(close), alignment: 0.5);
          await tester.pumpAndSettle();
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.text('Su ekle · Demo'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
