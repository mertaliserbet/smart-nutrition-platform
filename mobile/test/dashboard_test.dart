import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_theme.dart';

void main() {
  testWidgets(
    'transient widths recover without stale layout or negative card sizes',
    (tester) async {
      final width = ValueNotifier<double>(0);
      addTearDown(width.dispose);
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
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
      for (final value in [
        0.0,
        1.0,
        32.0,
        100.0,
        200.0,
        240.0,
        320.0,
        700.0,
        0.0,
        390.0,
      ]) {
        width.value = value;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width=$value');
        expect(
          find.text('Günlük enerji'),
          value < 240 ? findsNothing : findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'unavailable photo/barcode actions never simulate a successful record',
    (tester) async {
      await pumpMainShell(tester);
      for (final label in ['Fotoğraf', 'Barkod']) {
        final button = find.widgetWithText(TextButton, label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(button).onPressed, isNull);
      }
      expect(find.text('Aktivite ekle'), findsNothing);
      expect(find.text('Tahlil ekle'), findsNothing);
      expect(find.textContaining('kaydedildi'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  for (final brightness in Brightness.values) {
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
        'day page fits ${viewport.size} at ${viewport.scale}x with $brightness platform theme',
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
          for (final title in [
            'Günlük enerji',
            'Su molası',
            'Görüşmelerim',
            'Bugünkü planım',
          ]) {
            final heading = find.text(title);
            await tester.ensureVisible(heading);
            await tester.pumpAndSettle();
            expect(heading.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          final theme = Theme.of(tester.element(find.text('Günlük enerji')));
          expect(theme.colorScheme.primary, OnboardingTheme.ink);
          expect(theme.textTheme.bodyMedium!.fontFamily, 'Figtree');
          expect(find.byType(ProgressIndicator), findsNothing);
        },
      );
    }
  }
}

Future<void> pumpMainShell(WidgetTester tester) async {
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const MainShell(),
    ),
  );
  await tester.pumpAndSettle();
}
