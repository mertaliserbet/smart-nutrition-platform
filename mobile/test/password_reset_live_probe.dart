// Opt-in HTTPS/PostgreSQL/Mailpit proof using only disposable synthetic accounts.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/password_reset_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'M5: request, Mailpit code, reset, login, old-session invalidation and expiry',
    () async {
      final db = Platform.environment['SNP_RESET_TEST_DATABASE']!;
      expect(RegExp(r'^m5_verify_\d+$').hasMatch(db), isTrue);
      final origin = Uri.parse('https://localhost:7101');
      final mailOrigin = Uri.parse('http://127.0.0.1:8025');
      Future<String> sql(String text) async {
        final r = await Process.run('docker', [
          'exec',
          'smart-nutrition-postgres',
          'psql',
          '-X',
          '-v',
          'ON_ERROR_STOP=1',
          '-U',
          'smart_nutrition',
          '-d',
          db,
          '-Atqc',
          text,
        ]);
        expect(r.exitCode, 0, reason: 'Isolated synthetic fixture operation');
        return r.stdout.toString().trim();
      }

      expect(
        await sql(
          "SELECT DISTINCT datname FROM pg_stat_activity WHERE application_name='m5-live-verify'",
        ),
        db,
      );
      final email =
          'synthetic-m5-${DateTime.now().microsecondsSinceEpoch}@example.test';
      final seen = <String>{};
      final http = HttpClient();
      Future<dynamic> mail(
        String path, {
        String method = 'GET',
        Object? body,
      }) async {
        final r = await http.openUrl(method, mailOrigin.resolve(path));
        if (body != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(body));
        }
        final response = await r.close().timeout(const Duration(seconds: 10));
        final content = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('Mailpit request failed');
        }
        return content.isEmpty || method == 'DELETE'
            ? null
            : jsonDecode(content);
      }

      Future<String> findMail(String subject) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          final page = await mail(
            '/api/v1/search?${Uri(queryParameters: {'query': 'to:$email'}).query}',
          );
          for (final row in page['messages'] as List) {
            final id = row['ID'] as String;
            if (!(row['Subject'] as String).contains(subject) ||
                seen.contains(id)) {
              continue;
            }
            final detail = await mail('/api/v1/message/$id');
            seen.add(id);
            return detail['Text'] as String;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('Synthetic Mailpit message was not delivered');
      }

      String code(String text) => text
          .split('\n')
          .map((s) => s.trim())
          .singleWhere((line) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(line));
      const oldPassword = 'Synthetic M5 old password 2026!';
      const newPassword = 'Synthetic M5 new password 2026!';
      final reset = PasswordResetApi(baseUri: origin);
      final login = LoginApi(baseUri: origin);
      final session = AuthSession(api: login, store: WaterMemoryStore());
      try {
        final registration = await requestJson(
          method: 'POST',
          path: '/api/v1/auth/register',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
          payload: {
            'email': email,
            'password': oldPassword,
            'displayName': 'Synthetic M5 account',
            'role': 'client',
          },
        );
        expect(registration.statusCode, 201);
        final id = (registration.body as Map)['id'] as String;
        expect(RegExp(r'^[a-f0-9-]{36}$').hasMatch(id), isTrue);
        await sql("UPDATE users SET is_email_verified=true WHERE id='$id'");
        final old = await login.login(email: email, password: oldPassword);
        await session.initialize();
        expect(
          await session.signIn(email: email, password: oldPassword),
          isTrue,
        );
        await reset.request(email);
        final message = await findMail('Parola sıfırlama');
        expect(message.contains('30 dakika'), isTrue);
        final token = code(message);
        await reset.request(
          'synthetic-missing-${DateTime.now().microsecondsSinceEpoch}@example.test',
        );
        await expectLater(
          reset.reset('B' * 43, newPassword),
          throwsA(isA<PasswordResetApiException>()),
        );
        await reset.reset(token, newPassword);
        await findMail('Parolanız değiştirildi');
        await expectLater(
          reset.reset(token, newPassword),
          throwsA(isA<PasswordResetApiException>()),
        );
        await expectLater(
          login.login(email: email, password: oldPassword),
          throwsA(isA<LoginApiException>()),
        );
        final denied = await requestJson(
          method: 'GET',
          path: '/api/v1/auth/me',
          accessToken: old.accessToken,
          baseUri: origin,
          timeout: const Duration(seconds: 20),
        );
        expect(denied.statusCode, 401);
        await expectLater(
          login.refresh(old.refreshToken),
          throwsA(isA<LoginApiException>()),
        );
        await session.refresh();
        expect(session.isAuthenticated, isFalse);
        expect(
          await session.signIn(email: email, password: newPassword),
          isTrue,
        );
        await sql(
          "UPDATE users SET password_reset_last_sent_at=now()-interval '2 minutes' WHERE id='$id'",
        );
        await reset.request(email);
        final expired = code(await findMail('Parola sıfırlama'));
        await sql(
          "UPDATE users SET password_reset_last_sent_at=now()-interval '31 minutes', password_reset_expires_at=now()-interval '1 second' WHERE id='$id'",
        );
        await expectLater(
          reset.reset(expired, oldPassword),
          throwsA(isA<PasswordResetApiException>()),
        );
        await File('build/m5-live/result.json').writeAsString(
          jsonEncode({
            'httpsPostgresqlMailpit': true,
            'syntheticOnly': true,
            'requestAndDelivery': true,
            'newPasswordLogin': true,
            'oldAccessRefreshAndSessionRejected': true,
            'usedInvalidExpiredCodeRejected': true,
            'unknownEmailSameAcceptedResult': true,
            'deepLink': false,
          }),
        );
      } finally {
        if (session.isAuthenticated) await session.signOut();
        session.dispose();
        final page = await mail(
          '/api/v1/search?${Uri(queryParameters: {'query': 'to:$email'}).query}',
        );
        final ids = (page['messages'] as List)
            .map((r) => r['ID'] as String)
            .toList();
        if (ids.isNotEmpty) {
          await mail('/api/v1/messages', method: 'DELETE', body: {'IDs': ids});
        }
        http.close(force: true);
      }
    },
    skip: Platform.environment['SNP_RESET_LIVE'] != '1',
  );
}
