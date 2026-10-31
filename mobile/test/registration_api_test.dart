import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/api_config.dart';
import 'package:smart_nutrition_mobile/features/auth/registration_api.dart';

const userId = '41111111-1111-4111-8111-111111111111';

void main() {
  test('Android debug uses HTTPS localhost through the adb reverse tunnel', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(ApiConfig.baseUri.toString(), 'https://localhost:7099');
  });

  test('API origin requires HTTPS outside local debug development', () {
    expect(
      ApiConfig.validate(
        'https://api.example.test',
        allowLocalHttp: false,
      ).host,
      'api.example.test',
    );
    for (final value in [
      '',
      'http://10.0.2.2:5052',
      'http://localhost:5052',
      'https://user:password@example.test',
      'https://example.test/api/v1',
      'https://example.test?secret=value',
      'https://example.test#fragment',
    ]) {
      expect(
        () => ApiConfig.validate(value, allowLocalHttp: false),
        throwsFormatException,
      );
    }
    expect(
      () => ApiConfig.validate('http://192.0.2.1:5052', allowLocalHttp: true),
      throwsFormatException,
    );
  });

  group('real HTTP transport with an isolated loopback test server', () {
    late HttpServer server;
    late RegistrationApi api;
    late Uri origin;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = Uri.parse('http://127.0.0.1:${server.port}');
      api = RegistrationApi(baseUri: origin);
    });
    tearDown(() async => server.close(force: true));

    test(
      '201 sends exactly the approved fields without changing the password',
      () async {
        final captured = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          captured.complete({
            'method': request.method,
            'path': request.uri.toString(),
            'contentType': request.headers.contentType?.mimeType,
            'authorization': request.headers.value(
              HttpHeaders.authorizationHeader,
            ),
            'cookie': request.headers.value(HttpHeaders.cookieHeader),
            'body': body,
          });
          request.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': userId}));
          await request.response.close();
        });
        const password = '  Şifre😀e\u0301  ';
        await api.register(
          displayName: 'İpek Şen',
          email: 'synthetic@example.test',
          password: password,
        );
        expect(await captured.future, {
          'method': 'POST',
          'path': '/api/v1/auth/register',
          'contentType': 'application/json',
          'authorization': null,
          'cookie': null,
          'body': {
            'displayName': 'İpek Şen',
            'email': 'synthetic@example.test',
            'password': password,
          },
        });
      },
    );

    for (final scenario in [
      (status: 409, code: 'conflict', message: 'hesap zaten var'),
      (status: 400, code: 'invalid_request', message: 'Ad soyad ve e-posta'),
      (status: 422, code: 'validation_failed', message: '8–128'),
      (status: 429, code: 'rate_limited', message: 'Çok fazla deneme'),
      (status: 500, code: 'internal_error', message: 'şu anda kullanılamıyor'),
      (status: 503, code: 'internal_error', message: 'şu anda kullanılamıyor'),
    ]) {
      test(
        '${scenario.status}/${scenario.code} maps the API envelope safely',
        () async {
          server.listen((request) async {
            await request.drain<void>();
            request.response
              ..statusCode = scenario.status
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'error': {
                    'code': scenario.code,
                    'message': 'sensitive server text',
                    'details': {'password': 'must not be shown'},
                  },
                  'requestId': 'synthetic-request',
                }),
              );
            await request.response.close();
          });
          await expectLater(
            submit(api),
            throwsA(
              isA<RegistrationApiException>()
                  .having(
                    (error) => error.message,
                    'message',
                    contains(scenario.message),
                  )
                  .having(
                    (error) => error.message,
                    'safe message',
                    isNot(contains('sensitive')),
                  )
                  .having(
                    (error) => error.toString(),
                    'safe exception',
                    'RegistrationApiException',
                  ),
            ),
          );
        },
      );
    }

    for (final scenario in [
      (status: 200, body: '{"id":"$userId"}'),
      (status: 202, body: '{"id":"$userId"}'),
      (status: 204, body: ''),
      (status: 201, body: ''),
      (status: 201, body: '{broken'),
      (status: 201, body: '{"id":"not-a-uuid"}'),
      (status: 201, body: '{"accessToken":"unexpected"}'),
      (status: 409, body: '{"error":{"code":"conflict"}}'),
    ]) {
      test(
        'rejects unexpected status/body ${scenario.status}: ${scenario.body}',
        () async {
          server.listen((request) async {
            await request.drain<void>();
            request.response
              ..statusCode = scenario.status
              ..headers.contentType = ContentType.json
              ..write(scenario.body);
            await request.response.close();
          });
          await expectLater(
            submit(api),
            throwsA(isA<RegistrationApiException>()),
          );
        },
      );
    }

    test(
      'does not follow a redirect or send credentials a second time',
      () async {
        var count = 0;
        server.listen((request) async {
          count++;
          await request.drain<void>();
          request.response
            ..statusCode = 303
            ..headers.set(HttpHeaders.locationHeader, '/another-endpoint');
          await request.response.close();
        });
        await expectLater(
          submit(api),
          throwsA(isA<RegistrationApiException>()),
        );
        expect(count, 1);
      },
    );

    test('a dropped connection is unconfirmed and is never retried', () async {
      var count = 0;
      server.listen((request) async {
        count++;
        await request.drain<void>();
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      });
      await expectLater(
        submit(api),
        throwsA(
          isA<RegistrationApiException>().having(
            (error) => error.message,
            'unconfirmed result',
            const RegistrationApiException.connection().message,
          ),
        ),
      );
      expect(count, 1);
    });

    test(
      'timeout closes an unfinished request without automatic retry',
      () async {
        var count = 0;
        server.listen((request) async {
          count++;
          await request.drain<void>();
          // Deliberately leave the response unfinished until server teardown.
        });
        final shortTimeout = RegistrationApi(
          baseUri: origin,
          timeout: const Duration(milliseconds: 150),
        );
        await expectLater(
          submit(shortTimeout),
          throwsA(isA<RegistrationApiException>()),
        );
        expect(count, 1);
      },
    );
  });
}

Future<void> submit(RegistrationApi api) => api.register(
  displayName: 'Sentetik Danışan',
  email: 'synthetic@example.test',
  password: 'Sentetik şifre',
);
