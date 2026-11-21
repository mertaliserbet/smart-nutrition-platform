import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/password_reset_api.dart';

void main() {
  late HttpServer server;
  late PasswordResetApi api;
  late Future<void> Function(HttpRequest) respond;
  var calls = 0;
  setUp(() async {
    calls = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = PasswordResetApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    server.listen((request) async {
      calls++;
      await respond(request);
    });
  });
  tearDown(() => server.close(force: true));
  Future<void> reply(HttpRequest request, int status, [Object? body]) async {
    request.response.statusCode = status;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  }

  test('request is anonymous and sends only the trimmed email once', () async {
    respond = (r) async {
      expect(r.method, 'POST');
      expect(r.uri.path, '/api/v1/auth/password-reset-requests');
      expect(r.uri.query, isEmpty);
      for (final header in ['authorization', 'cookie', 'x-csrf-token']) {
        expect(r.headers.value(header), isNull);
      }
      expect(jsonDecode(await utf8.decoder.bind(r).join()), {
        'email': 'synthetic@example.test',
      });
      await reply(r, 202);
    };
    await api.request(' synthetic@example.test ');
    expect(calls, 1);
  });
  test(
    'reset sends only token and unchanged Unicode password, without authentication',
    () async {
      final token = 'A' * 43;
      const password = ' Şifre🔒123 ';
      respond = (r) async {
        expect(r.uri.path, '/api/v1/auth/reset-password');
        expect(r.method, 'POST');
        expect(r.headers.value('authorization'), isNull);
        expect(r.headers.value('cookie'), isNull);
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'token': token,
          'password': password,
        });
        await reply(r, 204);
      };
      await api.reset(' $token ', password);
      expect(calls, 1);
    },
  );
  for (final status in [400, 401, 422, 429, 500]) {
    test('HTTP $status never retries or leaks server text/secrets', () async {
      respond = (r) async {
        await r.drain<void>();
        r.response.headers.set('Retry-After', '30');
        await reply(r, status, {
          'error': {
            'code': status == 422
                ? 'validation_failed'
                : status == 429
                ? 'rate_limited'
                : 'invalid_request',
            'message': 'secret server token and password',
          },
          'requestId': 'synthetic',
        });
      };
      try {
        await api.reset('A' * 43, 'Synthetic password');
        fail('Expected failure');
      } on PasswordResetApiException catch (e) {
        expect(e.message, isNot(contains('secret server')));
        expect(e.toString(), 'PasswordResetApiException');
        if (status == 429) expect(e.retryAfter, const Duration(seconds: 30));
        if (status == 422) {
          expect(e.message, contains('süresi dolmuş veya kullanılmış'));
        }
      }
      expect(calls, 1);
    });
  }
  test('a nonempty 202 is not accepted as success', () async {
    respond = (r) => reply(r, 202, {'token': 'must not be accepted'});
    await expectLater(
      api.request('synthetic@example.test'),
      throwsA(isA<PasswordResetApiException>()),
    );
    expect(calls, 1);
  });
  test('timeout is uncertain and never replays a mutation', () async {
    final pending = Completer<void>();
    respond = (r) async {
      await pending.future;
    };
    final short = PasswordResetApi(
      baseUri: api.baseUri,
      timeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      short.reset('A' * 43, 'Synthetic password'),
      throwsA(
        isA<PasswordResetApiException>().having(
          (e) => e.message,
          'uncertain result',
          contains('tamamlanmış olabilir'),
        ),
      ),
    );
    expect(calls, 1);
    pending.complete();
  });
}
