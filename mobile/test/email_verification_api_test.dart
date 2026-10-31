import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_api.dart';

void main() {
  late HttpServer server;
  late EmailVerificationApi api;
  late Uri origin;
  final token = 'A' * 43;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = Uri.parse('http://127.0.0.1:${server.port}');
    api = EmailVerificationApi(baseUri: origin);
  });
  tearDown(() async => server.close(force: true));

  for (final verify in [true, false]) {
    test(
      '${verify ? 'verify 204' : 'resend 202'} sends only contract fields',
      () async {
        final captured = Completer<Map<String, Object?>>();
        server.listen((request) async {
          captured.complete({
            'method': request.method,
            'path': request.uri.path,
            'body': jsonDecode(await utf8.decoder.bind(request).join()),
            'authorization': request.headers.value(
              HttpHeaders.authorizationHeader,
            ),
            'cookie': request.headers.value(HttpHeaders.cookieHeader),
            'contentType': request.headers.contentType?.mimeType,
          });
          request.response.statusCode = verify ? 204 : 202;
          await request.response.close();
        });
        if (verify) {
          await api.verifyEmail(' $token ');
        } else {
          await api.resendVerification(' synthetic@example.test ');
        }
        expect(await captured.future, {
          'method': 'POST',
          'path':
              '/api/v1/auth/${verify ? 'verify-email' : 'resend-verification'}',
          'body': verify
              ? {'token': token}
              : {'email': 'synthetic@example.test'},
          'authorization': null,
          'cookie': null,
          'contentType': 'application/json',
        });
      },
    );
  }

  for (final status in [200, 201, 202, 302]) {
    test(
      'verify rejects unexpected status $status without following redirects',
      () async {
        var requests = 0;
        server.listen((request) async {
          requests++;
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.headers.set(HttpHeaders.locationHeader, '/redirect');
          await request.response.close();
        });
        await expectLater(
          api.verifyEmail(token),
          throwsA(isA<EmailVerificationApiException>()),
        );
        expect(requests, 1);
      },
    );
  }

  for (final response in [(204, ''), (202, '{}')]) {
    test('resend rejects non-contract response $response', () async {
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = response.$1
          ..write(response.$2);
        await request.response.close();
      });
      await expectLater(
        api.resendVerification('synthetic@example.test'),
        throwsA(isA<EmailVerificationApiException>()),
      );
    });
  }

  for (final entry in [
    (422, 'validation_failed', 'Kod geçersiz'),
    (400, 'invalid_request', 'Bilgileri kontrol'),
    (500, 'internal_error', 'şu anda kullanılamıyor'),
  ]) {
    test(
      'maps ${entry.$1} safely without exposing server details or tokens',
      () async {
        server.listen((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = entry.$1
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'error': {
                  'code': entry.$2,
                  'message': 'private $token',
                  'details': {'token': token},
                },
                'requestId': 'synthetic-request',
              }),
            );
          await request.response.close();
        });
        try {
          await api.verifyEmail(token);
          fail('An API error must not verify the email');
        } on EmailVerificationApiException catch (error) {
          expect(error.message, contains(entry.$3));
          expect(error.message, isNot(contains(token)));
          expect(error.toString(), isNot(contains(token)));
        }
      },
    );
  }

  for (final header in [null, '180', 'invalid']) {
    test(
      '429 uses Retry-After $header or conservative local fallback',
      () async {
        server.listen((request) async {
          await request.drain<void>();
          if (header != null) {
            request.response.headers.set(HttpHeaders.retryAfterHeader, header);
          }
          request.response
            ..statusCode = 429
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'error': {'code': 'rate_limited', 'message': 'limited'},
                'requestId': 'synthetic',
              }),
            );
          await request.response.close();
        });
        await expectLater(
          api.resendVerification('synthetic@example.test'),
          throwsA(
            isA<EmailVerificationApiException>().having(
              (e) => e.retryAfter,
              'retryAfter',
              Duration(seconds: header == '180' ? 180 : 60),
            ),
          ),
        );
      },
    );
  }

  test('429 accepts HTTP-date Retry-After', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 429
        ..headers.contentType = ContentType.json
        ..headers.set(
          HttpHeaders.retryAfterHeader,
          HttpDate.format(
            DateTime.now().toUtc().add(const Duration(minutes: 3)),
          ),
        )
        ..write(
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'limited'},
            'requestId': 'synthetic',
          }),
        );
      await request.response.close();
    });
    await expectLater(
      api.verifyEmail(token),
      throwsA(
        isA<EmailVerificationApiException>().having(
          (e) => e.retryAfter!.inSeconds,
          'retry seconds',
          inInclusiveRange(175, 180),
        ),
      ),
    );
  });

  test('malformed error envelope cannot manufacture success', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 422
        ..headers.contentType = ContentType.json
        ..write('{invalid json');
      await request.response.close();
    });
    await expectLater(
      api.verifyEmail(token),
      throwsA(
        isA<EmailVerificationApiException>().having(
          (e) => e.message,
          'message',
          contains('sonucu kesinleşmedi'),
        ),
      ),
    );
  });

  test(
    'connection refusal does not claim a failed or successful server transaction',
    () async {
      await server.close(force: true);
      await expectLater(
        api.verifyEmail(token),
        throwsA(
          isA<EmailVerificationApiException>().having(
            (e) => e.message,
            'message',
            contains('sonucu doğrulanamadı'),
          ),
        ),
      );
    },
  );

  test('timeout closes the request and does not retry', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
    });
    api = EmailVerificationApi(
      baseUri: origin,
      timeout: const Duration(milliseconds: 150),
    );
    await expectLater(
      api.verifyEmail(token),
      throwsA(
        isA<EmailVerificationApiException>().having(
          (e) => e.message,
          'message',
          contains('Bağlantı'),
        ),
      ),
    );
    expect(requests, 1);
  });
}
