import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const _configuredUrl = String.fromEnvironment('API_BASE_URL');

  static Uri get baseUri {
    if (_configuredUrl.isNotEmpty) return validate(_configuredUrl);
    if (!kDebugMode) return validate('');
    return validate('https://localhost:7099');
  }

  static SecurityContext? get developmentSecurityContext {
    const certificate = String.fromEnvironment('API_DEV_CERT_BASE64');
    if (!kDebugMode || certificate.isEmpty) return null;
    // Explicit trust in the public development certificate, never a TLS bypass.
    // Normal chain, expiry and hostname verification remain enabled.
    return SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(base64Decode(certificate));
  }

  static Uri validate(String value, {bool allowLocalHttp = kDebugMode}) {
    final uri = Uri.tryParse(value);
    final localHttp =
        allowLocalHttp &&
        uri?.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri?.host);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !localHttp) ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid API origin configuration.');
    }
    return uri;
  }
}
