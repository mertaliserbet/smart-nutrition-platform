// Opt-in real HTTPS probe; fixtures exist only in a disposable PostgreSQL.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_comment_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'real HTTPS: read expert root, reply as owner, page history and keep own access after withdrawal',
    () async {
      final container = Platform.environment['SNP_SHARING_CONTAINER']!;
      expect(
        RegExp(r'^smart-nutrition-sharing-test-\d+$').hasMatch(container),
        isTrue,
      );
      final origin = Uri.parse('https://localhost:7101'),
          suffix = DateTime.now().microsecondsSinceEpoch;
      final clientEmail = 'synthetic-sharing-client-$suffix@example.test',
          expertEmail = 'synthetic-sharing-expert-$suffix@example.test';
      const password = 'Synthetic mobile comment integration password';
      Future<String> register(String email, bool expert) async {
        final response = await requestJson(
          method: 'POST',
          path: expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic comment account',
            if (expert)
              'licenseInfo': 'Synthetic license'
            else
              'role': 'client',
          },
        );
        expect(response.statusCode, 201);
        return (response.body as Map)['id'] as String;
      }

      final clientId = await register(clientEmail, false),
          expertUser = await register(expertEmail, true);
      expect(
        RegExp(r'^[a-f0-9-]{36}$').hasMatch(clientId) &&
            RegExp(r'^[a-f0-9-]{36}$').hasMatch(expertUser),
        isTrue,
      );
      final seeded = await Process.run('docker', [
        'exec',
        container,
        'psql',
        '-U',
        'sharing_test',
        '-d',
        'sharing_test',
        '-Atc',
        "UPDATE users SET is_email_verified=true WHERE id IN ('$clientId','$expertUser'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='$expertUser'; SELECT id FROM dietitian_profiles WHERE user_id='$expertUser';",
      ]);
      expect(seeded.exitCode, 0);
      final expertId = seeded.stdout.toString().trim().split('\n').last.trim();
      final client = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      final expert = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      try {
        await client.initialize();
        await expert.initialize();
        expect(
          await client.signIn(email: clientEmail, password: password),
          isTrue,
        );
        expect(
          await expert.signIn(email: expertEmail, password: password),
          isTrue,
        );
        final links = DietitianApi(client);
        final pending = await links.request(dietitianId: expertId);
        final relationship = await DietitianApi(
          expert,
        ).changeRelationship(pending, 'accept', asDietitian: true);
        final grant = await links.setPermission(
          relationshipId: relationship.id,
          category: 'meal_logs',
          isGranted: true,
        );
        final meals = MealLogApi(client);
        final meal = await meals.create({
          'mealType': 'lunch',
          'consumedAt': '2026-11-18T12:00:00Z',
          'source': 'manual',
          'items': [
            {'displayName': 'Synthetic comment meal', 'isEstimated': false},
          ],
        });
        final comments = MealLogCommentApi(client);
        expect((await comments.list(meal.id)).totalCount, 0);
        final created = await expert.authorizedRequest(
          path: '/api/v1/meal-logs/${meal.id}/comments',
          method: 'POST',
          profileContext: 'dietitian',
          payload: {'text': 'Sentetik gerçek diyetisyen yorumu'},
        );
        expect(created.statusCode, 201);
        final root = (await comments.list(meal.id)).items.single;
        expect(root.isRoot, isTrue);
        expect(root.authorUserId, expertUser);
        final reply = await comments.reply(
          meal.id,
          root,
          '  Sentetik mobil yanıt 10  ',
        );
        expect(reply.parentCommentId, root.id);
        expect(reply.authorUserId, clientId);
        expect(reply.text, 'Sentetik mobil yanıt 10');
        final history = await comments.list(meal.id);
        expect(history.totalCount, 2);
        expect(history.items.map((row) => row.id), [root.id, reply.id]);
        expect((await comments.list(meal.id, page: 2)).items, isEmpty);
        await links.setPermission(
          relationshipId: relationship.id,
          category: 'meal_logs',
          current: grant,
          isGranted: false,
        );
        expect((await comments.list(meal.id)).totalCount, 2);
        await comments.reply(
          meal.id,
          root,
          'Paylaşım kapandıktan sonra kendi yanıtım',
        );
        final denied = await expert.authorizedRequest(
          path: '/api/v1/meal-logs/${meal.id}/comments?page=1&pageSize=10',
          profileContext: 'dietitian',
        );
        expect(denied.statusCode, 403);
        await expectLater(
          comments.reply(meal.id, reply, 'Yanıtın yanıtı'),
          throwsA(isA<MealLogCommentApiException>()),
        );
        await meals.delete(meal.id);
        await expectLater(
          comments.list(meal.id),
          throwsA(
            isA<MealLogCommentApiException>().having(
              (error) => error.statusCode,
              'deleted',
              404,
            ),
          ),
        );
      } finally {
        if (client.isAuthenticated) {
          await client.signOut();
        }
        if (expert.isAuthenticated) {
          await expert.signOut();
        }
        client.dispose();
        expert.dispose();
      }
    },
    skip: Platform.environment['SNP_MOBILE_COMMENT_LIVE'] != '1',
  );
}
