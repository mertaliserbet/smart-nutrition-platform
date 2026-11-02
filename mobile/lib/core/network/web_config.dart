import 'package:flutter/foundation.dart';

abstract final class WebConfig {
  static const _configuredUrl = String.fromEnvironment('WEB_BASE_URL');

  static Uri dietitianApplicationUri({
    String? baseUrl,
    bool isDebug = kDebugMode,
  }) {
    final configured = baseUrl ?? _configuredUrl;
    final value = configured.isEmpty && isDebug
        ? 'https://localhost:5173'
        : configured;
    final uri = Uri.tryParse(value);
    if (value != value.trim() ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('Invalid website origin configuration.');
    }
    // An origin is the only configurable input. Never attach session data,
    // return URLs or route arguments to the public application page.
    return uri.replace(path: '/uzman-basvurusu');
  }
}
