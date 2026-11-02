import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/auth/session_status_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

final refresh0 = 'A' * 43, refresh1 = 'B' * 43, refresh2 = 'C' * 43;
const unauthorized = LoginApiException('Oturum geçersiz.', unauthorized: true);
CurrentUserResponse verifiedUser({String role = 'client'}) =>
    CurrentUserResponse(
      id: '41111111-1111-4111-8111-111111111111',
      displayName: null,
      email: 'synthetic@example.test',
      role: role,
      isEmailVerified: true,
    );

void main() {
  testWidgets(
    'bootstrap persists rotation before me; only verified me opens Dashboard',
    (tester) async {
      final f = await Fixture.start(tester);
      expect(find.byType(SessionStatusPage), findsOneWidget);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      expect(f.api.renewals.length, 1);
      expect(f.store.value!.rotationPending, isTrue);
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pump();
      expect(f.store.value!.refreshToken, refresh1);
      expect(f.store.value!.rotationPending, isFalse);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      f.api.me.single.result.complete(verifiedUser());
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      expect(find.byType(MainShell), findsOneWidget);
      await f.close(tester);
    },
  );

  testWidgets(
    'restart uses the last persisted rotated token and verifies again',
    (tester) async {
      final first = await Fixture.start(tester);
      await first.finishRestore(tester);
      final store = first.store;
      await first.close(tester);
      final second = await Fixture.start(tester, store: store);
      expect(second.api.renewals.single.token, refresh1);
      expect(second.session.isAuthenticated, isFalse);
      await second.finishRestore(tester, token: refresh2);
      expect(second.session.isAuthenticated, isTrue);
      await second.close(tester);
    },
  );

  testWidgets(
    'initialize, refresh, resume and reentrant listeners share one refresh future',
    (tester) async {
      final f = await Fixture.start(tester);
      final one = f.session.refresh();
      final two = f.session.refreshUser();
      expect(identical(one, two), isTrue);
      var requested = false;
      f.session.addListener(() {
        if (!requested) {
          requested = true;
          unawaited(f.session.refresh());
        }
      });
      await f.finishRestore(tester);
      expect(f.api.renewals.length, 1);
      await f.close(tester);
    },
  );

  testWidgets(
    'proactive renewal preserves valid access but expiry blocks until new me succeeds',
    (tester) async {
      final f = await Fixture.start(tester, lead: const Duration(seconds: 30));
      await f.finishRestore(tester, lifetime: const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 90));
      expect(f.api.renewals.length, 2);
      expect(f.session.isAuthenticated, isTrue);
      f.api.renewals.last.result.complete(f.pair(refresh2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(f.session.isAuthenticated, isFalse);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      f.api.me.last.result.complete(verifiedUser());
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'me401 blocks access then refreshes once and verifies the new bearer',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      final checking = f.session.refreshUser();
      await tester.pump();
      f.api.me.last.onUnauthorized!();
      await tester.pump();
      expect(f.session.isAuthenticated, isFalse);
      f.api.me.last.result.completeError(unauthorized);
      await tester.pump();
      expect(f.api.renewals.length, 2);
      await f.finishRestore(tester, token: refresh2);
      await checking;
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'invalid refresh clears the secure credential without opening protected screens',
    (tester) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.completeError(unauthorized);
      await tester.pumpAndSettle();
      expect(f.store.value, isNull);
      expect(f.session.phase, SessionPhase.signedOut);
      expect(f.api.me, isEmpty);
      expect(find.byType(LoginPage), findsOneWidget);
      await f.close(tester);
    },
  );

  testWidgets('expired stored token is erased without a refresh request', (
    tester,
  ) async {
    final store = MemoryTokenStore(
      StoredRefreshToken(
        refresh0,
        tester.binding.clock.now().subtract(const Duration(seconds: 1)),
      ),
    );
    final f = await Fixture.start(tester, store: store);
    expect(f.store.value, isNull);
    expect(f.api.renewals, isEmpty);
    expect(f.session.phase, SessionPhase.signedOut);
    await f.close(tester);
  });

  testWidgets(
    'pending rotation after a crash is never replayed automatically',
    (tester) async {
      final store = MemoryTokenStore(
        StoredRefreshToken(
          refresh0,
          tester.binding.clock.now().add(const Duration(days: 30)),
          rotationPending: true,
        ),
      );
      final f = await Fixture.start(tester, store: store);
      expect(f.api.renewals, isEmpty);
      expect(f.session.phase, SessionPhase.reauthenticate);
      expect(find.text('Tekrar dene'), findsNothing);
      await f.session.refresh();
      expect(f.api.renewals, isEmpty);
      await tester.tap(find.text('Oturumu temizle ve girişe dön'));
      await tester.pumpAndSettle();
      expect(f.api.logouts, [refresh0]);
      expect(f.store.value, isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'proven pre-send network failure retains a ready token for manual retry',
    (tester) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.completeError(
        const LoginApiException.connection(),
      );
      await tester.pumpAndSettle();
      expect(f.store.value!.refreshToken, refresh0);
      expect(f.store.value!.rotationPending, isFalse);
      expect(f.session.phase, SessionPhase.retry);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pump();
      expect(f.api.renewals.last.token, refresh0);
      await f.finishRestore(tester);
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'ambiguous network loss retains a quarantined token across restart',
    (tester) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.completeError(
        const LoginApiException.connection(safeToRetry: false),
      );
      await tester.pumpAndSettle();
      expect(f.store.value!.rotationPending, isTrue);
      expect(f.session.phase, SessionPhase.reauthenticate);
      await f.session.refresh();
      expect(f.api.renewals.length, 1);
      final store = f.store;
      await f.close(tester);
      final restarted = await Fixture.start(tester, store: store);
      expect(restarted.api.renewals, isEmpty);
      expect(restarted.session.phase, SessionPhase.reauthenticate);
      await restarted.close(tester);
    },
  );

  testWidgets(
    'temporary me failure retains received rotation and retries only me',
    (tester) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pump();
      f.api.me.single.result.completeError(
        const LoginApiException.connection(),
      );
      await tester.pumpAndSettle();
      expect(f.store.value!.refreshToken, refresh1);
      expect(f.session.phase, SessionPhase.retry);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pump();
      expect(f.api.renewals.length, 1);
      expect(f.api.me.length, 2);
      f.api.me.last.result.complete(verifiedUser());
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'me401 after rotation clears credentials without a refresh loop',
    (tester) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pump();
      f.api.me.single.result.completeError(unauthorized);
      await tester.pumpAndSettle();
      expect(f.store.value, isNull);
      expect(f.api.renewals.length, 1);
      expect(f.session.isAuthenticated, isFalse);
      await f.close(tester);
    },
  );

  for (final invalid in ['same token', 'changed expiry', 'admin']) {
    testWidgets('invalid restoration cannot grant access: $invalid', (
      tester,
    ) async {
      final f = await Fixture.start(tester);
      f.api.renewals.single.result.complete(
        f.pair(
          invalid == 'same token' ? refresh0 : refresh1,
          refreshExpiry: invalid == 'changed expiry'
              ? f.expiry.add(const Duration(days: 1))
              : null,
        ),
      );
      await tester.pump();
      if (invalid == 'admin') {
        f.api.me.single.result.complete(verifiedUser(role: 'admin'));
      }
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isFalse);
      expect(f.store.value, isNull);
      await f.close(tester);
    });
  }

  testWidgets(
    'secure read failure keeps gate closed and can recover after unlock',
    (tester) async {
      final store = MemoryTokenStore(
        StoredRefreshToken(
          refresh0,
          tester.binding.clock.now().add(const Duration(days: 30)),
        ),
      )..failRead = true;
      final f = await Fixture.start(tester, store: store);
      expect(f.session.phase, SessionPhase.storageFailure);
      expect(f.api.renewals, isEmpty);
      store.failRead = false;
      unawaited(f.session.refresh());
      await tester.pump();
      await f.finishRestore(tester);
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets('a failed pending-marker write prevents any refresh request', (
    tester,
  ) async {
    final store = MemoryTokenStore(
      StoredRefreshToken(
        refresh0,
        tester.binding.clock.now().add(const Duration(days: 30)),
      ),
    )..failWrite = true;
    final f = await Fixture.start(tester, store: store);
    expect(f.api.renewals, isEmpty);
    expect(f.session.phase, SessionPhase.storageFailure);
    store.failWrite = false;
    unawaited(f.session.refresh());
    await tester.pump();
    await f.finishRestore(tester);
    expect(f.session.isAuthenticated, isTrue);
    await f.close(tester);
  });

  testWidgets(
    'failed rotated-token persistence retries the received token, never the consumed one',
    (tester) async {
      final f = await Fixture.start(tester);
      f.store.failWrite = true;
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pumpAndSettle();
      expect(f.session.phase, SessionPhase.storageFailure);
      expect(f.api.me, isEmpty);
      expect(f.store.value!.rotationPending, isTrue);
      f.store.failWrite = false;
      unawaited(f.session.refresh());
      await tester.pump();
      expect(f.api.renewals.length, 1);
      expect(f.store.value!.refreshToken, refresh1);
      f.api.me.single.result.complete(verifiedUser());
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'server logout failure still erases local memory and persisted credentials',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      f.api.logoutError = const LoginApiException.connection();
      await f.session.signOut();
      await tester.pumpAndSettle();
      expect(f.api.logouts, [refresh1]);
      expect(f.store.value, isNull);
      expect(f.session.user, isNull);
      expect(f.session.notice, contains('Sunucuda çıkış doğrulanamadı'));
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'failed local deletion fails closed and still attempts server revocation',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      f.store.failClear = true;
      await f.session.signOut();
      await tester.pumpAndSettle();
      expect(f.session.phase, SessionPhase.storageFailure);
      expect(f.session.user, isNull);
      expect(f.api.logouts, [refresh1]);
      expect(
        await f.session.signIn(
          email: 'synthetic@example.test',
          password: 'synthetic',
        ),
        isFalse,
      );
      f.store.failClear = false;
      await f.session.refresh();
      await tester.pumpAndSettle();
      expect(f.store.value, isNull);
      expect(f.session.phase, SessionPhase.signedOut);
      await f.close(tester);
    },
  );

  testWidgets(
    'logout during a refresh prevents a late response from restoring credentials',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.session.signOut();
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pumpAndSettle();
      expect(f.store.value, isNull);
      expect(f.api.logouts, [refresh0]);
      expect(f.api.me, isEmpty);
      expect(f.session.isAuthenticated, isFalse);
      await f.close(tester);
    },
  );

  testWidgets(
    'logout is serialized after an in-flight secure write and cannot resurrect a token',
    (tester) async {
      final f = await Fixture.start(tester);
      f.store.writeGate = Completer<void>();
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pump();
      final logout = f.session.signOut();
      f.store.writeGate!.complete();
      await logout;
      await tester.pumpAndSettle();
      expect(f.store.value, isNull);
      expect(f.store.operations.last, 'clear');
      expect(f.api.me, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    'disposal during refresh leaves a pending marker, never a stale replayable credential',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.close(tester);
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pump();
      expect(f.store.value!.rotationPending, isTrue);
      final next = await Fixture.start(tester, store: f.store);
      expect(next.api.renewals, isEmpty);
      expect(next.session.phase, SessionPhase.reauthenticate);
      await next.close(tester);
    },
  );

  testWidgets(
    'a stale me401 after a successful rotation cannot invalidate the new bearer',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      final oldRead = f.session.refreshUser();
      await tester.pump();
      final old = f.api.me.last;
      unawaited(f.session.refresh());
      await tester.pump();
      await f.finishRestore(tester, token: refresh2);
      old.onUnauthorized!();
      old.result.completeError(unauthorized);
      await oldRead;
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      expect(f.store.value!.refreshToken, refresh2);
      expect(f.api.renewals.length, 2);
      await f.close(tester);
    },
  );

  testWidgets(
    'logout cancels scheduled renewal and me work before either can send',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      final read = f.session.refreshUser();
      final renewal = f.session.refresh();
      final logout = f.session.signOut();
      await Future.wait([read, renewal, logout]);
      await tester.pumpAndSettle();
      expect(f.api.renewals.length, 1);
      expect(f.api.me.length, 1);
      expect(f.store.value, isNull);
      expect(f.session.phase, SessionPhase.signedOut);
      await f.close(tester);
    },
  );

  testWidgets(
    'terminal account validation failure cancels an overlapping rotation',
    (tester) async {
      final f = await Fixture.start(tester);
      await f.finishRestore(tester);
      final oldRead = f.session.refreshUser();
      await tester.pump();
      final oldMe = f.api.me.last;
      final renewal = f.session.refresh();
      await tester.pump();
      f.api.renewals.last.result.complete(f.pair(refresh2));
      await tester.pump();
      final newMe = f.api.me.last;
      oldMe.result.completeError(const LoginApiException.invalidResponse());
      await oldRead;
      newMe.result.complete(verifiedUser());
      await renewal;
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isFalse);
      expect(f.store.value, isNull);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'login persists its refresh credential before me and keeps access memory-only',
    (tester) async {
      final f = await Fixture.start(tester, store: MemoryTokenStore(null));
      final login = f.session.signIn(
        email: 'synthetic@example.test',
        password: 'synthetic',
      );
      await tester.pump();
      f.api.signins.single.complete(f.pair(refresh0));
      await tester.pump();
      expect(f.store.value!.refreshToken, refresh0);
      expect(f.store.value!.rotationPending, isFalse);
      expect(f.session.isAuthenticated, isFalse);
      f.api.me.single.result.complete(verifiedUser());
      expect(await login, isTrue);
      await tester.pumpAndSettle();
      expect(f.session.isAuthenticated, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'logout revokes a received credential even if persistence failed',
    (tester) async {
      final f = await Fixture.start(tester);
      f.store.failWrite = true;
      f.api.renewals.single.result.complete(f.pair(refresh1));
      await tester.pumpAndSettle();
      expect(f.session.phase, SessionPhase.storageFailure);
      await f.session.signOut();
      await tester.pumpAndSettle();
      expect(f.api.logouts, [refresh1]);
      expect(f.store.value, isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'terminal invalidation cannot be reentered by a renewal listener',
    (tester) async {
      final f = await Fixture.start(tester);
      var requested = false;
      f.session.addListener(() {
        if (!requested && f.session.phase == SessionPhase.working) {
          requested = true;
          unawaited(f.session.refresh());
        }
      });
      f.api.renewals.single.result.completeError(unauthorized);
      await tester.pumpAndSettle();
      expect(f.api.renewals.length, 1);
      expect(f.store.value, isNull);
      expect(f.session.phase, SessionPhase.signedOut);
      await f.close(tester);
    },
  );

  for (final pending in [false, true]) {
    testWidgets(
      'ending an unverified startup session returns to login from /register (pending=$pending)',
      (tester) async {
        tester.platformDispatcher.defaultRouteNameTestValue = '/register';
        addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
        final store = MemoryTokenStore(
          StoredRefreshToken(
            refresh0,
            tester.binding.clock.now().add(const Duration(days: 30)),
            rotationPending: pending,
          ),
        );
        final f = await Fixture.start(tester, store: store);
        if (pending) {
          await f.session.signOut();
        } else {
          f.api.renewals.single.result.completeError(unauthorized);
        }
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(RegisterPage, skipOffstage: false), findsNothing);
        expect(
          Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
          isFalse,
        );
        await f.close(tester);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'startup recovery uses ${brightness.name} theme on a small screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final f = await Fixture.start(tester);
        f.api.renewals.single.result.completeError(
          const LoginApiException.connection(),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(SessionStatusPage))).brightness,
          brightness,
        );
        await tester.ensureVisible(find.text('Tekrar dene'));
        await tester.pumpAndSettle();
        expect(find.text('Tekrar dene').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }
}

class Fixture {
  Fixture(this.session, this.api, this.store, this.expiry);
  final AuthSession session;
  final ControlledApi api;
  final MemoryTokenStore store;
  final DateTime expiry;
  static Future<Fixture> start(
    WidgetTester tester, {
    MemoryTokenStore? store,
    Duration lead = Duration.zero,
  }) async {
    final expiry =
        store?.value?.refreshTokenExpiresAt ??
        tester.binding.clock.now().add(const Duration(days: 30));
    final storage =
        store ?? MemoryTokenStore(StoredRefreshToken(refresh0, expiry));
    final api = ControlledApi();
    final session = AuthSession(
      api: api,
      store: storage,
      now: tester.binding.clock.now,
      refreshLeadTime: lead,
    );
    await tester.pumpWidget(SmartNutritionApp(session: session));
    await tester.pump();
    return Fixture(session, api, storage, expiry);
  }

  LoginUserResponse pair(
    String token, {
    Duration lifetime = const Duration(minutes: 15),
    DateTime? refreshExpiry,
  }) => LoginUserResponse(
    'header.${token[0]}payload.signature',
    session.now().add(lifetime),
    token,
    refreshExpiry ?? expiry,
  );
  Future<void> finishRestore(
    WidgetTester tester, {
    String? token,
    Duration lifetime = const Duration(minutes: 15),
  }) async {
    api.renewals.last.result.complete(
      pair(token ?? refresh1, lifetime: lifetime),
    );
    await tester.pump();
    api.me.last.result.complete(verifiedUser());
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  }
}

class MemoryTokenStore implements RefreshTokenStore {
  MemoryTokenStore(this.value);
  StoredRefreshToken? value;
  bool failRead = false, failWrite = false, failClear = false;
  Completer<void>? writeGate;
  final operations = <String>[];
  @override
  Future<StoredRefreshToken?> read() async {
    if (failRead) throw const SessionStorageException();
    return value;
  }

  @override
  Future<void> write(StoredRefreshToken record) async {
    if (failWrite) throw const SessionStorageException();
    await writeGate?.future;
    value = record;
    operations.add('write');
  }

  @override
  Future<void> clear() async {
    if (failClear) throw const SessionStorageException();
    value = null;
    operations.add('clear');
  }
}

class ControlledApi extends LoginApi {
  final signins = <Completer<LoginUserResponse>>[];
  @override
  Future<LoginUserResponse> login({
    required String email,
    required String password,
  }) {
    final result = Completer<LoginUserResponse>();
    signins.add(result);
    return result.future;
  }

  final renewals = <({String token, Completer<LoginUserResponse> result})>[];
  final me =
      <
        ({
          String token,
          Completer<CurrentUserResponse> result,
          void Function()? onUnauthorized,
        })
      >[];
  final logouts = <String>[];
  Object? logoutError;
  @override
  Future<LoginUserResponse> refresh(String refreshToken) {
    final result = Completer<LoginUserResponse>();
    renewals.add((token: refreshToken, result: result));
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

  @override
  Future<void> logout(String refreshToken) async {
    logouts.add(refreshToken);
    if (logoutError != null) throw logoutError!;
  }
}
