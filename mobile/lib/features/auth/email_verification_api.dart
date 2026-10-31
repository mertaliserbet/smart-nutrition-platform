import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';

class EmailVerificationApi {
  EmailVerificationApi({
    this.baseUri,
    this.timeout = const Duration(seconds: 20),
  });

  final Uri? baseUri;
  final Duration timeout;

  Future<void> verifyEmail(String token) =>
      _post('verify-email', {'token': token.trim()}, 204);

  Future<void> resendVerification(String email) =>
      _post('resend-verification', {'email': email.trim()}, 202);

  Future<void> _post(
    String action,
    Map<String, String> payload,
    int expectedStatus,
  ) async {
    try {
      final response = await postJson(
        path: '/api/v1/auth/$action',
        payload: payload,
        baseUri: baseUri,
        timeout: timeout,
      );
      if (response.statusCode == expectedStatus && !response.hasBody) return;
      final code = apiErrorCode(response.body);
      if (response.statusCode == 429 && code == 'rate_limited') {
        throw EmailVerificationApiException(
          'Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.',
          retryAfter: response.retryAfter ?? const Duration(seconds: 60),
        );
      }
      final message = switch ((response.statusCode, code)) {
        (422, 'validation_failed') when action == 'verify-email' =>
          'Kod geçersiz, süresi dolmuş veya daha önce kullanılmış. En son e-postadaki kodu kullanın ya da yeni kod isteyin.',
        (400, 'invalid_request') => 'Bilgileri kontrol edip tekrar deneyin.',
        (>= 500, _) =>
          'Doğrulama servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
        _ =>
          'Sunucu yanıtı doğrulanamadı. İşlem sonucu kesinleşmedi; lütfen tekrar deneyin.',
      };
      throw EmailVerificationApiException(message);
    } on EmailVerificationApiException {
      rethrow;
    } on HandshakeException {
      throw const EmailVerificationApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Lütfen daha sonra tekrar deneyin.',
      );
    } on TlsException {
      throw const EmailVerificationApiException(
        'Geliştirme sertifikası geçersiz. Bağlantı ayarlarını kontrol edin.',
      );
    } on IOException {
      throw const EmailVerificationApiException.connection();
    } on TimeoutException {
      throw const EmailVerificationApiException.connection();
    } on FormatException {
      throw const EmailVerificationApiException(
        'Doğrulama servisi adresi yapılandırılmamış veya geçersiz.',
      );
    }
  }
}

class EmailVerificationApiException implements Exception {
  const EmailVerificationApiException(this.message, {this.retryAfter});
  const EmailVerificationApiException.connection()
    : message =
          'Bağlantı kurulamadı veya kesildi. İşlem sonucu doğrulanamadı; lütfen tekrar deneyin.',
      retryAfter = null;

  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'EmailVerificationApiException';
}
