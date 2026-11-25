import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_validation.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_gate.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_widgets.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/forgot_password_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/auth/registration_api.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_page.dart';

import 'onboarding_test_support.dart';

void main() {
  test('registration accepts Unicode code point boundaries and whitespace', () {
    for (final password in [
      'a' * 8,
      'a' * 128,
      '😀' * 8,
      '😀' * 128,
      'a\u0301' * 4,
      ' ' * 8,
      '  şifre  ',
    ]) {
      expect(AuthValidation.registrationPassword(password), isNull);
    }
  });

  test('registration rejects passwords outside 8 to 128 code points', () {
    for (final password in ['a' * 7, '😀' * 7, ' ' * 7]) {
      expect(
        AuthValidation.registrationPassword(password),
        'Şifreniz en az 8 karakter olmalıdır.',
      );
    }
    for (final password in ['a' * 129, '😀' * 129]) {
      expect(
        AuthValidation.registrationPassword(password),
        'Şifreniz en fazla 128 karakter olabilir.',
      );
    }
    expect(AuthValidation.registrationPassword(null), 'Şifrenizi girin.');
    expect(AuthValidation.registrationPassword(''), 'Şifrenizi girin.');
  });

  test('registration rejects malformed UTF-16 as the backend does', () {
    for (final surrogate in [0xD800, 0xDC00]) {
      expect(
        AuthValidation.registrationPassword(
          'abcdefg${String.fromCharCode(surrogate)}',
        ),
        'Şifrenizde geçersiz bir karakter var.',
      );
    }
  });

  test('displayName requires a name without inventing name format rules', () {
    for (final name in [null, '', ' \t\n ']) {
      expect(AuthValidation.displayName(name), 'Adınızı ve soyadınızı girin.');
    }
    for (final name in ['İpek Şen', '李明', 'Cher', ' O’Neill ']) {
      expect(AuthValidation.displayName(name), isNull);
    }
    // Login authenticates existing credentials without reapplying signup rules.
    expect(AuthValidation.password('a'), isNull);
  });

  testWidgets('login validates empty and malformed inputs without navigating', (
    tester,
  ) async {
    await pumpAuth(tester, const LoginPage());
    expect(
      find.text('Giriş için e-posta adresinizin doğrulanmış olması gerekir.'),
      findsNothing,
    );
    await tapText(tester, 'Giriş yap');
    expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
    expect(find.text('Şifrenizi girin.'), findsOneWidget);

    await enterField(tester, 0, 'gecersiz-adres');
    await tapText(tester, 'Giriş yap');
    expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets(
    'password can be shown and hidden without modifying its contents',
    (tester) async {
      await pumpAuth(tester, const LoginPage());
      const password = '  Deneme parolası!  ';
      await enterField(tester, 1, password);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );

      await tester.tap(find.byTooltip('Göster: Şifre'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        password,
      );

      await tester.tap(find.byTooltip('Gizle: Şifre'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
    },
  );

  testWidgets(
    'keyboard login without a valid API response never creates a session',
    (tester) async {
      await pumpAuth(tester, const LoginPage());
      await enterField(tester, 0, 'ornek@example.com');
      await enterField(tester, 1, 'Deneme parolası!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Sunucu yanıtı doğrulanamadı. Oturum açılmadı; lütfen tekrar deneyin.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await enterField(tester, 0, 'baska@example.com');
      expect(
        find.text(
          'Sunucu yanıtı doğrulanamadı. Oturum açılmadı; lütfen tekrar deneyin.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'registration validates three fields and stays signed out after API rejection',
    (tester) async {
      await pumpAuth(tester, const RegisterPage());
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tapText(tester, 'Hesabımı oluştur');
      expect(find.text('Adınızı ve soyadınızı girin.'), findsOneWidget);
      expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi girin.'), findsOneWidget);
      await enterField(tester, 0, ' \t ');
      await enterField(tester, 1, 'gecersiz-adres');
      await enterField(tester, 2, 'kısa');
      await tapText(tester, 'Hesabımı oluştur');
      expect(find.text('Adınızı ve soyadınızı girin.'), findsOneWidget);
      expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
      expect(find.text('Şifreniz en az 8 karakter olmalıdır.'), findsOneWidget);
      await enterField(tester, 0, 'İpek Şen');
      await enterField(tester, 1, 'ornek@example.com');
      await enterField(tester, 2, 'Deneme parolası! ');
      await tapText(tester, 'Hesabımı oluştur');
      expect(find.text(registrationTestError), findsOneWidget);
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(NavigationBar, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('registration validates emoji lengths on keyboard submit', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    await enterField(tester, 0, 'İpek Şen');
    await enterField(tester, 1, 'ornek@example.test');
    for (final length in [7, 8, 128, 129]) {
      final password = '😀' * length;
      await enterField(tester, 2, password);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final expected = switch (length) {
        7 => 'Şifreniz en az 8 karakter olmalıdır.',
        129 => 'Şifreniz en fazla 128 karakter olabilir.',
        _ => registrationTestError,
      };
      expect(find.text(expected), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        password,
      );
      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('registration clears server feedback after editing', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    await enterField(tester, 0, 'İpek Şen');
    await enterField(tester, 1, 'ornek@example.test');
    await enterField(tester, 2, 'Sentetik şifre');
    await tapText(tester, 'Hesabımı oluştur');
    expect(find.text(registrationTestError), findsOneWidget);
    await enterField(tester, 0, 'İpek Şen Yılmaz');
    expect(find.text(registrationTestError), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration password visibility preserves the exact value', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    const password = '  Şifre😀e\u0301  ';
    await enterField(tester, 2, password);
    final toggle = find.byTooltip('Göster: Şifre');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isFalse,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      password,
    );
    await tester.tap(find.byTooltip('Gizle: Şifre'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password reset validates email before sending a request', (
    tester,
  ) async {
    await pumpAuth(tester, const ForgotPasswordPage());
    await tapText(tester, 'Sıfırlama kodu iste');
    expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
    await enterField(tester, 0, 'gecersiz');
    await tapText(tester, 'Sıfırlama kodu iste');
    expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
  });

  testWidgets(
    'registration shortcut restarts onboarding and other auth links still return',
    (tester) async {
      await pumpAuth(tester, const LoginPage());
      await enterField(tester, 1, 'Deneme parolası!');
      await tapText(tester, 'Hesabın yok mu? Kayıt ol');
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Merhaba, ben\nLimely!'), findsOneWidget);
      expect(find.byType(LoginPage, skipOffstage: false), findsNothing);
      expect(find.byType(RegisterPage), findsNothing);
      expect(find.text('E-posta doğrulama adımını incele'), findsNothing);
      await openLoginFromWelcome(tester);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('E-posta doğrulama hakkında'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );

      await tapText(tester, 'Şifremi unuttum');
      expect(find.byType(ForgotPasswordPage), findsOneWidget);
      await tapText(tester, 'Giriş ekranına dön');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('app back navigation never uncovers a debug dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.pumpAndSettle();
    await openLoginFromWelcome(tester);
    await tapText(tester, 'Hesabın yok mu? Kayıt ol');
    expect(find.byType(OnboardingPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Kimlik ekranları (önizleme)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all forms render externally supplied loading states without fake delays',
    (tester) async {
      for (final page in [
        const LoginPage(isLoading: true),
        const RegisterPage(isLoading: true),
        const ForgotPasswordPage(isLoading: true),
      ]) {
        await pumpAuth(tester, page);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Yükleniyor'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        for (final field in tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        )) {
          expect(field.enabled, isFalse);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('all forms display accessible external error states', (
    tester,
  ) async {
    const error = 'Örnek hata: işlem kullanılamıyor.';
    for (final page in [
      const LoginPage(errorMessage: error),
      const RegisterPage(errorMessage: error),
      const ForgotPasswordPage(errorMessage: error),
    ]) {
      await pumpAuth(tester, page);
      expect(find.text(error), findsOneWidget);
      final notice = find.descendant(
        of: find.byType(AuthErrorNotice),
        matching: find.byType(Semantics),
      );
      expect(tester.widget<Semantics>(notice).properties.liveRegion, isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  for (final brightness in Brightness.values) {
    for (final viewport in [
      (size: const Size(390, 844), scale: 1.0, keyboard: 0.0),
      (size: const Size(320, 640), scale: 2.0, keyboard: 220.0),
      (size: const Size(568, 320), scale: 1.5, keyboard: 120.0),
    ]) {
      testWidgets(
        'auth supports ${viewport.size}, ${viewport.scale}x, keyboard ${viewport.keyboard} in ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          tester.view.viewInsets = FakeViewPadding(bottom: viewport.keyboard);
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          for (final (page, title, action) in [
            (const LoginPage(), 'Yeniden merhaba!', 'Giriş yap'),
            (const RegisterPage(), 'Birlikte\nbaşlayalım.', 'Hesabımı oluştur'),
            (
              const ForgotPasswordPage(),
              'Şifrenizi mi unuttunuz?',
              'Sıfırlama kodu iste',
            ),
            (
              const EmailVerificationPage(
                email: 'sentetik.uzun.adres@example.test',
              ),
              'E-posta adresinizi doğrulayın',
              'Önceki ekrana dön',
            ),
          ]) {
            await pumpAuth(tester, page);
            await tester.pumpAndSettle();
            final heading = find.text(title);
            await Scrollable.ensureVisible(
              tester.element(heading),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(heading.hitTestable(), findsOneWidget);
            final button = find.text(action);
            await Scrollable.ensureVisible(
              tester.element(button),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
            expect(
              Theme.of(tester.element(heading)).brightness,
              page is LoginPage || page is RegisterPage
                  ? Brightness.light
                  : brightness,
            );
            if (page is RegisterPage) {
              for (final field in find.byType(TextFormField).evaluate()) {
                await Scrollable.ensureVisible(field, alignment: 0.5);
                await tester.pumpAndSettle();
                expect(
                  find.byWidget(field.widget).hitTestable(),
                  findsOneWidget,
                );
              }
              expect(find.byType(RegisterPage), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}

Future<void> pumpAuth(WidgetTester tester, Widget page) async {
  if (page is RegisterPage && page.registrationApi == null) {
    page = RegisterPage(
      isLoading: page.isLoading,
      errorMessage: page.errorMessage,
      registrationApi: RejectedRegistrationApi(),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      onGenerateRoute: AuthGate.route,
      home: page,
    ),
  );
}

const registrationTestError = 'Örnek kayıt servisi hatası.';

class RejectedRegistrationApi extends RegistrationApi {
  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    throw const RegistrationApiException(registrationTestError);
  }
}

Future<void> enterField(WidgetTester tester, int index, String value) async {
  final field = find.byType(TextFormField).at(index);
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String label) async {
  final target = find.text(label);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
