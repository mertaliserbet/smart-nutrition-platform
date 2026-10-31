import 'dart:async';
import 'package:flutter/widgets.dart';

import 'login_api.dart';

/// A process-local session. Only login + server-verified /me can open the gate.
class AuthSession extends ChangeNotifier {
  AuthSession({LoginApi? api, this.now = DateTime.now})
    : _api = api ?? LoginApi();
  final LoginApi _api;
  final DateTime Function() now;
  String? _accessToken;
  DateTime? _expiresAt;
  CurrentUserResponse? _user;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _disposed = false;
  bool _busy = false;
  String? _notice;

  bool get isAuthenticated =>
      _user != null && _accessToken != null && _expiresAt!.isAfter(now());
  bool get isBusy => _busy;
  CurrentUserResponse? get user => isAuthenticated ? _user : null;
  String? get notice => _notice;

  Future<bool> signIn({required String email, required String password}) async {
    if (_busy || _disposed) return false;
    final generation = ++_generation;
    _clear();
    _busy = true;
    _notice = null;
    notifyListeners();
    try {
      final login = await _api.login(email: email, password: password);
      if (!_current(generation)) return false;
      if (!login.expiresAt.isAfter(now())) {
        throw const LoginApiException.invalidResponse();
      }
      final user = await _api.currentUser(login.accessToken);
      if (!_current(generation)) return false;
      if (!login.expiresAt.isAfter(now()) ||
          !user.isEmailVerified ||
          !const ['client', 'dietitian'].contains(user.role)) {
        throw const LoginApiException.invalidResponse();
      }
      _accessToken = login.accessToken;
      _expiresAt = login.expiresAt;
      _user = user;
      _expiryTimer = Timer(login.expiresAt.difference(now()), checkExpiry);
      return true;
    } catch (_) {
      if (!_current(generation)) return false;
      _clear();
      rethrow;
    } finally {
      if (_current(generation)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Future authenticated API operations must use the same 401 invalidation.
  Future<void> refreshUser() async {
    checkExpiry();
    final token = _accessToken;
    if (!isAuthenticated || token == null) return;
    final generation = _generation;
    try {
      final user = await _api.currentUser(
        token,
        onUnauthorized: () {
          if (_current(generation)) {
            signOut(message: 'Oturumunuz geçersiz. Lütfen tekrar giriş yapın.');
          }
        },
      );
      if (!_current(generation)) return;
      checkExpiry();
      if (!isAuthenticated) return;
      if (!user.isEmailVerified ||
          !const ['client', 'dietitian'].contains(user.role)) {
        signOut(
          message: 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
        );
        return;
      }
      _user = user;
      notifyListeners();
    } on LoginApiException catch (error) {
      if ((error.unauthorized || error.invalidResponse) &&
          _current(generation)) {
        signOut(message: 'Oturumunuz geçersiz. Lütfen tekrar giriş yapın.');
      }
      rethrow;
    }
  }

  void checkExpiry() {
    if (!_disposed && _expiresAt != null && !_expiresAt!.isAfter(now())) {
      signOut(message: 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.');
    }
  }

  void signOut({String? message}) {
    if (_disposed) return;
    ++_generation; // Discard late login/me/401 responses from previous sessions.
    _clear();
    _busy = false;
    _notice = message;
    notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _accessToken = null;
    _expiresAt = null;
    _user = null;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clear();
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
