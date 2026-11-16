// Opt-in local HTTPS probe. No stored credentials or TLS bypass.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';

void main() {
  test(
    'real HTTPS: register/verify/login and meal create/list/detail/edit/delete',
    () async {
      final origin = Uri.parse('https://localhost:7099');
      final email =
          'synthetic-meal-live-${DateTime.now().microsecondsSinceEpoch}@example.test';
      final password = base64UrlEncode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      final result = <String, Object?>{
        'email': email,
        'messageIds': <String>[],
      };
      final resultFile = File(Platform.environment['SNP_MEAL_RESULT']!);
      final mail = HttpClient();
      final session = AuthSession(
        api: LoginApi(baseUri: origin),
        store: _Store(),
      );
      Future<void> saveResult() => resultFile.writeAsString(jsonEncode(result));
      Future<Map<String, dynamic>> mailbox(String path) async {
        final response = await (await mail.getUrl(
          Uri.parse('http://127.0.0.1:8025$path'),
        )).close();
        expect(response.statusCode, 200);
        return jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
      }

      try {
        final registered = await requestJson(
          method: 'POST',
          path: '/api/v1/auth/register',
          baseUri: origin,
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Sentetik öğün HTTPS testi',
          },
          timeout: const Duration(seconds: 20),
        );
        expect(registered.statusCode, 201);
        result['userId'] = (registered.body as Map)['id'];
        await saveResult();
        String? token;
        for (var attempt = 0; attempt < 100 && token == null; attempt++) {
          final found = await mailbox(
            '/api/v1/search?query=${Uri.encodeQueryComponent('to:$email')}',
          );
          for (final message in found['messages'] as List) {
            final id = (message as Map)['ID'] as String;
            final detail = await mailbox(
              '/api/v1/message/${Uri.encodeComponent(id)}',
            );
            final candidates = (detail['Text'] as String)
                .split('\n')
                .map((s) => s.trim())
                .where((s) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(s));
            if (candidates.isNotEmpty) {
              token = candidates.single;
              (result['messageIds'] as List<String>).add(id);
              break;
            }
          }
          if (token == null) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        await saveResult();
        expect(
          token != null,
          isTrue,
          reason: 'Synthetic verification mail not received.',
        );
        final verified = await requestJson(
          method: 'POST',
          path: '/api/v1/auth/verify-email',
          baseUri: origin,
          payload: {'token': token!},
          timeout: const Duration(seconds: 20),
        );
        expect(verified.statusCode, 204);
        await session.initialize();
        expect(await session.signIn(email: email, password: password), isTrue);
        final api = MealLogApi(session);
        expect((await api.list()).totalCount, 0);
        final body = <String, Object?>{
          'mealType': 'lunch',
          'consumedAt': DateTime.now().toUtc().toIso8601String(),
          'source': 'manual',
          'note': 'Sentetik canlı test',
          'items': [
            <String, Object?>{
              'displayName': 'Sentetik mercimek çorbası',
              'isEstimated': true,
              'quantityGrams': 125.5,
              'caloriesKcal': 0,
              'proteinGrams': 12.5,
              'carbsGrams': null,
              'fatGrams': 0,
            },
          ],
        };
        final created = await api.create(body);
        result['mealId'] = created.id;
        await saveResult();
        expect((await api.list()).items.single.id, created.id);
        expect((await api.get(created.id)).items.single.quantityGrams, 125.5);
        final changedItem = Map<String, Object?>.from(
          (body['items'] as List).single as Map,
        )..['proteinGrams'] = 14.75;
        await api.update(created.id, {
          'note': 'Sentetik düzenlenmiş not',
          'items': [changedItem],
        });
        expect((await api.get(created.id)).items.single.proteinGrams, 14.75);
        await api.delete(created.id);
        expect((await api.list()).totalCount, 0);
        await expectLater(
          api.get(created.id),
          throwsA(
            isA<MealLogApiException>().having(
              (e) => e.statusCode,
              'status',
              404,
            ),
          ),
        );
        result['passed'] = true;
        await saveResult();
      } finally {
        if (session.isAuthenticated) await session.signOut();
        session.dispose();
        mail.close(force: true);
        await saveResult();
      }
    },
    skip: Platform.environment['SNP_MEAL_PROBE'] != '1',
  );
}

class _Store implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
