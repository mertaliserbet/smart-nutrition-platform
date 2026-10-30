import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/forgot_password_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('first frame stays signed out in ${brightness.name} theme', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const SmartNutritionApp());
      expect(find.byType(LoginPage), findsOneWidget);
      expectNoProtectedScreens();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(LoginPage)));
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, brightness);
      expect(find.byTooltip('Kimlik ekranları (önizleme)'), findsNothing);
      expectNoProtectedScreens();
    });

    for (final (route, page, backLabel) in [
      ('/register', RegisterPage, 'Zaten hesabınız var mı? Girişe dön'),
      ('/email-verification', EmailVerificationPage, 'Önceki ekrana dön'),
      ('/forgot-password', ForgotPasswordPage, 'Giriş ekranına dön'),
    ]) {
      for (final useSystemBack in [false, true]) {
        final backMethod = useSystemBack ? 'system back' : 'footer';
        testWidgets(
          'public startup $route returns to login with $backMethod in ${brightness.name}',
          (tester) async {
            tester.platformDispatcher.defaultRouteNameTestValue = route;
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            addTearDown(
              tester.platformDispatcher.clearDefaultRouteNameTestValue,
            );
            addTearDown(
              tester.platformDispatcher.clearPlatformBrightnessTestValue,
            );

            await tester.pumpWidget(const SmartNutritionApp());
            expectNoProtectedScreens();
            await tester.pumpAndSettle();
            expect(find.byType(page), findsOneWidget);
            final navigator = Navigator.of(tester.element(find.byType(page)));
            expect(navigator.canPop(), isTrue);
            final back = find.widgetWithText(TextButton, backLabel);
            expect(tester.widget<TextButton>(back).onPressed, isNotNull);

            if (useSystemBack) {
              await tester.binding.handlePopRoute();
            } else {
              await tester.ensureVisible(back);
              await tester.pumpAndSettle();
              await tester.tap(back);
            }
            await tester.pumpAndSettle();

            expect(find.byType(LoginPage), findsOneWidget);
            expect(find.byType(page), findsNothing);
            expect(navigator.canPop(), isFalse);
            expectNoProtectedScreens();
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(find.byType(LoginPage), findsOneWidget);
            expectNoProtectedScreens();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final route in [
    '/dashboard',
    '/home',
    '/nutrition',
    '/progress',
    '/profile',
    '/meal-log',
    '/unknown',
  ]) {
    testWidgets('signed-out named navigation to $route returns to login', (
      tester,
    ) async {
      await tester.pumpWidget(const SmartNutritionApp());
      Navigator.of(
        tester.element(find.byType(LoginPage)),
      ).pushNamed<void>(route, arguments: {'isAuthenticated': true});
      await tester.pump();
      expectNoProtectedScreens();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expectNoProtectedScreens();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expectNoProtectedScreens();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('protected startup link never mounts a protected route', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/nutrition';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(const SmartNutritionApp());
    expect(find.byType(LoginPage), findsOneWidget);
    expectNoProtectedScreens();
    await tester.pumpAndSettle();
    expect(
      Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (route, page) in [
    ('/register', RegisterPage),
    ('/email-verification', EmailVerificationPage),
    ('/forgot-password', ForgotPasswordPage),
  ]) {
    testWidgets('signed-out users can open $route and return safely', (
      tester,
    ) async {
      await tester.pumpWidget(const SmartNutritionApp());
      Navigator.of(
        tester.element(find.byType(LoginPage)),
      ).pushNamed<void>(route);
      await tester.pumpAndSettle();
      expect(find.byType(page), findsOneWidget);
      expectNoProtectedScreens();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expectNoProtectedScreens();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('valid form input never unlocks the application', (tester) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'ornek@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Sentetik parola');
    final submit = find.widgetWithText(FilledButton, 'Giriş yap');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.text('Giriş şu anda kullanıma açık değil. Oturum açılmadı.'),
      findsOneWidget,
    );
    expectNoProtectedScreens();
    await tester.pumpWidget(const SmartNutritionApp(key: ValueKey('restart')));
    expect(find.byType(LoginPage), findsOneWidget);
    expectNoProtectedScreens();
    expect(tester.takeException(), isNull);
  });
}

void expectNoProtectedScreens() {
  for (final page in [
    MainShell,
    HomePage,
    NutritionPage,
    ProgressPage,
    ProfilePage,
    ManualMealLogPage,
    NavigationBar,
  ]) {
    expect(find.byType(page, skipOffstage: false), findsNothing);
  }
}
