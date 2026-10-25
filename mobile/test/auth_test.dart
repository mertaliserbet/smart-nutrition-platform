import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_widgets.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/forgot_password_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

void main() {
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
      await pumpAuth(tester, const RegisterPage());
      await tapText(tester, 'Kayıt ol');
      expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi tekrar girin.'), findsOneWidget);

      await enterField(tester, 0, 'ornek@example.com');
      await enterField(tester, 1, 'Deneme parolası! ');
      await enterField(tester, 2, 'Deneme parolası!');
      await tapText(tester, 'Kayıt ol');
      expect(find.text('Şifreler eşleşmiyor.'), findsOneWidget);
      await enterField(tester, 2, 'Deneme parolası! ');
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
    },
  );

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

  testWidgets('debug dashboard stays accessible and retains the selected tab', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profil'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kimlik ekranları (önizleme)'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MainShell), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
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
              const EmailVerificationPage(),
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
