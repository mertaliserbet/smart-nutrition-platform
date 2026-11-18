import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_api.dart';
import 'water_test_support.dart';
import 'client_task_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late ClientTaskApi api;
  late Future<void> Function(HttpRequest) resource;
  var renewals = 0;
  Future<void> reply(HttpRequest r, int status, Object? body) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  setUp(() async {
    renewals = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (r) => reply(r, 200, taskJson());
    final refreshExpiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object?> pair(int revision) => {
      'accessToken': 'synthetic.task$revision.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': String.fromCharCode(65 + revision) * 43,
      'refreshTokenExpiresAt': refreshExpiry.toIso8601String(),
    };
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': '44444444-4444-4444-8444-444444444444',
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          renewals++;
          await r.drain<void>();
          await reply(r, 200, pair(renewals));
        default:
          await resource(r);
      }
    });
    session = AuthSession(
      api: LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}')),
      store: WaterMemoryStore(),
    );
    await session.initialize();
    expect(
      await session.signIn(
        email: 'synthetic@example.test',
        password: 'Synthetic password',
      ),
      true,
    );
    api = ClientTaskApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });

  test(
    'list uses mandatory pagination, bearer and client context without clientId',
    () async {
      resource = (r) async {
        expect(r.uri.path, '/api/v1/client-tasks');
        expect(r.uri.queryParameters, {'page': '2', 'pageSize': '10'});
        expect(r.method, 'GET');
        expect(r.headers.value('x-profile-context'), 'client');
        expect(r.headers.value('authorization'), startsWith('Bearer '));
        await reply(r, 200, {
          'items': [taskJson()],
          'totalCount': 11,
        });
      };
      expect((await api.list(page: 2)).totalCount, 11);
    },
  );
  test('detail and descending version snapshots use existing paths', () async {
    resource = (r) async {
      if (r.uri.path.endsWith('/versions')) {
        expect(r.uri.queryParameters, {'page': '1', 'pageSize': '10'});
        await reply(r, 200, {
          'items': [
            {
              'id': taskExpertId,
              'clientTaskId': taskId,
              'versionNumber': 1,
              'createdAt': '2026-11-19T10:00:00Z',
              'snapshot': taskJson(),
            },
          ],
          'totalCount': 1,
        });
      } else {
        expect(r.uri.path, '/api/v1/client-tasks/$taskId');
        await reply(r, 200, taskJson());
      }
    };
    expect((await api.get(taskId)).status, ClientTaskStatus.pending);
    expect((await api.versions(taskId)).items.single.snapshot.id, taskId);
  });
  test(
    'completion sends only optimistic version and status, no owner or dates',
    () async {
      resource = (r) async {
        expect(r.method, 'PATCH');
        expect(r.headers.value('x-profile-context'), 'client');
        final payload = jsonDecode(await utf8.decoder.bind(r).join());
        expect(payload, {'expectedVersionNumber': 1, 'status': 'completed'});
        await reply(r, 200, taskJson(status: 'completed', version: 2));
      };
      expect(
        (await api.patch(
          taskSample(),
          status: ClientTaskStatus.completed,
        )).versionNumber,
        2,
      );
    },
  );
  test(
    'reminder false is explicit and omitted status remains untouched',
    () async {
      resource = (r) async {
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'expectedVersionNumber': 1,
          'isReminderEnabled': false,
        });
        await reply(r, 200, taskJson());
      };
      await api.patch(taskSample(reminder: true), isReminderEnabled: false);
    },
  );
  test(
    'GET refreshes once; PATCH 401 refreshes token without replay',
    () async {
      var reads = 0;
      resource = (r) async {
        reads++;
        await reply(r, reads == 1 ? 401 : 200, reads == 1 ? {} : taskJson());
      };
      await api.get(taskId);
      expect(reads, 2);
      expect(renewals, 1);
      var writes = 0;
      resource = (r) async {
        writes++;
        await r.drain<void>();
        await reply(r, 401, {});
      };
      await expectLater(
        api.patch(taskSample(), status: ClientTaskStatus.completed),
        throwsA(
          isA<ClientTaskApiException>().having(
            (e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(writes, 1);
      expect(renewals, 2);
    },
  );
  for (final code in [403, 404, 409, 422, 500]) {
    test('PATCH $code is reported without automatic retry', () async {
      var calls = 0;
      resource = (r) async {
        calls++;
        await r.drain<void>();
        await reply(r, code, {});
      };
      await expectLater(
        api.patch(taskSample(), status: ClientTaskStatus.completed),
        throwsA(
          isA<ClientTaskApiException>().having(
            (e) => e.statusCode,
            'status',
            code,
          ),
        ),
      );
      expect(calls, 1);
    });
  }
  test(
    'unknown status, offsetless timestamps, bad nullable and version payloads fail closed',
    () async {
      for (final change in [
        {'status': 'overdue'},
        {'createdAt': '2026-11-19T10:00:00'},
        {'versionNumber': 0},
        {'dueAt': null, 'isReminderEnabled': true},
      ]) {
        resource = (r) => reply(r, 200, {...taskJson(), ...change});
        await expectLater(
          api.get(taskId),
          throwsA(isA<ClientTaskApiException>()),
        );
      }
    },
  );
  test('unsupported transitions never issue HTTP writes', () async {
    var calls = 0;
    resource = (r) async {
      calls++;
      await reply(r, 200, {});
    };
    await expectLater(
      api.patch(taskSample(), status: ClientTaskStatus.cancelled),
      throwsA(isA<ClientTaskApiException>()),
    );
    await expectLater(
      api.patch(
        taskSample(status: ClientTaskStatus.completed),
        status: ClientTaskStatus.inProgress,
      ),
      throwsA(isA<ClientTaskApiException>()),
    );
    expect(calls, 0);
  });
  test('malformed successful write is uncertain; no replay', () async {
    var calls = 0;
    resource = (r) async {
      calls++;
      await r.drain<void>();
      await reply(r, 200, {});
    };
    await expectLater(
      api.patch(taskSample(), status: ClientTaskStatus.completed),
      throwsA(
        isA<ClientTaskApiException>().having(
          (e) => e.uncertain,
          'uncertain',
          true,
        ),
      ),
    );
    expect(calls, 1);
  });
}
