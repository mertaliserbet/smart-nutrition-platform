import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_widgets.dart';
import 'package:smart_nutrition_mobile/features/auth/forgot_password_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/password_reset_api.dart';
import 'water_test_support.dart';

class ResetTestApi extends PasswordResetApi {
  int requests = 0, resets = 0;
  String? email, code, password;
  Completer<void>? pending;
  PasswordResetApiException? failure;
  @override
  Future<void> request(String email) async {
    requests++;
    this.email = email;
    if (failure != null) throw failure!;
    await pending?.future;
  }

  @override
  Future<void> reset(String token, String password) async {
    resets++;
    code = token;
    this.password = password;
    if (failure != null) throw failure!;
    await pending?.future;
  }
}

void main() {
  late ResetTestApi api;
  setUp(() {
    api = ResetTestApi();
  });
  Future<void> open(WidgetTester tester, {WaterTestSession? session}) async {
    Widget page = MaterialApp(home: ForgotPasswordPage(api: api));
    if (session != null) page = AuthSessionScope(session: session, child: page);
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    final target = find.widgetWithText(
      label == 'Şifreyi yenile' || label == 'Sıfırlama kodu iste'
          ? FilledButton
          : TextButton,
      label,
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> fillReset(
    WidgetTester tester, {
    String? token,
    String password = ' Synthetic🔒123 ',
    String? confirmation,
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('reset-token')),
      token ?? 'A' * 43,
    );
    for (final (key, value) in [
      ('reset-password', password),
      ('reset-confirmation', confirmation ?? password),
    ]) {
      await tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
        value,
      );
    }
  }

  testWidgets(
    'request validates email and shows the same generic accepted state',
    (tester) async {
      await open(tester);
      await tap(tester, 'Sıfırlama kodu iste');
      expect(api.requests, 0);
      await tester.enterText(
        find.byKey(const ValueKey('reset-email')),
        'synthetic@example.test',
      );
      await tap(tester, 'Sıfırlama kodu iste');
      expect(api.requests, 1);
      expect(
        find.textContaining('Bu adres uygun bir hesaba aitse'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reset-token')), findsOneWidget);
      expect(api.resets, 0);
    },
  );
  testWidgets('malformed/link token, short password and mismatch never reset', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Sıfırlama kodum var');
    await fillReset(tester, token: 'https://example.test/reset?token=secret');
    await tap(tester, 'Şifreyi yenile');
    expect(api.resets, 0);
    await fillReset(tester, password: 'short');
    await tap(tester, 'Şifreyi yenile');
    expect(api.resets, 0);
    await fillReset(tester, confirmation: 'different');
    await tap(tester, 'Şifreyi yenile');
    expect(api.resets, 0);
  });
  testWidgets('success clears secrets, never signs in, and returns to login', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Sıfırlama kodum var');
    await fillReset(tester);
    await tap(tester, 'Şifreyi yenile');
    expect(api.resets, 1);
    expect(api.password, ' Synthetic🔒123 ');
    expect(find.text('Şifreniz yenilendi'), findsOneWidget);
    expect(find.byType(AuthPasswordField), findsNothing);
    await tap(tester, 'Giriş ekranına dön');
    expect(find.byType(LoginPage), findsOneWidget);
  });
  testWidgets(
    'pending mutation disables double submit and clears password fields',
    (tester) async {
      api.pending = Completer<void>();
      await open(tester);
      await tap(tester, 'Sıfırlama kodum var');
      await fillReset(tester);
      await tap(tester, 'Şifreyi yenile', settle: false);
      expect(api.resets, 1);
      expect(
        tester
            .widget<AuthSubmitButton>(find.byType(AuthSubmitButton))
            .isLoading,
        isTrue,
      );
      expect(find.text(' Synthetic🔒123 '), findsNothing);
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(api.resets, 1);
    },
  );
  testWidgets('expired/used errors do not claim success or retry', (
    tester,
  ) async {
    api.failure = const PasswordResetApiException(
      'Kod geçersiz, süresi dolmuş veya kullanılmış.',
    );
    await open(tester);
    await tap(tester, 'Sıfırlama kodum var');
    await fillReset(tester);
    await tap(tester, 'Şifreyi yenile');
    expect(api.resets, 1);
    expect(find.text('Şifreniz yenilendi'), findsNothing);
    expect(
      find.textContaining('süresi dolmuş veya kullanılmış'),
      findsOneWidget,
    );
    await tap(tester, 'Yeni kod iste');
    expect(find.byKey(const ValueKey('reset-email')), findsOneWidget);
    expect(api.requests, 0);
  });
  testWidgets(
    'account change clears a pending draft and ignores late success',
    (tester) async {
      final session = WaterTestSession();
      addTearDown(session.dispose);
      api.pending = Completer<void>();
      await open(tester, session: session);
      await tap(tester, 'Sıfırlama kodum var');
      await fillReset(tester);
      await tap(tester, 'Şifreyi yenile', settle: false);
      session.changeOwner();
      await tester.pump();
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Oturum değişti.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reset-token')), findsNothing);
      expect(find.text('Şifreniz yenilendi'), findsNothing);
    },
  );
}
