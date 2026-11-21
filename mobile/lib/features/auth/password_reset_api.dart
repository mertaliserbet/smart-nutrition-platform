import 'dart:async';
import 'dart:io';
import '../../core/network/json_api.dart';

/// Anonymous single-attempt requests; secrets are never persisted.
class PasswordResetApi {
  PasswordResetApi({this.baseUri, this.timeout = const Duration(seconds: 20)});
  final Uri? baseUri;
  final Duration timeout;
  Future<void> request(String email) =>
      _post('password-reset-requests', {'email': email.trim()}, 202);
  Future<void> reset(String token, String password) => _post('reset-password', {
    'token': token.trim(),
    'password': password,
  }, 204);
  Future<void> _post(
    String action,
    Map<String, String> payload,
    int expected,
  ) async {
    try {
      final response = await postJson(
        path: '/api/v1/auth/$action',
        payload: payload,
        baseUri: baseUri,
        timeout: timeout,
      );
      if (response.statusCode == expected && !response.hasBody) return;
      final code = apiErrorCode(response.body);
      if (response.statusCode == 429 && code == 'rate_limited') {
        throw PasswordResetApiException(
          'Çok fazla istek yapıldı. Bir süre bekleyip yeniden deneyin.',
          retryAfter: response.retryAfter,
        );
      }
      throw PasswordResetApiException(switch ((response.statusCode, code)) {
        (422, 'validation_failed') =>
          'Kod geçersiz, süresi dolmuş veya kullanılmış olabilir; şifreniz de kurallara uygun olmalıdır. En son e-postadaki kodu kullanın ya da yeni kod isteyin.',
        (400, 'invalid_request') => 'Bilgileri kontrol edip yeniden deneyin.',
        (>= 500, _) =>
          'Şifre sıfırlama servisi şu anda kullanılamıyor. Daha sonra yeniden deneyin.',
        _ =>
          'İşlem sonucu doğrulanamadı. Otomatik tekrar yapılmadı; durumunuzu kontrol edin.',
      });
    } on PasswordResetApiException {
      rethrow;
    } on HandshakeException {
      throw const PasswordResetApiException(
        'Sunucuyla güvenli bağlantı kurulamadı.',
      );
    } on TlsException {
      throw const PasswordResetApiException(
        'Sunucunun güvenlik sertifikası doğrulanamadı.',
      );
    } on IOException {
      throw const PasswordResetApiException.connection();
    } on TimeoutException {
      throw const PasswordResetApiException.connection();
    } on FormatException {
      throw const PasswordResetApiException(
        'Sunucu adresi veya yanıtı doğrulanamadı.',
      );
    }
  }
}

class PasswordResetApiException implements Exception {
  const PasswordResetApiException(this.message, {this.retryAfter});
  const PasswordResetApiException.connection()
    : message =
          'Bağlantı kesildi veya zaman aşımına uğradı. İşlem tamamlanmış olabilir; otomatik tekrar yapılmadı. Yeni şifrenizle giriş yapmayı deneyebilir veya kendiniz yeniden işlem başlatabilirsiniz.',
      retryAfter = null;
  final String message;
  final Duration? retryAfter;
  @override
  String toString() => 'PasswordResetApiException';
}
