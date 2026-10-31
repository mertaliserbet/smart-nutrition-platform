import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';

const testToken = 'syntheticHeader.syntheticPayload.syntheticSignature';
const userId = '41111111-1111-4111-8111-111111111111';
Map<String, Object?> validUser() => {
  'id': userId,
  'displayName': null,
  'email': 'synthetic@example.test',
  'role': 'client',
  'isEmailVerified': true,
};
Map<String, Object?> validLogin() => {
  'accessToken': testToken,
  'tokenType': 'Bearer',
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 15))
      .toIso8601String(),
};

void main() {
  late HttpServer server;
  late LoginApi api;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}'));
  });
  tearDown(() async => server.close(force: true));

  test(
    'login sends only email/password; preserves Unicode and password whitespace',
    () async {
      final captured = Completer<Map<String, Object?>>();
      server.listen((request) async {
        captured.complete({
          'method': request.method,
          'path': request.uri.toString(),
          'body': jsonDecode(await utf8.decoder.bind(request).join()),
          'authorization': request.headers.value(
            HttpHeaders.authorizationHeader,
          ),
          'cookie': request.headers.value(HttpHeaders.cookieHeader),
          'contentType': request.headers.contentType?.mimeType,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(validLogin()));
        await request.response.close();
      });
      const password = '  Şifre😀e\u0301  ';
      final login = await api.login(
        email: ' synthetic@example.test ',
        password: password,
      );
      expect(login.accessToken, testToken);
      expect(login.expiresAt.isUtc, isTrue);
      expect(await captured.future, {
        'method': 'POST',
        'path': '/api/v1/auth/login',
        'body': {'email': 'synthetic@example.test', 'password': password},
        'authorization': null,
        'cookie': null,
        'contentType': 'application/json',
      });
    },
  );

  test(
    '/me uses GET with bearer only, no body/query/cookie; nullable name remains null',
    () async {
      final captured = Completer<Map<String, Object?>>();
      server.listen((request) async {
        captured.complete({
          'method': request.method,
          'path': request.uri.toString(),
          'body': await utf8.decoder.bind(request).join(),
          'authorization': request.headers.value(
            HttpHeaders.authorizationHeader,
          ),
          'cookie': request.headers.value(HttpHeaders.cookieHeader),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(validUser()));
        await request.response.close();
      });
      final user = await api.currentUser(testToken);
      expect(user.id, userId);
      expect(user.displayName, isNull);
      expect(user.role, 'client');
      expect(user.isEmailVerified, isTrue);
      expect(await captured.future, {
        'method': 'GET',
        'path': '/api/v1/auth/me',
        'body': '',
        'authorization': 'Bearer $testToken',
        'cookie': null,
      });
    },
  );

  for (final entry in [
    (401, 'unauthenticated', 'Giriş yapılamadı'),
    (400, 'invalid_request', 'alanlarını kontrol'),
    (429, 'rate_limited', 'Çok fazla'),
    (500, 'internal_error', 'şu anda kullanılamıyor'),
    (302, 'redirect', 'yanıtı doğrulanamadı'),
    (201, 'created', 'yanıtı doğrulanamadı'),
  ]) {
    for (final login in [true, false]) {
      test(
        '${login ? 'login' : 'me'} ${entry.$1} is safe, never redirects/retries',
        () async {
          var requests = 0;
          server.listen((request) async {
            requests++;
            await request.drain<void>();
            request.response
              ..statusCode = entry.$1
              ..headers.contentType = ContentType.json
              ..headers.set(HttpHeaders.locationHeader, '/leak')
              ..write(
                jsonEncode({
                  'error': {
                    'code': entry.$2,
                    'message': 'secret $testToken',
                    'details': {'password': 'private'},
                  },
                  'requestId': 'synthetic',
                }),
              );
            await request.response.close();
          });
          try {
            if (login) {
              await api.login(
                email: 'synthetic@example.test',
                password: 'secret',
              );
            } else {
              await api.currentUser(testToken);
            }
            fail('Unexpected authenticated response');
          } on LoginApiException catch (error) {
            expect(error.message, contains(entry.$3));
            expect(error.message, isNot(contains(testToken)));
            expect(error.toString(), 'LoginApiException');
            expect(error.unauthorized, entry.$1 == 401);
          }
          expect(requests, 1);
        },
      );
    }
  }

  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'missing expiry': (body) => body.remove('expiresAt'),
    'wrong bearer type': (body) => body['tokenType'] = 'bearer',
    'blank token': (body) => body['accessToken'] = '',
    'non JWT token': (body) => body['accessToken'] = 'opaque',
    'bad expiry': (body) => body['expiresAt'] = 'not-a-dateZ',
    'non UTC expiry': (body) => body['expiresAt'] = '2026-10-31T16:00:00+03:00',
    'extra field': (body) => body['refreshToken'] = 'private',
  }.entries) {
    test('malformed login response: ${mutation.key}', () async {
      server.listen((request) async {
        await request.drain<void>();
        final body = validLogin();
        mutation.value(body);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      await expectLater(
        api.login(email: 'synthetic@example.test', password: 'secret'),
        throwsA(isA<LoginApiException>()),
      );
    });
  }

  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'unverified': (body) => body['isEmailVerified'] = false,
    'admin': (body) => body['role'] = 'admin',
    'unknown role': (body) => body['role'] = 'owner',
    'missing name': (body) => body.remove('displayName'),
    'invalid uuid': (body) => body['id'] = 'wrong',
    'wrong verified type': (body) => body['isEmailVerified'] = 'true',
    'extra field': (body) => body['passwordHash'] = 'private',
  }.entries) {
    test('me cannot open the gate with ${mutation.key}', () async {
      server.listen((request) async {
        await request.drain<void>();
        final body = validUser();
        mutation.value(body);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      await expectLater(
        api.currentUser(testToken),
        throwsA(isA<LoginApiException>()),
      );
    });
  }

  test('malformed 200 response is never a successful login', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{broken');
      await request.response.close();
    });
    await expectLater(
      api.login(email: 'synthetic@example.test', password: 'secret'),
      throwsA(isA<LoginApiException>()),
    );
  });

  test('401 invalidates before a stalled error body completes', () async {
    var invalidated = false;
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 401;
      request.response.write('{');
      await request.response.flush();
    });
    api = LoginApi(
      baseUri: api.baseUri,
      timeout: const Duration(milliseconds: 200),
    );
    await expectLater(
      api.currentUser(testToken, onUnauthorized: () => invalidated = true),
      throwsA(isA<LoginApiException>()),
    );
    expect(invalidated, isTrue);
  });

  for (final login in [true, false]) {
    test(
      '${login ? 'login' : 'me'} connection refusal is a safe connection error',
      () async {
        await server.close(force: true);
        await expectLater(
          login
              ? api.login(email: 'synthetic@example.test', password: 'secret')
              : api.currentUser(testToken),
          throwsA(
            isA<LoginApiException>().having(
              (error) => error.message,
              'message',
              contains('Bağlantı'),
            ),
          ),
        );
      },
    );
  }
}
