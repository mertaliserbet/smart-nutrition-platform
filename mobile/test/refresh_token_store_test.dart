import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';

void main() {
  final origin = Uri.parse('https://api.example.test');
  final key =
      'smart_nutrition.refresh.v1.${base64UrlEncode(utf8.encode(origin.origin))}';
  final token = 'A' * 43;
  final record = StoredRefreshToken(token, DateTime.utc(2026, 12, 1));
  const native = FlutterSecureStorage();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'stores only refresh/expiry/pending in one secure item on $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final store = SecureRefreshTokenStore(baseUri: origin);
        await store.write(record.pending(true));
        final items = await native.readAll();
        expect(items.keys, [key]);
        final body = jsonDecode(items[key]!) as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'refreshToken',
          'refreshTokenExpiresAt',
          'rotationPending',
        });
        expect(body['rotationPending'], isTrue);
        final read = await store.read();
        expect(read!.refreshToken, token);
        expect(read.refreshTokenExpiresAt, record.refreshTokenExpiresAt);
        expect(read.rotationPending, isTrue);
        expect(read.toString(), isNot(contains(token)));
      },
    );
  }

  test(
    'API origins are isolated and clear never deletes another origin',
    () async {
      final first = SecureRefreshTokenStore(baseUri: origin);
      final second = SecureRefreshTokenStore(
        baseUri: Uri.parse('https://other.example.test'),
      );
      await first.write(record);
      expect(await second.read(), isNull);
      await second.write(
        StoredRefreshToken('B' * 43, record.refreshTokenExpiresAt),
      );
      await first.clear();
      expect(await first.read(), isNull);
      expect((await second.read())!.refreshToken, 'B' * 43);
    },
  );

  for (final value in [
    '{bad',
    '{}',
    jsonEncode({
      'refreshToken': token,
      'refreshTokenExpiresAt': 'not-a-date',
      'rotationPending': false,
    }),
    jsonEncode({
      'refreshToken': token,
      'refreshTokenExpiresAt': '2026-12-01T00:00:00',
      'rotationPending': false,
    }),
    jsonEncode({
      'refreshToken': 'short',
      'refreshTokenExpiresAt': '2026-12-01T00:00:00Z',
      'rotationPending': false,
    }),
    jsonEncode({
      'refreshToken': token,
      'refreshTokenExpiresAt': '2026-12-01T00:00:00Z',
      'rotationPending': 'false',
    }),
  ]) {
    test(
      'corrupt secure record fails closed (${value.length} bytes)',
      () async {
        await native.write(key: key, value: value);
        await expectLater(
          SecureRefreshTokenStore(baseUri: origin).read(),
          throwsA(isA<SessionStorageException>()),
        );
      },
    );
  }

  test(
    'clear overwrites credential with signed-out marker if native delete fails',
    () async {
      final failing = FailingStorage();
      final store = SecureRefreshTokenStore(storage: failing, baseUri: origin);
      await store.write(record);
      failing.failDeletes = true;
      await store.clear();
      expect(await native.read(key: key), '{"signedOut":true}');
      expect(await store.read(), isNull);
    },
  );

  test('clear still deletes if native overwrite fails', () async {
    final failing = FailingStorage();
    final store = SecureRefreshTokenStore(storage: failing, baseUri: origin);
    await store.write(record);
    failing.failWrites = true;
    await store.clear();
    expect(await native.read(key: key), isNull);
  });

  test(
    'failure of both secure erase methods is reported, never silently accepted',
    () async {
      final failing = FailingStorage();
      final store = SecureRefreshTokenStore(storage: failing, baseUri: origin);
      await store.write(record);
      failing.failWrites = failing.failDeletes = true;
      await expectLater(store.clear(), throwsA(isA<SessionStorageException>()));
      expect((await store.read())!.refreshToken, token);
      expect(
        const SessionStorageException().toString(),
        'SessionStorageException',
      );
    },
  );

  test(
    'unsupported platforms have no plaintext or web-storage fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final store = SecureRefreshTokenStore(baseUri: origin);
      await expectLater(
        store.write(record),
        throwsA(isA<SessionStorageException>()),
      );
      await expectLater(store.read(), throwsA(isA<SessionStorageException>()));
      expect(await native.readAll(), isEmpty);
    },
  );
}

class FailingStorage extends FlutterSecureStorage {
  bool failWrites = false, failDeletes = false;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failWrites) throw PlatformException(code: 'synthetic-write-failure');
    return super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failDeletes) throw PlatformException(code: 'synthetic-delete-failure');
    return super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}
