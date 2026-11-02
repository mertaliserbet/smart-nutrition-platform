import 'dart:async';
import 'package:flutter/widgets.dart';

import 'login_api.dart';
import 'refresh_token_store.dart';

enum SessionPhase {
  checking,
  signedOut,
  working,
  authenticated,
  retry,
  reauthenticate,
  storageFailure,
}

/// Only a server-verified /me opens the gate; persisted refresh is never proof of login.
class AuthSession extends ChangeNotifier {
  AuthSession({
    LoginApi? api,
    RefreshTokenStore? store,
    this.now = DateTime.now,
    this.refreshLeadTime = const Duration(seconds: 30),
  }) : _api = api ?? LoginApi(),
       _store = store ?? SecureRefreshTokenStore();
  final LoginApi _api;
  final RefreshTokenStore _store;
  final DateTime Function() now;
  final Duration refreshLeadTime;
  String? _accessToken;
  DateTime? _expiresAt;
  CurrentUserResponse? _user;
  StoredRefreshToken? _record;
  LoginUserResponse? _candidate;
  Timer? _renewTimer;
  Timer? _expiryTimer;
  Future<void> _storageTail = Future.value();
  Future<void>? _renewal;
  Future<void>? _meRequest;
  Future<void>? _initialization;
  int _generation = 0;
  int _accessRevision = 0;
  bool _disposed = false;
  bool _working = false;
  bool _interactiveLogin = false;
  bool _signingOut = false;
  bool _cleanupRequired = false;
  bool _sessionEnded = false;
  SessionPhase _phase = SessionPhase.checking;
  String? _notice;

  SessionPhase get phase => _phase;
  bool get hasEndedSession => _sessionEnded;
  bool get isAuthenticated =>
      _phase == SessionPhase.authenticated &&
      _user != null &&
      _accessToken != null &&
      _expiresAt!.isAfter(now());
  bool get isBusy => _working;
  bool get isBlocking =>
      !isAuthenticated &&
      _phase != SessionPhase.signedOut &&
      !(_interactiveLogin && _phase == SessionPhase.working);
  bool get canRetry => !_working && _phase != SessionPhase.reauthenticate;
  CurrentUserResponse? get user => isAuthenticated ? _user : null;
  String? get notice => _notice;

  Future<T> _storage<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= refresh();

  Future<bool> signIn({required String email, required String password}) async {
    if (_phase == SessionPhase.checking) await initialize();
    if (_working || _disposed || _phase != SessionPhase.signedOut) return false;
    final generation = ++_generation;
    _working = true;
    _interactiveLogin = true;
    _phase = SessionPhase.working;
    _notice = null;
    _notify();
    try {
      final pair = await _api.login(email: email, password: password);
      if (!_current(generation)) return false;
      await _accept(pair, generation);
      return _current(generation) && isAuthenticated;
    } catch (error) {
      if (!_current(generation)) return false;
      await _failure(error, generation);
      rethrow;
    } finally {
      if (_current(generation)) {
        _working = false;
        _interactiveLogin = false;
        _notify();
      }
    }
  }

  /// A single future covers bootstrap, proactive renewal, resume and 401 recovery.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_renewal != null) return _renewal!;
    if (_interactiveLogin || _signingOut) return Future.value();
    final generation = _generation;
    final operation = Future<void>.microtask(() => _refresh(generation));
    _renewal = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_renewal, operation)) _renewal = null;
      }),
    );
    return operation;
  }

  Future<void> _refresh(int generation) async {
    if (!_current(generation)) return;
    _working = true;
    if (!isAuthenticated) _phase = SessionPhase.working;
    _notice = null;
    _notify();
    var requestStarted = false;
    try {
      if (_cleanupRequired) {
        await _forget(
          generation,
          'Oturum temizlendi. Tekrar giriş yapabilirsiniz.',
        );
        return;
      }
      // A received pair is persisted before /me. A failed /me read can retry
      // without consuming another refresh token.
      if (_candidate != null) {
        final pair = _candidate!;
        await _savePair(pair, generation);
        if (!_current(generation)) return;
        if (pair.expiresAt.isAfter(now())) {
          await _verify(pair, generation);
          return;
        }
        _candidate = null;
      }
      if (_record == null) {
        final stored = await _storage(() => _store.read());
        if (!_current(generation)) return;
        _record = stored;
      }
      if (!_current(generation)) return;
      final record = _record;
      if (record == null) {
        _phase = SessionPhase.signedOut;
        return;
      }
      if (!record.refreshTokenExpiresAt.isAfter(now())) {
        await _forget(
          generation,
          'Oturum süreniz doldu. Lütfen tekrar giriş yapın.',
        );
        return;
      }
      if (record.rotationPending) {
        _phase = SessionPhase.reauthenticate;
        _notice =
            'Önceki yenilemenin sonucu doğrulanamadı. Eski kodu tekrar kullanmadan oturumu temizleyip giriş yapın.';
        return;
      }
      await _storage(() async {
        if (_current(generation)) await _store.write(record.pending(true));
      });
      if (!_current(generation)) return;
      _record = record.pending(true);
      requestStarted = true;
      final pair = await _api.refresh(record.refreshToken);
      if (!_current(generation)) return;
      if (pair.refreshToken == record.refreshToken ||
          !pair.refreshTokenExpiresAt.isAtSameMomentAs(
            record.refreshTokenExpiresAt,
          )) {
        throw const LoginApiException.invalidResponse();
      }
      await _accept(pair, generation);
    } catch (error) {
      if (!_current(generation)) return;
      if (requestStarted &&
          _candidate == null &&
          error is LoginApiException &&
          error.safeToRetry &&
          !error.unauthorized) {
        // Proven pre-send failure / explicit pre-processing rejection: no rotation.
        final ready = _record!.pending(false);
        try {
          await _storage(() async {
            if (_current(generation)) await _store.write(ready);
          });
          if (!_current(generation)) return;
          _record = ready;
        } catch (_) {
          /* Keep the durable pending marker; never replay blindly. */
        }
      }
      await _failure(error, generation);
    } finally {
      if (_current(generation)) {
        _working = false;
        _notify();
      }
    }
  }

  Future<void> _accept(LoginUserResponse pair, int generation) async {
    if (!pair.expiresAt.isAfter(now()) ||
        !pair.refreshTokenExpiresAt.isAfter(now())) {
      throw const LoginApiException.invalidResponse();
    }
    _candidate = pair;
    await _savePair(pair, generation);
    if (_current(generation)) await _verify(pair, generation);
  }

  Future<void> _savePair(LoginUserResponse pair, int generation) async {
    final record = StoredRefreshToken(
      pair.refreshToken,
      pair.refreshTokenExpiresAt,
    );
    await _storage(() async {
      if (_current(generation)) await _store.write(record);
    });
    if (_current(generation)) _record = record;
  }

  Future<void> _verify(LoginUserResponse pair, int generation) async {
    final user = await _api.currentUser(pair.accessToken);
    if (!_current(generation)) return;
    if (!pair.expiresAt.isAfter(now()) ||
        !user.isEmailVerified ||
        !const ['client', 'dietitian'].contains(user.role)) {
      throw const LoginApiException.invalidResponse();
    }
    _accessToken = pair.accessToken;
    _expiresAt = pair.expiresAt;
    _user = user;
    ++_accessRevision;
    _candidate = null;
    _phase = SessionPhase.authenticated;
    _notice = null;
    _renewTimer?.cancel();
    _expiryTimer?.cancel();
    final remaining = pair.expiresAt.difference(now());
    final lead = remaining > refreshLeadTime
        ? remaining - refreshLeadTime
        : remaining ~/ 2;
    if (remaining > const Duration(seconds: 2)) {
      _renewTimer = Timer(lead, () => unawaited(refresh()));
    }
    _expiryTimer = Timer(remaining, checkExpiry);
  }

  Future<void> _failure(Object error, int generation) async {
    if (!_current(generation)) return;
    if (error is LoginApiException &&
        (error.unauthorized || error.invalidResponse)) {
      if (_interactiveLogin && _record == null && _candidate == null) {
        // A rejected login has no stored session to erase. Keep the form/email;
        // LoginPage displays the safe API error while clearing the password.
        _clearAccess();
        _phase = SessionPhase.signedOut;
        _notice = null;
        return;
      }
      await _forget(generation, error.message);
      return;
    }
    if (error is SessionStorageException) {
      _clearAccess();
      _phase = SessionPhase.storageFailure;
      _notice = error.message;
      return;
    }
    _notice = error is LoginApiException
        ? error.message
        : 'Oturum kontrolü tamamlanamadı. Lütfen tekrar deneyin.';
    if (_record?.rotationPending == true) {
      _notice =
          'Yenilemenin sonucu doğrulanamadı. Güvenliğiniz için eski token tekrar gönderilmeyecek. Oturumu temizleyip giriş yapın.';
      if (!isAuthenticated) _phase = SessionPhase.reauthenticate;
    } else if (!isAuthenticated) {
      _phase = _record == null ? SessionPhase.signedOut : SessionPhase.retry;
    }
  }

  Future<void> refreshUser() {
    if (_renewal != null) return _renewal!;
    if (_meRequest != null) return _meRequest!;
    if (!isAuthenticated) return refresh();
    final generation = _generation;
    final token = _accessToken!;
    final revision = _accessRevision;
    final operation = Future<void>.microtask(
      () => _readUser(generation, token, revision),
    );
    _meRequest = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_meRequest, operation)) _meRequest = null;
      }),
    );
    return operation;
  }

  Future<void> _readUser(int generation, String token, int revision) async {
    if (!_current(generation) || _accessRevision != revision) return;
    var denied = false;
    bool current() => _current(generation) && _accessRevision == revision;
    try {
      final user = await _api.currentUser(
        token,
        onUnauthorized: () {
          if (current() && _accessToken == token) {
            denied = true;
            _clearAccess();
            revision = _accessRevision;
            _phase = SessionPhase.working;
            _notify();
          }
        },
      );
      if (!current()) return;
      if (!user.isEmailVerified ||
          !const ['client', 'dietitian'].contains(user.role)) {
        await _forget(
          generation,
          'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
        );
        return;
      }
      if (!isAuthenticated) {
        await refresh();
        return;
      }
      _user = user;
      _notify();
    } catch (error) {
      if (!current()) return;
      if (denied || (error is LoginApiException && error.unauthorized)) {
        _clearAccess();
        _phase = SessionPhase.working;
        _notify();
        await refresh();
      } else {
        await _failure(error, generation);
        _notify();
      }
    }
  }

  void checkExpiry() {
    if (_disposed) return;
    if (_expiresAt != null && !_expiresAt!.isAfter(now())) {
      _clearAccess();
      _phase = SessionPhase.working;
      _notify();
      unawaited(refresh());
    }
  }

  Future<void> _forget(int generation, String message) async {
    if (!_current(generation)) return;
    _sessionEnded = true;
    generation = ++_generation;
    _renewal = null;
    _meRequest = null;
    _interactiveLogin = false;
    _signingOut = true;
    _working = true;
    _phase = SessionPhase.working;
    _clearAccess();
    _candidate = null;
    _notify();
    try {
      await _storage(() async {
        if (_current(generation)) await _store.clear();
      });
      if (!_current(generation)) return;
      _record = null;
      _cleanupRequired = false;
      _phase = SessionPhase.signedOut;
      _notice = message;
    } catch (_) {
      if (!_current(generation)) return;
      _cleanupRequired = true;
      _phase = SessionPhase.storageFailure;
      _notice =
          'Yerel oturum deposu temizlenemedi. Cihazın kilidini açıp tekrar deneyin.';
    } finally {
      if (_current(generation)) {
        _working = false;
        _signingOut = false;
        _notify();
      }
    }
  }

  Future<void> signOut({String? message}) async {
    if (_disposed) return;
    _sessionEnded = true;
    final generation = ++_generation;
    String? token = _candidate?.refreshToken ?? _record?.refreshToken;
    _signingOut = true;
    _interactiveLogin = false;
    _renewal = null;
    _meRequest = null;
    _working = true;
    _phase = SessionPhase.working;
    _clearAccess();
    _candidate = null;
    _notice = null;
    _notify();
    var localCleared = false;
    var serverAttempted = false;
    try {
      await _storage(() async {
        try {
          token ??= (await _store.read())?.refreshToken;
        } catch (_) {
          /* Still erase. */
        }
        await _store.clear();
      });
      localCleared = true;
      if (!_current(generation)) return;
      _record = null;
      _cleanupRequired = false;
      _phase = SessionPhase.signedOut;
      _notice = message;
      _working = false;
      _signingOut = false;
      _notify();
      if (token != null) {
        serverAttempted = true;
        await _api.logout(token!);
      }
    } catch (_) {
      if (!_current(generation)) return;
      if (!localCleared) {
        _cleanupRequired = true;
        _phase = SessionPhase.storageFailure;
        _notice =
            'Yerel oturum deposu temizlenemedi. Cihazın kilidini açıp tekrar deneyin.';
      } else {
        _notice =
            'Bu cihazdaki oturum kapatıldı. Sunucuda çıkış doğrulanamadı; oturumunuzun süresi sunucuda dolana kadar devam edebilir.';
      }
    } finally {
      if (_current(generation)) {
        _working = false;
        _signingOut = false;
        _notify();
      }
      if (!serverAttempted && token != null) {
        try {
          await _api.logout(token!);
        } catch (_) {
          /* Local failure remains visible. */
        }
      }
    }
  }

  void _clearAccess() {
    ++_accessRevision;
    _renewTimer?.cancel();
    _expiryTimer?.cancel();
    _renewTimer = null;
    _expiryTimer = null;
    _accessToken = null;
    _expiresAt = null;
    _user = null;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clearAccess();
    _record = null;
    _candidate = null;
    _renewal = null;
    _meRequest = null;
    super.dispose();
  }
}

class AuthSessionScope extends InheritedNotifier<AuthSession> {
  const AuthSessionScope({
    required AuthSession session,
    required super.child,
    super.key,
  }) : super(notifier: session);
  static AuthSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthSessionScope>()?.notifier;
}
