// Opt-in real Flutter task API regression; only the disposable M6 database.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'water_test_support.dart';

void main() {
  test(
    'HTTPS tasks: assign, mobile transitions/history, revoke and account isolation',
    () async {
      final db = Platform.environment['SNP_M6_DATABASE']!;
      expect(RegExp(r'^m6_verify_\d+$').hasMatch(db), isTrue);
      final origin = Uri.parse('https://localhost:7101');
      Future<String> sql(String query) async {
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
          query,
        ]);
        expect(r.exitCode, 0, reason: 'Isolated task fixture operation');
        return r.stdout.toString().trim();
      }

      expect(
        await sql(
          "SELECT DISTINCT datname FROM pg_stat_activity WHERE application_name='m6-live-verify'",
        ),
        db,
      );
      final tag = DateTime.now().microsecondsSinceEpoch;
      const password = 'Synthetic M6 task password 2026!';
      Future<({String email, String id})> register(
        String label, {
        bool expert = false,
      }) async {
        final email = 'synthetic-m6-task-$label-$tag@example.test';
        final r = await requestJson(
          method: 'POST',
          path: expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic M6 task account',
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

      final a = await register('owner'),
          b = await register('other'),
          d = await register('expert', expert: true);
      final expertId = await sql(
        "SELECT id FROM dietitian_profiles WHERE user_id='${d.id}'",
      );
      final owner = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      final expert = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      await owner.initialize();
      await expert.initialize();
      try {
        expect(await owner.signIn(email: a.email, password: password), isTrue);
        expect(await expert.signIn(email: d.email, password: password), isTrue);
        final sharing = DietitianApi(owner), tasks = ClientTaskApi(owner);
        expect((await tasks.list()).totalCount, 0);
        final pending = await sharing.request(dietitianId: expertId);
        final active = await DietitianApi(
          expert,
        ).changeRelationship(pending, 'accept', asDietitian: true);
        final path =
            '/api/v1/client-tasks?page=1&pageSize=10&clientId=${active.clientId}';
        expect(
          (await expert.authorizedRequest(
            path: path,
            profileContext: 'dietitian',
          )).statusCode,
          403,
        );
        var grant = await sharing.setPermission(
          relationshipId: active.id,
          category: 'client_tasks',
          isGranted: true,
        );
        final assigned = await expert.authorizedRequest(
          path: '/api/v1/client-tasks',
          method: 'POST',
          profileContext: 'dietitian',
          payload: {
            'clientId': active.clientId,
            'description': 'Synthetic M6 mobile task',
            'dueAt': DateTime.now()
                .toUtc()
                .add(const Duration(days: 2))
                .toIso8601String(),
          },
        );
        expect(assigned.statusCode, 201);
        var task = (await tasks.list()).items.single;
        expect(task.status, ClientTaskStatus.pending);
        expect(task.dueAt, isNotNull);
        task = await tasks.patch(task, status: ClientTaskStatus.inProgress);
        task = await tasks.patch(task, status: ClientTaskStatus.completed);
        expect(task.versionNumber, 3);
        expect((await tasks.versions(task.id)).items.length, 3);
        final readback = await expert.authorizedRequest(
          path: '/api/v1/client-tasks/${task.id}',
          profileContext: 'dietitian',
        );
        expect((readback.body as Map)['status'], 'completed');
        grant = await sharing.setPermission(
          relationshipId: active.id,
          category: 'client_tasks',
          current: grant,
          isGranted: false,
        );
        expect(
          (await expert.authorizedRequest(
            path: path,
            profileContext: 'dietitian',
          )).statusCode,
          403,
        );
        expect((await tasks.get(task.id)).status, ClientTaskStatus.completed);
        await owner.signOut();
        expect(await owner.signIn(email: b.email, password: password), isTrue);
        expect((await tasks.list()).totalCount, 0);
        await expectLater(
          tasks.get(task.id),
          throwsA(
            isA<ClientTaskApiException>().having(
              (e) => e.statusCode,
              'other client',
              404,
            ),
          ),
        );
        await File('build/m6/tasks-result.txt').writeAsString(
          'Passed: real Flutter task list/detail/transitions/history, dueAt, expert readback, revoked consent and account isolation.',
        );
      } finally {
        if (owner.isAuthenticated) await owner.signOut();
        if (expert.isAuthenticated) await expert.signOut();
        owner.dispose();
        expert.dispose();
      }
    },
    skip: Platform.environment['SNP_TASK_LIVE'] != '1',
  );
}
