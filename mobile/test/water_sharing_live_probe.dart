// Opt-in real Flutter sharing client + HTTPS + isolated PostgreSQL.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'M4: water consent grants expert read; revoke preserves four categories',
    () async {
      final db = Platform.environment['SNP_WATER_SHARING_DATABASE']!;
      expect(RegExp(r'^m4_verify_\d+$').hasMatch(db), isTrue);
      final origin = Uri.parse('https://localhost:7101');
      Future<String> sql(String statement) async {
        final p = await Process.run('docker', [
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
          statement,
        ]);
        expect(p.exitCode, 0, reason: 'Isolated synthetic fixture operation');
        return p.stdout.toString().trim();
      }

      expect(
        await sql(
          "SELECT DISTINCT datname FROM pg_stat_activity WHERE application_name='m4-live-verify'",
        ),
        db,
      );
      const password = 'Synthetic M4 sharing password 2026!';
      final tag = DateTime.now().microsecondsSinceEpoch;
      Future<({String email, String id})> register(
        String label, {
        bool expert = false,
      }) async {
        final email = 'synthetic-m4-$label-$tag@example.test';
        final r = await requestJson(
          method: 'POST',
          path: expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic M4 account',
            if (expert)
              'licenseInfo': 'Synthetic license'
            else
              'role': 'client',
          },
        );
        expect(r.statusCode, 201);
        final id = (r.body as Map)['id'] as String;
        expect(RegExp(r'^[a-f0-9-]{36}$').hasMatch(id), isTrue);
        await sql("UPDATE users SET is_email_verified=true WHERE id='$id'");
        if (expert) {
          await sql(
            "UPDATE dietitian_profiles SET is_verified=true WHERE user_id='$id'",
          );
        }
        return (email: email, id: id);
      }

      final owner = await register('owner'),
          expertUser = await register('expert', expert: true);
      final outsider = await register('outsider');
      final expertId = await sql(
        "SELECT id FROM dietitian_profiles WHERE user_id='${expertUser.id}'",
      );
      final client = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      final expert = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      await client.initialize();
      await expert.initialize();
      try {
        expect(
          await client.signIn(email: owner.email, password: password),
          isTrue,
        );
        expect(
          await expert.signIn(email: expertUser.email, password: password),
          isTrue,
        );
        final permissions = DietitianApi(client);
        final pending = await permissions.request(dietitianId: expertId);
        await expectLater(
          permissions.setPermission(
            relationshipId: pending.id,
            category: 'water_logs',
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'pending',
              409,
            ),
          ),
        );
        final active = await DietitianApi(
          expert,
        ).changeRelationship(pending, 'accept', asDietitian: true);
        expect(await permissions.permissions(active.id), isEmpty);
        final logApi = WaterLogApi(client);
        final water = await logApi.create(
          amountMl: 250.125,
          consumedAt: DateTime(2026, 10, 20, 10),
        );
        final root = '/api/v1/dietitian/clients/${active.clientId}/water-logs';
        Future<JsonApiResponse> read(String path) =>
            expert.authorizedRequest(path: path, profileContext: 'dietitian');
        final listPath = '$root?page=1&pageSize=10';
        expect((await read(listPath)).statusCode, 403);
        for (final category in DietitianApi.sharingCategories.where(
          (x) => x != 'water_logs',
        )) {
          await permissions.setPermission(
            relationshipId: active.id,
            category: category,
            isGranted: true,
          );
        }
        final before = {
          for (final p in await permissions.permissions(active.id))
            p.category: p.id,
        };
        expect(before.length, 4);
        expect((await read(listPath)).statusCode, 403);
        var grant = await permissions.setPermission(
          relationshipId: active.id,
          category: 'water_logs',
          isGranted: true,
        );
        var rows = await permissions.permissions(active.id);
        expect(rows.length, 5);
        expect(rows.every((p) => p.isGranted), isTrue);
        var readback = await read(listPath);
        expect(readback.statusCode, 200);
        expect((readback.body as Map)['totalCount'], 1);
        expect((readback.body as Map)['items'][0]['id'], water.id);
        expect((readback.body as Map)['items'][0]['amountMl'], 250.125);
        final range = WaterDayRange.forDate(DateTime(2026, 10, 20));
        final totalPath =
            '$root/daily-total?${Uri(queryParameters: range.query).query}';
        expect(((await read(totalPath)).body as Map)['totalAmountMl'], 250.125);
        grant = await permissions.setPermission(
          relationshipId: active.id,
          category: 'water_logs',
          current: grant,
          isGranted: false,
        );
        expect((await read(listPath)).statusCode, 403);
        expect((await read(totalPath)).statusCode, 403);
        rows = await permissions.permissions(active.id);
        for (final row in rows.where((p) => p.category != 'water_logs')) {
          expect(row.id, before[row.category]);
          expect(row.isGranted, isTrue);
        }
        expect((await logApi.get(water.id)).amountMl, 250.125);
        await expectLater(
          DietitianApi(expert).setPermission(
            relationshipId: active.id,
            category: 'water_logs',
            current: grant,
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'expert cannot grant',
              403,
            ),
          ),
        );
        grant = await permissions.setPermission(
          relationshipId: active.id,
          category: 'water_logs',
          current: grant,
          isGranted: true,
        );
        expect((await read(listPath)).statusCode, 200);
        await permissions.endRelationship(active);
        expect((await read(listPath)).statusCode, 404);
        await expectLater(
          permissions.setPermission(
            relationshipId: active.id,
            category: 'water_logs',
            current: grant,
            isGranted: true,
          ),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'ended',
              409,
            ),
          ),
        );
        await client.signOut();
        expect(
          await client.signIn(email: outsider.email, password: password),
          isTrue,
        );
        await expectLater(
          permissions.permissions(active.id),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'other account',
              404,
            ),
          ),
        );
        final anonymous = await requestJson(
          method: 'GET',
          path: listPath,
          baseUri: origin,
          timeout: const Duration(seconds: 20),
        );
        expect(anonymous.statusCode, 401);
        await File('build/m4-live/live-result.txt').writeAsString(
          'Passed: real Flutter API, HTTPS/PostgreSQL; default deny, five categories, water grant/read/revoke, other grants preserved, relationship end, account isolation.',
        );
      } finally {
        if (client.isAuthenticated) await client.signOut();
        if (expert.isAuthenticated) await expert.signOut();
        client.dispose();
        expert.dispose();
      }
    },
    skip: Platform.environment['SNP_WATER_SHARING_LIVE'] != '1',
  );
}
