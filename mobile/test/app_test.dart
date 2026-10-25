import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';

void main() {
  const screens = [
    (
      label: 'Ana Sayfa',
      page: HomePage,
      description:
          'Tüm değerler örnektir; size ait veri veya kişisel hedef önerisi değildir.',
    ),
    (
      label: 'Beslenme',
      page: NutritionPage,
      description: 'Öğünleriniz ve beslenme programınız burada yer alacak.',
    ),
    (
      label: 'İlerleme',
      page: ProgressPage,
      description:
          'Ölçüm geçmişiniz ve gelişim grafikleriniz burada yer alacak.',
    ),
    (
      label: 'Profil',
      page: ProfilePage,
      description:
          'Profil bilgileriniz ve gizlilik tercihleriniz burada yer alacak.',
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('opens home and navigation in ${brightness.name} Material 3', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const SmartNutritionApp());
      await tester.pumpAndSettle();

      expect(find.text('Smart Nutrition'), findsOneWidget);
      expect(find.text('Gününüz, bir bakışta.'), findsOneWidget);
      expect(find.text(screens.first.description), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      for (final screen in screens) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(screen.label),
          ),
          findsOneWidget,
        );
      }

      final theme = Theme.of(tester.element(find.byType(HomePage)));
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switches between all tab screens and supports reselection', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());

    for (final (index, screen) in screens.indexed) {
      await selectTab(tester, screen.label);
      expect(find.byType(screen.page), findsOneWidget);
      expect(find.text(screen.description), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );

      await selectTab(tester, screen.label);
      expect(find.byType(screen.page), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('home action opens the nutrition tab', (tester) async {
    await tester.pumpWidget(const SmartNutritionApp());
    final action = find.text('Beslenmeye göz at');
    await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(NutritionPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back returns from another tab to home', (tester) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await selectTab(tester, 'Profil');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('system theme changes preserve the selected tab', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const SmartNutritionApp());
    await selectTab(tester, 'Profil');
    expect(
      Theme.of(tester.element(find.byType(ProfilePage))).brightness,
      Brightness.light,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(ProfilePage))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 480), const Size(568, 320)]) {
      testWidgets(
        'all tabs support large text at $size in ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          await tester.pumpWidget(const SmartNutritionApp());
          await tester.pumpAndSettle();

          for (final screen in screens) {
            await selectTab(tester, screen.label);
            final description = find.text(screen.description);
            // A paragraph can be taller than the viewport at large text sizes.
            await Scrollable.ensureVisible(
              tester.element(description),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();

            expect(description.hitTestable(), findsOneWidget);
            expect(
              find
                  .descendant(
                    of: find.byType(NavigationBar),
                    matching: find.text(screen.label),
                  )
                  .hitTestable(),
              findsOneWidget,
            );

            if (screen.page == HomePage) {
              final action = find.text('Beslenmeye göz at');
              await Scrollable.ensureVisible(
                tester.element(action),
                alignment: 0.5,
              );
              await tester.pumpAndSettle();
              expect(action.hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('switching tabs preserves the scroll position', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const SmartNutritionApp());
    await selectTab(tester, 'İlerleme');
    await tester.ensureVisible(find.text(screens[2].description));
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(ProgressPage),
      matching: find.byType(Scrollable),
    );
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));

    await selectTab(tester, 'Profil');
    await selectTab(tester, 'İlerleme');

    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
    expect(tester.takeException(), isNull);
  });
}

Future<void> selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}
