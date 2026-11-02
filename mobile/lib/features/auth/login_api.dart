import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';

class LoginApi {
  LoginApi({this.baseUri, this.timeout = const Duration(seconds: 20)});

  final Uri? baseUri;
  final Duration timeout;

  Future<LoginUserResponse> login({
    required String email,
    required String password,
  }) => _safe(() async {
    final response = await postJson(
      path: '/api/v1/auth/login',
      payload: {'email': email.trim(), 'password': password},
      baseUri: baseUri,
      timeout: timeout,
    );
    _requireSuccess(response);
    return _pair(response);
  });

  Future<LoginUserResponse> refresh(String refreshToken) {
    var sending = false;
    var unauthorized = false;
    return _safe(
      () async {
        final response = await postJson(
          path: '/api/v1/auth/refresh',
          payload: {'refreshToken': refreshToken},
          baseUri: baseUri,
          timeout: timeout,
          onRequestSending: () => sending = true,
          onUnauthorized: () => unauthorized = true,
        );
        _requireSuccess(response, sessionAction: true);
        return _pair(response);
      },
      mayHaveSent: () => sending,
      unauthorizedSeen: () => unauthorized,
    );
  }

  Future<void> logout(String refreshToken) => _safe(() async {
    final response = await postJson(
      path: '/api/v1/auth/logout',
      payload: {'refreshToken': refreshToken},
      baseUri: baseUri,
      timeout: timeout,
    );
    if (response.statusCode == 204 && !response.hasBody) return;
    _requireSuccess(response, sessionAction: true);
    throw const LoginApiException.invalidResponse();
  });

  LoginUserResponse _pair(JsonApiResponse response) {
    final body = response.body;
    if (body is! Map<String, dynamic> ||
        body.length != 5 ||
        body['tokenType'] != 'Bearer' ||
        body['accessToken'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
        ).hasMatch(body['accessToken'] as String) ||
        body['expiresAt'] is! String ||
        !RegExp(r'(Z|\+00:00)$').hasMatch(body['expiresAt'] as String) ||
        body['refreshToken'] is! String ||
        (body['refreshToken'] as String).length != 43 ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(body['refreshToken'] as String) ||
        body['refreshTokenExpiresAt'] is! String ||
        !RegExp(
          r'(Z|\+00:00)$',
        ).hasMatch(body['refreshTokenExpiresAt'] as String)) {
      throw const LoginApiException.invalidResponse();
    }
    final expiresAt = DateTime.tryParse(body['expiresAt'] as String);
    final refreshExpiresAt = DateTime.tryParse(
      body['refreshTokenExpiresAt'] as String,
    );
    if (expiresAt == null || refreshExpiresAt == null) {
      throw const LoginApiException.invalidResponse();
    }
    // JWT claims are not used to grant access; /auth/me verifies the bearer.
    return LoginUserResponse(
      body['accessToken'] as String,
      expiresAt,
      body['refreshToken'] as String,
      refreshExpiresAt,
    );
  }

  Future<CurrentUserResponse> currentUser(
    String accessToken, {
    void Function()? onUnauthorized,
  }) => _safe(() async {
    final response = await getJson(
      path: '/api/v1/auth/me',
      accessToken: accessToken,
      baseUri: baseUri,
      timeout: timeout,
      onUnauthorized: onUnauthorized,
    );
    _requireSuccess(response);
    final body = response.body;
    if (body is! Map<String, dynamic> ||
        body.length != 5 ||
        body['id'] is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(body['id'] as String) ||
        !body.containsKey('displayName') ||
        (body['displayName'] != null && body['displayName'] is! String) ||
        body['email'] is! String ||
        (body['email'] as String).trim().isEmpty ||
        !const ['client', 'dietitian'].contains(body['role']) ||
        body['isEmailVerified'] != true) {
      throw const LoginApiException.invalidResponse();
    }
    return CurrentUserResponse(
      id: body['id'] as String,
      displayName: body['displayName'] as String?,
      email: body['email'] as String,
      role: body['role'] as String,
      isEmailVerified: true,
    );
  });

  void _requireSuccess(JsonApiResponse response, {bool sessionAction = false}) {
    if (response.statusCode == 200) return;
    final message = switch ((
      response.statusCode,
      apiErrorCode(response.body),
    )) {
      (401, _) when sessionAction =>
        'Oturumunuz geçersiz veya süresi dolmuş. Lütfen tekrar giriş yapın.',
      (401, _) =>
        'Giriş yapılamadı. E-posta ve şifrenizi kontrol edip e-posta doğrulamasını tamamlayın. Admin hesapları MFA destekli web girişini kullanmalıdır.',
      (400, 'invalid_request') when sessionAction =>
        'Oturum bilgileri doğrulanamadı. Lütfen tekrar deneyin.',
      (400, 'invalid_request') =>
        'E-posta ve şifre alanlarını kontrol edip tekrar deneyin.',
      (429, _) when sessionAction =>
        'Çok fazla oturum isteği yapıldı. Bir süre bekleyip tekrar deneyin.',
      (429, _) =>
        'Çok fazla giriş denemesi yapıldı. Bir süre bekleyip tekrar deneyin.',
      (>= 500, _) =>
        'Giriş servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
      _ => const LoginApiException.invalidResponse().message,
    };
    throw LoginApiException(
      message,
      unauthorized: response.statusCode == 401,
      safeToRetry: response.statusCode == 429 || response.statusCode == 400,
    );
  }

  Future<T> _safe<T>(
    Future<T> Function() operation, {
    bool Function()? mayHaveSent,
    bool Function()? unauthorizedSeen,
  }) async {
    LoginApiException failure(Object error) {
      if (unauthorizedSeen?.call() == true) {
        return const LoginApiException(
          'Oturumunuz geçersiz. Lütfen tekrar giriş yapın.',
          unauthorized: true,
        );
      }
      final safeToRetry = !(mayHaveSent?.call() ?? false);
      if (error is HandshakeException) {
        return LoginApiException(
          'Sunucuyla güvenli bağlantı kurulamadı. Lütfen daha sonra tekrar deneyin.',
          safeToRetry: safeToRetry,
        );
      }
      if (error is TlsException) {
        return LoginApiException(
          'Geliştirme sertifikası geçersiz. Bağlantı ayarlarını kontrol edin.',
          safeToRetry: safeToRetry,
        );
      }
      if (error is FormatException) {
        return LoginApiException(
          'Giriş servisi adresi veya yanıtı geçersiz. Bağlantı ayarlarını kontrol edin.',
          safeToRetry: safeToRetry,
        );
      }
      return LoginApiException.connection(safeToRetry: safeToRetry);
    }

    try {
      return await operation();
    } on LoginApiException {
      rethrow;
    } on IOException catch (error) {
      throw failure(error);
    } on TimeoutException catch (error) {
      throw failure(error);
    } on FormatException catch (error) {
      throw failure(error);
    }
  }
}

class LoginUserResponse {
  const LoginUserResponse(
    this.accessToken,
    this.expiresAt,
    this.refreshToken,
    this.refreshTokenExpiresAt,
  );
  final String accessToken;
  final DateTime expiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
}

class CurrentUserResponse {
  const CurrentUserResponse({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    required this.isEmailVerified,
  });
  final String id;
  final String? displayName;
  final String email;
  final String role;
  final bool isEmailVerified;
}

class LoginApiException implements Exception {
  const LoginApiException(
    this.message, {
    this.unauthorized = false,
    this.safeToRetry = false,
  }) : invalidResponse = false;
  const LoginApiException.connection({this.safeToRetry = true})
    : message =
          'Bağlantı kurulamadı veya kesildi. Oturum doğrulanamadı; lütfen tekrar deneyin.',
      unauthorized = false,
      invalidResponse = false;
  const LoginApiException.invalidResponse()
    : message =
          'Sunucu yanıtı doğrulanamadı. Oturum açılmadı; lütfen tekrar deneyin.',
      unauthorized = false,
      invalidResponse = true,
      safeToRetry = false;
  final String message;
  final bool unauthorized;
  final bool invalidResponse;
  final bool safeToRetry;
  @override
  String toString() => 'LoginApiException';
}
