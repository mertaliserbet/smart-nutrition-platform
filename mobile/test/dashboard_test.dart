import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

void main() {
  testWidgets('zero-width first frame recovers when layout becomes available', (
    tester,
  ) async {
    final width = ValueNotifier<double>(0);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, value, child) => SizedBox(
                width: value,
                child: HomePage(onViewNutrition: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);

    for (final value in [240.0, 320.0, 700.0, 0.0, 390.0]) {
      width.value = value;
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (value > 0) {
        expect(find.text('Hızlı işlemler'), findsOneWidget);
        for (final button in tester.widgetList<SizedBox>(
          find.ancestor(
            of: find.byType(OutlinedButton),
            matching: find.byType(SizedBox),
          ),
        )) {
          if (button.width != null) {
            expect(button.width, greaterThanOrEqualTo(0));
          }
        }
      }
    }
  });

  testWidgets('quick actions open dismissible previews without changing data', (
    tester,
  ) async {
    await pumpMainShell(tester);

    for (final label in ['Aktivite ekle', 'Tahlil ekle']) {
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
      expect(find.text('1250 mL'), findsNothing);
      expect(find.text('1680'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'dashboard handles tiny widths at ${scale}x in ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 900);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final width = ValueNotifier<double>(0);
          addTearDown(width.dispose);
          var viewedNutrition = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder<double>(
                    valueListenable: width,
                    builder: (context, value, child) => SizedBox(
                      width: value,
                      child: HomePage(
                        onViewNutrition: () => viewedNutrition = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);

          for (final value in [
            1.0,
            32.0,
            33.0,
            64.0,
            80.0,
            99.0,
            100.0,
            127.0,
            128.0,
            129.0,
            143.0,
            144.0,
            160.0,
            200.0,
            240.0,
            320.0,
            700.0,
            1024.0,
            0.0,
            390.0,
          ]) {
            width.value = value;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'width=$value');
            if (value > 32) {
              for (final title in [
                'Günlük enerji',
                'Makro dengesi',
                'Su tüketimi',
                'Hızlı işlemler',
                'Beslenme programı',
                'Son öğünler',
              ]) {
                expect(find.text(title), findsOneWidget);
              }
              expect(find.byType(OutlinedButton), findsNWidgets(4));
              expect(find.byType(ProgressIndicator), findsNothing);
            } else {
              expect(find.byType(OutlinedButton), findsNothing);
            }
          }

          final action = find.text('Beslenmeye göz at');
          await Scrollable.ensureVisible(
            tester.element(action),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(viewedNutrition, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final viewport in [
      (size: const Size(240, 480), scale: 1.0),
      (size: const Size(280, 640), scale: 2.0),
      (size: const Size(320, 640), scale: 2.0),
      (size: const Size(568, 320), scale: 1.5),
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

          await pumpMainShell(tester);
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

          final action = find.text('Aktivite ekle');
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
          expect(find.text('Aktivite ekle · Demo'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

// Exercise the shell as an isolated widget; this is not an authenticated app.
Future<void> pumpMainShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const MainShell(),
    ),
  );
}
