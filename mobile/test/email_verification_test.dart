import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_gate.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_api.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

const email = 'synthetic@example.test';
final token = 'A' * 43;
final verifyButton = find.widgetWithText(FilledButton, 'E-postamı doğrula');
final resendButton = find.byType(OutlinedButton);

void main() {
  testWidgets(
    'registration email is visible; initial cooldown sends no request',
    (tester) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api, registered: true);
      expect(find.text(email), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.obscureText, isTrue);
      expect(fields.first.enableSuggestions, isFalse);
      expect(fields.last.readOnly, isTrue);
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      expect(api.verifyCalls + api.resendCalls, 0);
      await tester.pump(const Duration(seconds: 61));
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNotNull);
      expect(api.verifyCalls + api.resendCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('invalid or link-shaped input never reaches the API', (
    tester,
  ) async {
    final api = PendingVerificationApi();
    await pumpPage(tester, api);
    for (final input in [
      '',
      'short',
      'https://example.test/?token=$token',
      '${'A' * 42}!',
    ]) {
      await tester.enterText(find.byType(TextFormField).first, input);
      tester.widget<FilledButton>(verifyButton).onPressed!();
      await tester.pumpAndSettle();
      expect(find.textContaining('43 karakterlik'), findsOneWidget);
    }
    expect(api.verifyCalls, 0);
    expect(find.text('E-posta doğrulaması tamamlandı.'), findsNothing);
  });

  testWidgets(
    'verification waits, blocks duplicate requests and returns to a clean login stack',
    (tester) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      await tester.enterText(find.byType(TextFormField).first, ' $token ');
      await tester.ensureVisible(verifyButton);
      await tester.pumpAndSettle();
      final submit = tester.widget<FilledButton>(verifyButton).onPressed!;
      await tester.tap(verifyButton);
      submit();
      await tester.pump();
      expect(api.verifyCalls, 1);
      expect(api.submittedToken, token);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('E-posta doğrulaması tamamlandı.'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(EmailVerificationPage), findsOneWidget);
      api.verifyResult.complete();
      await tester.pumpAndSettle();
      expect(find.text('E-posta doğrulaması tamamlandı.'), findsOneWidget);
      expect(find.textContaining('Oturum açılmadı.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      final back = find.text('Giriş ekranına dön');
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.byType(EmailVerificationPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
        isFalse,
      );
      Navigator.of(
        tester.element(find.byType(LoginPage)),
      ).pushNamed('/dashboard');
      await tester.pumpAndSettle();
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(find.byType(LoginPage), findsWidgets);
    },
  );

  for (final failure in [
    const EmailVerificationApiException(
      'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış.',
    ),
    const EmailVerificationApiException.connection(),
    const EmailVerificationApiException(
      'Doğrulama servisi şu anda kullanılamıyor.',
    ),
  ]) {
    testWidgets('verification error stays signed out: ${failure.message}', (
      tester,
    ) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      await tester.enterText(find.byType(TextFormField).first, token);
      tester.widget<FilledButton>(verifyButton).onPressed!();
      await tester.pump();
      api.verifyResult.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('E-posta doğrulaması tamamlandı.'), findsNothing);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(tester.widget<FilledButton>(verifyButton).onPressed, isNotNull);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
    });
  }

  testWidgets(
    'resend validates email, blocks concurrent actions and treats 202 generically',
    (tester) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      await tester.enterText(find.byType(TextFormField).last, 'invalid');
      tester.widget<OutlinedButton>(resendButton).onPressed!();
      await tester.pumpAndSettle();
      expect(api.resendCalls, 0);
      await tester.enterText(find.byType(TextFormField).last, ' $email ');
      final resend = tester.widget<OutlinedButton>(resendButton).onPressed!;
      resend();
      resend();
      await tester.pump();
      expect(api.resendCalls, 1);
      expect(api.submittedEmail, email);
      expect(tester.widget<FilledButton>(verifyButton).onPressed, isNull);
      expect(find.textContaining('Hesap doğrulamaya uygunsa'), findsNothing);
      api.resendResult.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Hesap doğrulamaya uygunsa'), findsOneWidget);
      expect(find.text('Tekrar istemek için 60 sn bekleyin.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      resend();
      expect(api.resendCalls, 1);
      await tester.pump(const Duration(seconds: 59));
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNotNull);
      expect(find.text('E-posta doğrulaması tamamlandı.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '429 Retry-After cooldown also blocks verification-triggered resend',
    (tester) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      await tester.enterText(find.byType(TextFormField).first, token);
      tester.widget<FilledButton>(verifyButton).onPressed!();
      await tester.pump();
      api.verifyResult.completeError(
        const EmailVerificationApiException(
          'Çok fazla istek yapıldı.',
          retryAfter: Duration(seconds: 180),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Çok fazla istek yapıldı.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      await tester.pump(const Duration(seconds: 61));
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNull);
      await tester.pump(const Duration(seconds: 120));
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNotNull);
      expect(api.resendCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final failure in [
    const EmailVerificationApiException.connection(),
    const EmailVerificationApiException(
      'Doğrulama servisi şu anda kullanılamıyor.',
    ),
  ]) {
    testWidgets('resend failure shows no acknowledgement: ${failure.message}', (
      tester,
    ) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      tester.widget<OutlinedButton>(resendButton).onPressed!();
      await tester.pump();
      api.resendResult.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.text(failure.message), findsOneWidget);
      expect(find.textContaining('Hesap doğrulamaya uygunsa'), findsNothing);
      expect(tester.widget<OutlinedButton>(resendButton).onPressed, isNotNull);
    });
  }

  testWidgets(
    'a response after disposal neither navigates nor updates disposed state',
    (tester) async {
      final api = PendingVerificationApi();
      await pumpPage(tester, api);
      await tester.enterText(find.byType(TextFormField).first, token);
      tester.widget<FilledButton>(verifyButton).onPressed!();
      await tester.pumpWidget(const SizedBox.shrink());
      api.verifyResult.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    for (final size in [const Size(320, 640), const Size(568, 320)]) {
      testWidgets(
        'controls remain reachable in ${theme.brightness.name} at $size and large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpPage(
            tester,
            PendingVerificationApi(),
            theme: theme,
            textScale: 2,
          );
          for (final control in [
            verifyButton,
            resendButton,
            find.text('Önceki ekrana dön'),
          ]) {
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            expect(control.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  PendingVerificationApi api, {
  bool registered = false,
  ThemeData? theme,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      onGenerateRoute: AuthGate.route,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: EmailVerificationPage(
        email: email,
        registrationCompleted: registered,
        verificationApi: api,
        now: tester.binding.clock.now,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class PendingVerificationApi extends EmailVerificationApi {
  final verifyResult = Completer<void>();
  final resendResult = Completer<void>();
  int verifyCalls = 0;
  int resendCalls = 0;
  String? submittedToken;
  String? submittedEmail;

  @override
  Future<void> verifyEmail(String token) {
    verifyCalls++;
    submittedToken = token;
    return verifyResult.future;
  }

  @override
  Future<void> resendVerification(String email) {
    resendCalls++;
    submittedEmail = email;
    return resendResult.future;
  }
}
