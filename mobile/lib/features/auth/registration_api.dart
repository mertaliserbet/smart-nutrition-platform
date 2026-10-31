import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';

class RegistrationApi {
  RegistrationApi({this.baseUri, this.timeout = const Duration(seconds: 20)});

  final Uri? baseUri;
  final Duration timeout;

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await postJson(
        path: '/api/v1/auth/register',
        payload: {
          'displayName': displayName,
          'email': email,
          'password': password,
        },
        baseUri: baseUri,
        timeout: timeout,
      );
      final body = response.body;
      if (response.statusCode == HttpStatus.created) {
        if (body is Map<String, dynamic> &&
            body.length == 1 &&
            body['id'] is String &&
            RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(body['id'] as String)) {
          return;
        }
        throw const RegistrationApiException.invalidResponse();
      }
      // Raw messages/details can contain user data and are never surfaced.
      final message = switch ((response.statusCode, apiErrorCode(body))) {
        (409, 'conflict') =>
          'Bu e-posta adresiyle bir hesap zaten var. Giriş yapmayı deneyebilirsiniz.',
        (400, 'invalid_request') =>
          'Kayıt bilgileri doğrulanamadı. Ad soyad ve e-posta alanlarını kontrol edin.',
        (422, 'validation_failed') =>
          'Kayıt bilgileri kabul edilmedi. Şifrenizin 8–128 karakter olduğunu kontrol edin.',
        (429, 'rate_limited') =>
          'Çok fazla deneme yapıldı. Bir süre sonra tekrar deneyin.',
        (>= 500, _) =>
          'Kayıt servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
        _ => const RegistrationApiException.invalidResponse().message,
      };
      throw RegistrationApiException(message);
    } on RegistrationApiException {
      rethrow;
    } on HandshakeException {
      throw const RegistrationApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Lütfen daha sonra tekrar deneyin.',
      );
    } on TlsException {
      throw const RegistrationApiException(
        'Geliştirme sertifikası geçersiz. Kayıt bağlantı ayarlarını kontrol edin.',
      );
    } on IOException {
      throw const RegistrationApiException.connection();
    } on TimeoutException {
      throw const RegistrationApiException.connection();
    } on FormatException {
      throw const RegistrationApiException(
        'Kayıt servisi adresi yapılandırılmamış veya geçersiz.',
      );
    }
  }
}

class RegistrationApiException implements Exception {
  const RegistrationApiException(this.message);

  const RegistrationApiException.connection()
    : message =
          'Bağlantı kurulamadı veya kesildi. Kayıt sonucu doğrulanamadı. Tekrar denemeden önce e-postanızı kontrol edin.';

  const RegistrationApiException.invalidResponse()
    : message =
          'Sunucu yanıtı doğrulanamadı. Tekrar denemeden önce e-postanızı kontrol edin.';

  final String message;

  @override
  String toString() => 'RegistrationApiException';
}
