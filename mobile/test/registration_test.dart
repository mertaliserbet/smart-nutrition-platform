import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/auth/registration_api.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'successful registration waits for the API in ${brightness.name}',
      (tester) async {
        final api = PendingRegistrationApi();
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpRegistration(tester, api);
        await fillRegistration(tester);
        final button = find.widgetWithText(FilledButton, 'Kayıt ol');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final submit = tester.widget<FilledButton>(button).onPressed!;
        submit();
        submit();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(api.calls, 1);
        expect(api.payload, {
          'displayName': 'İpek Şen',
          'email': 'synthetic@example.test',
          'password': '  Sentetik 😀 şifre  ',
        });
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(EmailVerificationPage), findsNothing);
        for (final field in tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        )) {
          expect(field.enabled, isFalse);
        }
        for (final button in tester.widgetList<TextButton>(
          find.byType(TextButton),
        )) {
          expect(button.onPressed, isNull);
        }
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(RegisterPage), findsOneWidget);
        expectNoProtectedScreens();

        api.result.complete();
        await tester.pumpAndSettle();
        expect(find.byType(RegisterPage, skipOffstage: false), findsNothing);
        expect(find.byType(EmailVerificationPage), findsOneWidget);
        expect(find.text('synthetic@example.test'), findsOneWidget);
        expect(
          find.text(
            'Hesabınız oluşturuldu. Giriş için e-posta doğrulaması gerekir.',
          ),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(
          tester.widget<TextField>(find.byType(TextField).last).readOnly,
          isTrue,
        );
        expectNoProtectedScreens();
        expect(
          Theme.of(
            tester.element(find.byType(EmailVerificationPage)),
          ).brightness,
          brightness,
        );
        final back = find.text('Giriş ekranına dön');
        await tester.ensureVisible(back);
        await tester.pumpAndSettle();
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expectNoProtectedScreens();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final failure in [
    const RegistrationApiException(
      'Bu e-posta adresiyle bir hesap zaten var. Giriş yapmayı deneyebilirsiniz.',
    ),
    const RegistrationApiException(
      'Kayıt bilgileri kabul edilmedi. Şifrenizin 8–128 karakter olduğunu kontrol edin.',
    ),
    const RegistrationApiException(
      'Kayıt servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
    ),
    const RegistrationApiException.connection(),
  ]) {
    testWidgets('registration error stays signed out: ${failure.message}', (
      tester,
    ) async {
      final api = PendingRegistrationApi();
      await pumpRegistration(tester, api);
      await fillRegistration(tester);
      final submit = find.widgetWithText(FilledButton, 'Kayıt ol');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      api.result.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.text(failure.message), findsOneWidget);
      expect(api.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(
        find.byType(EmailVerificationPage, skipOffstage: false),
        findsNothing,
      );
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.enabled, isTrue);
      }
      expectNoProtectedScreens();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid form never starts registration or opens verification', (
    tester,
  ) async {
    final api = PendingRegistrationApi();
    await pumpRegistration(tester, api);
    final submit = find.widgetWithText(FilledButton, 'Kayıt ol');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    expect(find.text('Adınızı ve soyadınızı girin.'), findsOneWidget);
    expect(find.text('E-posta doğrulama adımını incele'), findsNothing);
    expect(
      find.byType(EmailVerificationPage, skipOffstage: false),
      findsNothing,
    );
    expectNoProtectedScreens();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late registration response cannot navigate a disposed page', (
    tester,
  ) async {
    final api = PendingRegistrationApi();
    await pumpRegistration(tester, api);
    await fillRegistration(tester);
    final submit = find.widgetWithText(FilledButton, 'Kayıt ol');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    api.result.complete();
    await tester.pumpAndSettle();
    expect(find.byType(EmailVerificationPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpRegistration(WidgetTester tester, RegistrationApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const LoginPage(),
    ),
  );
  Navigator.of(tester.element(find.byType(LoginPage))).push(
    MaterialPageRoute<void>(
      builder: (context) => RegisterPage(registrationApi: api),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fillRegistration(WidgetTester tester) async {
  for (final (index, value) in [
    (0, 'İpek Şen'),
    (1, ' synthetic@example.test '),
    (2, '  Sentetik 😀 şifre  '),
    (3, '  Sentetik 😀 şifre  '),
  ]) {
    final field = find.byType(TextFormField).at(index);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    await tester.pump();
  }
}

void expectNoProtectedScreens() {
  for (final type in [
    MainShell,
    HomePage,
    NutritionPage,
    ProgressPage,
    ProfilePage,
    NavigationBar,
  ]) {
    expect(find.byType(type, skipOffstage: false), findsNothing);
  }
}

// Controlled API completions exist only in tests; production always uses HTTP.
class PendingRegistrationApi extends RegistrationApi {
  final result = Completer<void>();
  int calls = 0;
  Map<String, String>? payload;

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    calls++;
    payload = {
      'displayName': displayName,
      'email': email,
      'password': password,
    };
    return result.future;
  }
}
