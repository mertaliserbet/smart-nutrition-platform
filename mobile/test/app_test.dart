import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'package:smart_nutrition_mobile/features/chat/chat_page.dart';

void main() {
  const screens = [
    (
      label: 'Günüm',
      page: HomePage,
      description: 'Bugün kendine iyi gelecek bir adım seç.',
    ),
    (
      label: 'Planım',
      page: NutritionPage,
      description: 'Planını görüntülemek için oturumun doğrulanmalıdır.',
    ),
    (
      label: 'Ölçüm',
      page: ProgressPage,
      description: 'Ölçümleri görüntülemek için oturumunuz doğrulanmalıdır.',
    ),
    (
      label: 'Sohbet',
      page: ChatPage,
      description: 'Sohbeti görüntülemek için oturumun doğrulanmalıdır.',
    ),
    (
      label: 'Hesabım',
      page: ProfilePage,
      description: 'Hesabını görüntülemek için oturumun doğrulanmalıdır.',
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('opens home and navigation in ${brightness.name} Material 3', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpMainShell(tester);
      await tester.pumpAndSettle();

      expect(find.text('Smart Nutrition'), findsNothing);
      expect(find.text('Günün, senin\nritminde.'), findsOneWidget);
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
      expect(find.byTooltip('Kimlik ekranları (önizleme)'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switches between all tab screens and supports reselection', (
    tester,
  ) async {
    await pumpMainShell(tester);

    for (final (index, screen) in screens.indexed) {
      await selectTab(tester, screen.label);
      expect(find.byType(screen.page), findsOneWidget);
      expect(find.text(screen.description), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        [0, 2, 1, 3, 4][index],
      );

      await selectTab(tester, screen.label);
      expect(find.byType(screen.page), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('home action opens the nutrition tab', (tester) async {
    await pumpMainShell(tester);
    final action = find.byTooltip('Planımı aç');
    await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(NutritionPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back returns from another tab to home', (tester) async {
    await pumpMainShell(tester);
    await selectTab(tester, 'Hesabım');

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

    await pumpMainShell(tester);
    await selectTab(tester, 'Hesabım');
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
      4,
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

          await pumpMainShell(tester);
          await tester.pumpAndSettle();

          for (final screen in screens) {
            await selectTab(tester, screen.label);
            final description = find.text(screen.description);
            if (description.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                description,
                80,
                scrollable: find
                    .descendant(
                      of: find.byType(screen.page),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            }
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
              final action = find.byTooltip('Planımı aç');
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

    await pumpMainShell(tester);
    await selectTab(tester, 'Ölçüm');
    await tester.ensureVisible(find.text(screens[2].description));
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(ProgressPage),
      matching: find.byType(Scrollable),
    );
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));

    await selectTab(tester, 'Hesabım');
    await selectTab(tester, 'Ölçüm');

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
