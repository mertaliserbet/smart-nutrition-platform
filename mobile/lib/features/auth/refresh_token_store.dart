import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/api_config.dart';

class StoredRefreshToken {
  const StoredRefreshToken(
    this.refreshToken,
    this.refreshTokenExpiresAt, {
    this.rotationPending = false,
  });
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final bool rotationPending;
  StoredRefreshToken pending(bool value) => StoredRefreshToken(
    refreshToken,
    refreshTokenExpiresAt,
    rotationPending: value,
  );
}

abstract interface class RefreshTokenStore {
  Future<StoredRefreshToken?> read();
  Future<void> write(StoredRefreshToken value);
  Future<void> clear();
}

/// One encrypted item per API origin. Access tokens and account data never enter storage.
class SecureRefreshTokenStore implements RefreshTokenStore {
  SecureRefreshTokenStore({FlutterSecureStorage? storage, this.baseUri})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              migrateOnAlgorithmChange: false,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
              synchronizable: false,
            ),
          );
  final FlutterSecureStorage _storage;
  final Uri? baseUri;
  String get _key =>
      'smart_nutrition.refresh.v1.${base64UrlEncode(utf8.encode((baseUri ?? ApiConfig.baseUri).origin))}';

  void _requireMobile() {
    if (kIsWeb ||
        !const [
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      throw const SessionStorageException();
    }
  }

  @override
  Future<StoredRefreshToken?> read() async {
    try {
      _requireMobile();
      final value = await _storage.read(key: _key);
      if (value == null || value == '{"signedOut":true}') return null;
      final body = jsonDecode(value);
      if (body is! Map<String, dynamic> ||
          body.length != 3 ||
          body['refreshToken'] is! String ||
          (body['refreshToken'] as String).length != 43 ||
          !RegExp(
            r'^[A-Za-z0-9_-]{43}$',
          ).hasMatch(body['refreshToken'] as String) ||
          body['refreshTokenExpiresAt'] is! String ||
          body['rotationPending'] is! bool) {
        throw const SessionStorageException();
      }
      final expiry = DateTime.tryParse(body['refreshTokenExpiresAt'] as String);
      if (expiry == null || !expiry.isUtc) {
        throw const SessionStorageException();
      }
      return StoredRefreshToken(
        body['refreshToken'] as String,
        expiry,
        rotationPending: body['rotationPending'] as bool,
      );
    } catch (_) {
      throw const SessionStorageException();
    }
  }

  @override
  Future<void> write(StoredRefreshToken value) async {
    try {
      _requireMobile();
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'refreshToken': value.refreshToken,
          'refreshTokenExpiresAt': value.refreshTokenExpiresAt
              .toUtc()
              .toIso8601String(),
          'rotationPending': value.rotationPending,
        }),
      );
    } catch (_) {
      throw const SessionStorageException();
    }
  }

  @override
  Future<void> clear() async {
    _requireMobile();
    var overwritten = false;
    try {
      // If deletion fails after overwrite, no credential remains to restore.
      await _storage.write(key: _key, value: '{"signedOut":true}');
      overwritten = true;
    } catch (_) {
      /* Still attempt deletion. */
    }
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      if (!overwritten) throw const SessionStorageException();
    }
  }
}

class SessionStorageException implements Exception {
  const SessionStorageException();
  String get message =>
      'Güvenli oturum deposuna erişilemedi. Cihazın kilidini açıp tekrar deneyin.';
  @override
  String toString() => 'SessionStorageException';
}
