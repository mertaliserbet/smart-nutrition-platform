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
    final body = response.body;
    if (body is! Map<String, dynamic> ||
        body.length != 3 ||
        body['tokenType'] != 'Bearer' ||
        body['accessToken'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
        ).hasMatch(body['accessToken'] as String) ||
        body['expiresAt'] is! String ||
        !RegExp(r'(Z|\+00:00)$').hasMatch(body['expiresAt'] as String)) {
      throw const LoginApiException.invalidResponse();
    }
    final expiresAt = DateTime.tryParse(body['expiresAt'] as String);
    if (expiresAt == null) throw const LoginApiException.invalidResponse();
    // JWT claims are not used to grant access; /auth/me verifies the bearer.
    return LoginUserResponse(body['accessToken'] as String, expiresAt);
  });

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

  void _requireSuccess(JsonApiResponse response) {
    if (response.statusCode == 200) return;
    final message = switch ((
      response.statusCode,
      apiErrorCode(response.body),
    )) {
      (401, _) =>
        'Giriş yapılamadı. E-posta ve şifrenizi kontrol edip e-posta doğrulamasını tamamlayın. Admin hesapları MFA destekli web girişini kullanmalıdır.',
      (400, 'invalid_request') =>
        'E-posta ve şifre alanlarını kontrol edip tekrar deneyin.',
      (429, _) =>
        'Çok fazla giriş denemesi yapıldı. Bir süre bekleyip tekrar deneyin.',
      (>= 500, _) =>
        'Giriş servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
      _ => const LoginApiException.invalidResponse().message,
    };
    throw LoginApiException(message, unauthorized: response.statusCode == 401);
  }

  Future<T> _safe<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on LoginApiException {
      rethrow;
    } on HandshakeException {
      throw const LoginApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Lütfen daha sonra tekrar deneyin.',
      );
    } on TlsException {
      throw const LoginApiException(
        'Geliştirme sertifikası geçersiz. Bağlantı ayarlarını kontrol edin.',
      );
    } on IOException {
      throw const LoginApiException.connection();
    } on TimeoutException {
      throw const LoginApiException.connection();
    } on FormatException {
      throw const LoginApiException(
        'Giriş servisi adresi veya yanıtı geçersiz. Bağlantı ayarlarını kontrol edin.',
      );
    }
  }
}

class LoginUserResponse {
  const LoginUserResponse(this.accessToken, this.expiresAt);
  final String accessToken;
  final DateTime expiresAt;
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
  const LoginApiException(this.message, {this.unauthorized = false})
    : invalidResponse = false;
  const LoginApiException.connection()
    : message =
          'Bağlantı kurulamadı veya kesildi. Oturum doğrulanamadı; lütfen tekrar deneyin.',
      unauthorized = false,
      invalidResponse = false;
  const LoginApiException.invalidResponse()
    : message =
          'Sunucu yanıtı doğrulanamadı. Oturum açılmadı; lütfen tekrar deneyin.',
      unauthorized = false,
      invalidResponse = true;
  final String message;
  final bool unauthorized;
  final bool invalidResponse;
  @override
  String toString() => 'LoginApiException';
}
