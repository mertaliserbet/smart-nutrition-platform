import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';

const token = 'syntheticHeader.syntheticPayload.syntheticSignature';
const invalidLogin = LoginApiException(
  'Giriş yapılamadı. E-posta ve şifrenizi kontrol edip e-posta doğrulamasını tamamlayın.',
  unauthorized: true,
);
CurrentUserResponse user({String role = 'client', bool verified = true}) =>
    CurrentUserResponse(
      id: '41111111-1111-4111-8111-111111111111',
      displayName: 'Sentetik Kullanıcı',
      email: 'synthetic@example.test',
      role: role,
      isEmailVerified: verified,
    );
final submitButton = find.widgetWithText(FilledButton, 'Giriş yap');

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('gate opens only after login AND me in ${brightness.name}', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final (session, api) = await setup(tester);
      await fillAndSubmit(tester);
      // Calling a previously captured callback cannot bypass the pending guard.
      expect(api.logins.length, 1);
      expect(api.logins.single.email, 'synthetic@example.test');
      expect(api.logins.single.password, '  Şifre😀  ');
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
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
      expect(find.byType(LoginPage), findsOneWidget);
      api.logins.single.result.complete(
        LoginUserResponse(
          token,
          session.now().add(const Duration(minutes: 15)),
        ),
      );
      await tester.pump();
      expect(api.me.length, 1);
      expect(api.me.single.token, token);
      expect(session.isAuthenticated, isFalse);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      api.me.single.result.complete(user());
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isTrue);
      expect(find.byType(LoginPage, skipOffstage: false), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(MainShell))).canPop(),
        isFalse,
      );
      expect(
        Theme.of(tester.element(find.byType(MainShell))).brightness,
        brightness,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }

  testWidgets('verified dietitian can sign in without gaining Admin access', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    await fillAndSubmit(tester);
    api.logins.single.result.complete(
      LoginUserResponse(token, session.now().add(const Duration(minutes: 15))),
    );
    await tester.pump();
    api.me.single.result.complete(user(role: 'dietitian'));
    await tester.pumpAndSettle();
    expect(session.isAuthenticated, isTrue);
    expect(session.user!.role, 'dietitian');
    expect(find.byType(MainShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('invalid form sends no request, including keyboard submission', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    tester.widget<FilledButton>(submitButton).onPressed!();
    await tester.pumpAndSettle();
    expect(api.logins, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, 'wrong');
    await tester.enterText(find.byType(TextFormField).last, 'a');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.logins, isEmpty);
    expect(session.isAuthenticated, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  for (final failure in [
    invalidLogin,
    const LoginApiException.connection(),
    const LoginApiException('Giriş servisi şu anda kullanılamıyor.'),
    const LoginApiException('Çok fazla giriş denemesi yapıldı.'),
  ]) {
    testWidgets('login error remains signed out: ${failure.message}', (
      tester,
    ) async {
      final (session, api) = await setup(tester);
      await fillAndSubmit(tester);
      api.logins.single.result.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.text(failure.message), findsOneWidget);
      expect(session.isAuthenticated, isFalse);
      expect(session.user, isNull);
      expect(api.me, isEmpty);
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }

  for (final failure in [
    invalidLogin,
    const LoginApiException.connection(),
    const LoginApiException.invalidResponse(),
  ]) {
    testWidgets(
      'login 200 cannot grant access if me fails: ${failure.message}',
      (tester) async {
        final (session, api) = await setup(tester);
        await fillAndSubmit(tester);
        api.logins.single.result.complete(
          LoginUserResponse(
            token,
            session.now().add(const Duration(minutes: 15)),
          ),
        );
        await tester.pump();
        api.me.single.result.completeError(failure);
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsOneWidget);
        expect(session.isAuthenticated, isFalse);
        expect(session.user, isNull);
        expect(find.byType(MainShell, skipOffstage: false), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
      },
    );
  }

  for (final invalidUser in [
    user(role: 'admin'),
    user(verified: false),
    user(role: 'unknown'),
  ]) {
    testWidgets(
      'session itself rejects ${invalidUser.role}, verified=${invalidUser.isEmailVerified}',
      (tester) async {
        final (session, api) = await setup(tester);
        await fillAndSubmit(tester);
        api.logins.single.result.complete(
          LoginUserResponse(
            token,
            session.now().add(const Duration(minutes: 15)),
          ),
        );
        await tester.pump();
        api.me.single.result.complete(invalidUser);
        await tester.pumpAndSettle();
        expect(session.isAuthenticated, isFalse);
        expect(find.byType(MainShell, skipOffstage: false), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
      },
    );
  }

  for (final expireWhileMePending in [false, true]) {
    testWidgets(
      'expired token cannot open gate; mePending=$expireWhileMePending',
      (tester) async {
        final (session, api) = await setup(tester);
        await fillAndSubmit(tester);
        api.logins.single.result.complete(
          LoginUserResponse(
            token,
            session.now().add(Duration(seconds: expireWhileMePending ? 1 : -1)),
          ),
        );
        await tester.pump();
        if (expireWhileMePending) {
          await tester.pump(const Duration(seconds: 2));
          api.me.single.result.complete(user());
        } else {
          expect(api.me, isEmpty);
        }
        await tester.pumpAndSettle();
        expect(session.isAuthenticated, isFalse);
        expect(find.byType(MainShell, skipOffstage: false), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
      },
    );
  }

  testWidgets(
    'logout erases nested routes, prevents back/direct-route access and never revives a late request',
    (tester) async {
      final (session, api) = await setup(tester);
      await authenticate(tester, session, api);
      final navigator = Navigator.of(tester.element(find.byType(MainShell)));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const ManualMealLogPage()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ManualMealLogPage), findsOneWidget);
      final refresh = session.refreshUser();
      await tester.pump();
      session.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(find.byType(ManualMealLogPage, skipOffstage: false), findsNothing);
      expect(session.user, isNull);
      api.me.last.result.complete(user());
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (final path in [
        '/dashboard',
        '/nutrition',
        '/progress',
        '/profile',
      ]) {
        Navigator.of(tester.element(find.byType(LoginPage))).pushNamed(
          path,
          arguments: {'accessToken': token, 'isAuthenticated': true},
        );
        await tester.pumpAndSettle();
        expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      }
      expect(session.isAuthenticated, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    'invalid account response closes an already authenticated session',
    (tester) async {
      final (session, api) = await setup(tester);
      await authenticate(tester, session, api);
      final refresh = session.refreshUser();
      await tester.pump();
      api.me.last.result.completeError(
        const LoginApiException.invalidResponse(),
      );
      await expectLater(refresh, throwsA(isA<LoginApiException>()));
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isFalse);
      expect(session.user, isNull);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    'transient refresh failure neither renews nor invents a session',
    (tester) async {
      final (session, api) = await setup(tester);
      await authenticate(
        tester,
        session,
        api,
        lifetime: const Duration(seconds: 10),
      );
      final refresh = session.refreshUser();
      await tester.pump();
      api.me.last.result.completeError(const LoginApiException.connection());
      await expectLater(refresh, throwsA(isA<LoginApiException>()));
      expect(session.isAuthenticated, isTrue);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isFalse);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets('logout button clears the in-memory session', (tester) async {
    final (session, api) = await setup(tester);
    await authenticate(tester, session, api);
    await tester.tap(find.byTooltip('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(session.isAuthenticated, isFalse);
    expect(session.user, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('exact expiry clears gate and nested protected history', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    await authenticate(
      tester,
      session,
      api,
      lifetime: const Duration(seconds: 10),
    );
    Navigator.of(tester.element(find.byType(MainShell))).pushNamed('/profile');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(session.isAuthenticated, isFalse);
    expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    expect(
      find.text('Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
      findsOneWidget,
    );
    expect(
      Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets(
    'resume checks wall-clock expiry before making another API request',
    (tester) async {
      var wallTime = DateTime.utc(2026, 10, 31);
      final api = PendingLoginApi();
      final session = AuthSession(api: api, now: () => wallTime);
      await tester.pumpWidget(SmartNutritionApp(session: session));
      await authenticate(tester, session, api);
      wallTime = wallTime.add(const Duration(minutes: 16));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isFalse);
      expect(api.me.length, 1);
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    '401 on resume clears every protected route before body completion',
    (tester) async {
      final (session, api) = await setup(tester);
      await authenticate(tester, session, api);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.me.length, 2);
      api.me.last.onUnauthorized!();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(
        find.text('Oturumunuz geçersiz. Lütfen tekrar giriş yapın.'),
        findsOneWidget,
      );
      api.me.last.result.completeError(invalidLogin);
      await tester.pumpAndSettle();
      expect(session.isAuthenticated, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets('late login after cancellation cannot recreate a session', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    await fillAndSubmit(tester);
    session.signOut();
    api.logins.single.result.complete(
      LoginUserResponse(token, session.now().add(const Duration(minutes: 15))),
    );
    await tester.pumpAndSettle();
    expect(api.me, isEmpty);
    expect(session.isAuthenticated, isFalse);
    expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('a previous session 401 cannot log out a newer session', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    await authenticate(tester, session, api);
    final oldRefresh = session.refreshUser();
    await tester.pump();
    final oldRequest = api.me.last;
    session.signOut();
    await tester.pumpAndSettle();
    await authenticate(tester, session, api);
    oldRequest.onUnauthorized!();
    oldRequest.result.completeError(invalidLogin);
    await expectLater(oldRefresh, throwsA(isA<LoginApiException>()));
    await tester.pumpAndSettle();
    expect(session.isAuthenticated, isTrue);
    expect(find.byType(MainShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('new application session starts signed out after restart', (
    tester,
  ) async {
    final (session, api) = await setup(tester);
    await authenticate(tester, session, api);
    await tester.pumpWidget(const SmartNutritionApp(key: ValueKey('restart')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    session.dispose();
  });
}

Future<(AuthSession, PendingLoginApi)> setup(WidgetTester tester) async {
  final api = PendingLoginApi();
  final session = AuthSession(api: api, now: tester.binding.clock.now);
  await tester.pumpWidget(SmartNutritionApp(session: session));
  await tester.pumpAndSettle();
  return (session, api);
}

Future<void> fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).first,
    ' synthetic@example.test ',
  );
  await tester.enterText(find.byType(TextFormField).last, '  Şifre😀  ');
  await tester.ensureVisible(submitButton);
  await tester.pumpAndSettle();
  final submit = tester.widget<FilledButton>(submitButton).onPressed!;
  await tester.tap(submitButton);
  submit();
  await tester.pump();
}

Future<void> authenticate(
  WidgetTester tester,
  AuthSession session,
  PendingLoginApi api, {
  Duration lifetime = const Duration(minutes: 15),
}) async {
  await fillAndSubmit(tester);
  api.logins.last.result.complete(
    LoginUserResponse(token, session.now().add(lifetime)),
  );
  await tester.pump();
  api.me.last.result.complete(user());
  await tester.pumpAndSettle();
}

class PendingLoginApi extends LoginApi {
  final logins =
      <
        ({String email, String password, Completer<LoginUserResponse> result})
      >[];
  final me =
      <
        ({
          String token,
          Completer<CurrentUserResponse> result,
          void Function()? onUnauthorized,
        })
      >[];
  @override
  Future<LoginUserResponse> login({
    required String email,
    required String password,
  }) {
    final result = Completer<LoginUserResponse>();
    logins.add((email: email, password: password, result: result));
    return result.future;
  }

  @override
  Future<CurrentUserResponse> currentUser(
    String accessToken, {
    void Function()? onUnauthorized,
  }) {
    final result = Completer<CurrentUserResponse>();
    me.add((
      token: accessToken,
      result: result,
      onUnauthorized: onUnauthorized,
    ));
    return result.future;
  }
}
