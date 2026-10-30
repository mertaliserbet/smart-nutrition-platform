import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_validation.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_widgets.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/forgot_password_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

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
      find.text(
        'Arayüz önizlemesi · Giriş, kayıt ve e-posta gönderimi yapılmaz.',
      ),
      findsOneWidget,
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

  testWidgets('valid login and keyboard submission never create a session', (
    tester,
  ) async {
    await pumpAuth(tester, const LoginPage());
    await enterField(tester, 0, 'ornek@example.com');
    await enterField(tester, 1, 'Deneme parolası!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.text('Giriş şu anda kullanıma açık değil. Oturum açılmadı.'),
      findsOneWidget,
    );
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await enterField(tester, 0, 'baska@example.com');
    expect(
      find.text('Giriş şu anda kullanıma açık değil. Oturum açılmadı.'),
      findsNothing,
    );
  });

  testWidgets(
    'registration validates confirmation and does not create an account',
    (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/register';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(const SmartNutritionApp());
      expect(find.byType(TextFormField), findsNWidgets(4));
      await tapText(tester, 'Kayıt ol');
      expect(find.text('Adınızı ve soyadınızı girin.'), findsOneWidget);
      expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi tekrar girin.'), findsOneWidget);

      await enterField(tester, 0, ' \t ');
      await enterField(tester, 1, 'gecersiz-adres');
      await tapText(tester, 'Kayıt ol');
      expect(find.text('Adınızı ve soyadınızı girin.'), findsOneWidget);
      expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);

      await enterField(tester, 0, 'İpek Şen');
      await enterField(tester, 1, 'ornek@example.com');
      await enterField(tester, 2, 'Deneme parolası! ');
      await enterField(tester, 3, 'Deneme parolası!');
      await tapText(tester, 'Kayıt ol');
      expect(find.text('Şifreler eşleşmiyor.'), findsOneWidget);
      await enterField(tester, 3, 'Deneme parolası! ');
      await tapText(tester, 'Kayıt ol');

      expect(
        find.text(
          'Hesap oluşturma şu anda kullanıma açık değil. Hesap oluşturulmadı.',
        ),
        findsOneWidget,
      );
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(NavigationBar, skipOffstage: false), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration validates emoji lengths on submit and keyboard done',
    (tester) async {
      await pumpAuth(tester, const RegisterPage());
      await enterField(tester, 0, 'İpek Şen');
      await enterField(tester, 1, 'ornek@example.test');
      for (final length in [7, 8, 128, 129]) {
        final password = '😀' * length;
        await enterField(tester, 2, password);
        await enterField(tester, 3, password);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final expected = switch (length) {
          7 => 'Şifreniz en az 8 karakter olmalıdır.',
          129 => 'Şifreniz en fazla 128 karakter olabilir.',
          _ =>
            'Hesap oluşturma şu anda kullanıma açık değil. Hesap oluşturulmadı.',
        };
        expect(find.text(expected), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(2))
              .controller!
              .text,
          password,
        );
        expect(find.byType(EmailVerificationPage), findsNothing);
        expect(find.byType(MainShell), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('registration refreshes matching and feedback after edits', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    await enterField(tester, 0, 'İpek Şen');
    await enterField(tester, 1, 'ornek@example.test');
    await enterField(tester, 2, 'Sentetik şifre');
    await enterField(tester, 3, 'Sentetik şifre');
    await enterField(tester, 2, 'Başka bir şifre');
    expect(find.text('Şifreler eşleşmiyor.'), findsOneWidget);
    await enterField(tester, 2, 'Sentetik şifre');
    expect(find.text('Şifreler eşleşmiyor.'), findsNothing);
    await tapText(tester, 'Kayıt ol');
    const feedback =
        'Hesap oluşturma şu anda kullanıma açık değil. Hesap oluşturulmadı.';
    expect(find.text(feedback), findsOneWidget);
    await enterField(tester, 0, 'İpek Şen Yılmaz');
    expect(find.text(feedback), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration password visibility preserves both exact values', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    const password = '  Şifre😀e\u0301  ';
    await enterField(tester, 2, password);
    await enterField(tester, 3, password);
    for (final (index, label) in [(2, 'Şifre'), (3, 'Şifre tekrarı')]) {
      final toggle = find.byTooltip('Göster: $label');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(index)).obscureText,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(index))
            .controller!
            .text,
        password,
      );
      await tester.tap(find.byTooltip('Gizle: $label'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(index)).obscureText,
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification preview keeps email context and clears passwords', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/register';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(const SmartNutritionApp());
    await enterField(tester, 0, 'İpek Şen');
    await enterField(tester, 1, ' ornek@example.test ');
    await enterField(tester, 2, 'Sentetik parola');
    await enterField(tester, 3, 'Sentetik parola');
    await tapText(tester, 'E-posta doğrulama adımını incele');
    expect(find.byType(EmailVerificationPage), findsOneWidget);
    expect(find.text('ornek@example.test'), findsOneWidget);
    expect(
      find.text(
        'Bu önizlemede doğrulama e-postası gönderilmez ve adres doğrulanmaz.',
      ),
      findsOneWidget,
    );
    expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    await tapText(tester, 'Önceki ekrana dön');
    expect(find.byType(RegisterPage), findsOneWidget);
    for (final index in [2, 3]) {
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(index))
            .controller!
            .text,
        isEmpty,
      );
    }
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'İpek Şen',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification preview omits an invalid email address', (
    tester,
  ) async {
    await pumpAuth(tester, const RegisterPage());
    await enterField(tester, 1, 'gecersiz-adres');
    await tapText(tester, 'E-posta doğrulama adımını incele');
    expect(find.byType(EmailVerificationPage), findsOneWidget);
    expect(find.text('E-posta adresi'), findsNothing);
    expect(find.text('gecersiz-adres'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KVKK information is accessible without consent or form changes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpAuth(tester, const RegisterPage());
      await enterField(tester, 0, 'İpek Şen');
      await enterField(tester, 1, 'ornek@example.test');
      await enterField(tester, 2, 'Sentetik parola');
      await enterField(tester, 3, 'Sentetik parola');
      final before = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller!.text)
          .toList();
      final link = find.bySemanticsLabel('KVKK aydınlatma metni');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      expect(link.hitTestable(), findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Aydınlatma metni henüz yayımlanmadı. Yayımlandığında bu alandan erişebilirsiniz.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Checkbox, skipOffstage: false), findsNothing);
      await tapText(tester, 'Kapat');
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller!.text)
            .toList(),
        before,
      );
      await tapText(tester, 'Kayıt ol');
      expect(
        find.text(
          'Hesap oluşturma şu anda kullanıma açık değil. Hesap oluşturulmadı.',
        ),
        findsOneWidget,
      );
      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'password reset validates email without claiming an email was sent',
    (tester) async {
      await pumpAuth(tester, const ForgotPasswordPage());
      await tapText(tester, 'Sıfırlama bağlantısı iste');
      expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
      await enterField(tester, 0, 'gecersiz');
      await tapText(tester, 'Sıfırlama bağlantısı iste');
      expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
      await enterField(tester, 0, 'ornek@example.com');
      await tapText(tester, 'Sıfırlama bağlantısı iste');

      expect(
        find.text(
          'E-posta gönderimi şu anda kullanıma açık değil. Sıfırlama bağlantısı gönderilmedi.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ForgotPasswordPage), findsOneWidget);
    },
  );

  testWidgets(
    'auth screens navigate and return without simulating registration',
    (tester) async {
      await pumpAuth(tester, const LoginPage());
      await enterField(tester, 1, 'Deneme parolası!');
      await tapText(tester, 'Hesabınız yok mu? Kayıt ol');
      expect(find.byType(RegisterPage), findsOneWidget);
      await tapText(tester, 'E-posta doğrulama adımını incele');
      expect(find.byType(EmailVerificationPage), findsOneWidget);
      expect(
        find.text(
          'Bu önizlemede doğrulama e-postası gönderilmez ve adres doğrulanmaz.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Önceki ekrana dön');
      expect(find.byType(RegisterPage), findsOneWidget);
      await tapText(tester, 'Zaten hesabınız var mı? Girişe dön');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );

      await tapText(tester, 'Şifremi unuttum');
      expect(find.byType(ForgotPasswordPage), findsOneWidget);
      await tapText(tester, 'Giriş ekranına dön');
      expect(find.byType(LoginPage), findsOneWidget);
      await tapText(tester, 'E-posta doğrulama hakkında');
      expect(find.byType(EmailVerificationPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('app back navigation never uncovers a debug dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.pumpAndSettle();
    await tapText(tester, 'Hesabınız yok mu? Kayıt ol');
    expect(find.byType(RegisterPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
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
            (const LoginPage(), 'Tekrar hoş geldiniz', 'Giriş yap'),
            (const RegisterPage(), 'Size özel bir başlangıç', 'Kayıt ol'),
            (
              const ForgotPasswordPage(),
              'Şifrenizi mi unuttunuz?',
              'Sıfırlama bağlantısı iste',
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
              Theme.of(tester.element(find.byType(AuthPageLayout))).brightness,
              brightness,
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
              await tapText(tester, 'KVKK aydınlatma metni');
              expect(find.byType(BottomSheet), findsOneWidget);
              await tapText(tester, 'Kapat');
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
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, home: page),
  );
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
