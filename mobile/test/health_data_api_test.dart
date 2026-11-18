import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/health/health_data_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'health_sync_test_support.dart';
import 'water_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late HealthDataApi api;
  late Future<void> Function(HttpRequest) resource;
  var renewals = 0;
  Future<void> reply(HttpRequest r, int status, Object? body) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  Map<String, Object?> connection({String status = 'active'}) => {
    'id': healthConnectionId,
    'clientId': healthClientId,
    'provider': 'health_connect',
    'status': status,
    'versionNumber': 1,
    'lastSyncedAt': null,
    'lastAttemptAt': null,
    'lastSyncStatus': 'never',
    'lastErrorCode': null,
  };
  Map<String, Object?> record() => {
    'id': healthClientId,
    'clientId': healthClientId,
    'wearableConnectionId': healthConnectionId,
    'provider': 'health_connect',
    'metric': 'steps',
    'sourceId': 'native source + exact',
    'externalRecordId': 'native-record',
    'rawType': 'STEPS',
    'rawUnit': 'COUNT',
    'sourceName': 'Synthetic',
    'recordingMethod': '2',
    'exerciseType': null,
    'versionNumber': 2,
    'isDeleted': false,
    'updatedAt': '2026-11-19T12:00:00Z',
  };
  Map<String, Object?> batch() => {
    'wearableConnectionId': healthConnectionId,
    'batchId': '33333333-3333-4333-8333-333333333333',
    'changes': [
      {
        'operation': 'upsert',
        'metric': 'steps',
        'sourceId': 'native source + exact',
        'externalRecordId': 'native-record',
        'rawType': 'STEPS',
        'rawUnit': 'COUNT',
        'sourceName': 'Synthetic',
        'recordingMethod': '2',
        'expectedVersionNumber': 1,
        'samples': [
          {
            'startedAt': '2026-11-19T08:00:00Z',
            'endedAt': '2026-11-19T08:01:00Z',
            'rawValue': 20,
          },
        ],
      },
    ],
  };
  setUp(() async {
    renewals = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (r) => reply(r, 200, connection());
    final expiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object?> pair(int n) => {
      'accessToken': 'synthetic.health$n.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': String.fromCharCode(65 + n) * 43,
      'refreshTokenExpiresAt': expiry.toIso8601String(),
    };
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': '44444444-4444-4444-8444-444444444444',
            'displayName': 'Synthetic',
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
    api = HealthDataApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'connection POST sends only provider; revoked state is never auto activated',
    () async {
      resource = (r) async {
        expect(r.method, 'POST');
        expect(r.uri.path, '/api/v1/wearable-connections');
        expect(r.headers.value('x-profile-context'), 'client');
        expect(r.headers.value('authorization'), startsWith('Bearer '));
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'provider': 'health_connect',
        });
        await reply(r, 200, connection(status: 'revoked'));
      };
      expect((await api.connect('health_connect')).status, 'revoked');
    },
  );
  test(
    'source lookup encodes exact native identity and includes tombstones',
    () async {
      resource = (r) async {
        expect(
          r.uri.path,
          '/api/v1/wearable-connections/$healthConnectionId/records',
        );
        expect(r.uri.queryParameters, {
          'page': '1',
          'pageSize': '100',
          'sourceId': 'native source + exact',
          'rawType': 'STEPS',
          'externalRecordId': 'native-record',
        });
        await reply(r, 200, {
          'items': [
            {...record(), 'isDeleted': true},
          ],
          'totalCount': 1,
        });
      };
      expect(
        (await api.record(
          healthConnectionId,
          'native source + exact',
          'STEPS',
          'native-record',
        ))!.isDeleted,
        true,
      );
    },
  );
  test(
    'sync envelope and receipt retain batch identity without clientId',
    () async {
      final payload = batch();
      resource = (r) async {
        expect(r.method, 'POST');
        expect(r.uri.path, '/api/v1/wearable-connections/sync');
        expect(jsonDecode(await utf8.decoder.bind(r).join()), payload);
        await reply(r, 200, {
          'batchId': payload['batchId'],
          'wearableConnectionId': healthConnectionId,
          'committedAt': '2026-11-19T12:00:00Z',
          'records': [record()],
        });
      };
      expect((await api.sync(payload)).batchId, payload['batchId']);
    },
  );
  test(
    'status PATCH includes optimistic version, never reconnects implicitly',
    () async {
      resource = (r) async {
        expect(r.method, 'PATCH');
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'expectedVersionNumber': 1,
          'status': 'revoked',
        });
        await reply(r, 200, connection(status: 'revoked'));
      };
      expect(
        (await api.changeStatus(syncConnection(), 'revoked')).status,
        'revoked',
      );
    },
  );
  test(
    'summary sends offset day bounds and preserves unknown null versus real zero',
    () async {
      final day = WaterDayRange.forDate(DateTime(2026, 11, 19));
      resource = (r) async {
        expect(r.uri.path, '/api/v1/activity-logs/daily-summary');
        expect(r.uri.queryParameters, day.query);
        await reply(r, 200, {
          'from': day.from.toUtc().toIso8601String(),
          'to': day.to.toUtc().toIso8601String(),
          'steps': 0,
          'distanceKm': null,
          'activeEnergyKcal': null,
          'exerciseMinutes': null,
          'heartRateMeanBpm': null,
          'heartRateMinBpm': null,
          'heartRateMaxBpm': null,
          'exerciseCount': 0,
          'heartRateSampleCount': 0,
          'excludedOverlapCount': 0,
          'unallocatedCount': 0,
          'isPartial': false,
          'calculationPolicy': 'conservative_overlap_v1',
        });
      };
      final summary = await api.dailySummary(day);
      expect(summary.values['steps'], 0);
      expect(summary.values['distanceKm'], null);
    },
  );
  test(
    'GET may refresh once but sync 401 never automatically repeats POST',
    () async {
      var reads = 0;
      resource = (r) async {
        reads++;
        await reply(r, reads == 1 ? 401 : 200, reads == 1 ? {} : connection());
      };
      await api.getConnection(healthConnectionId);
      expect(reads, 2);
      expect(renewals, 1);
      var writes = 0;
      resource = (r) async {
        writes++;
        await r.drain<void>();
        await reply(r, 401, {});
      };
      await expectLater(
        api.sync(batch()),
        throwsA(
          isA<HealthDataException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(writes, 1);
      expect(renewals, 2);
    },
  );
  for (final status in [403, 404, 409, 413, 422, 500]) {
    test('sync $status is surfaced without automatic write retry', () async {
      var calls = 0;
      resource = (r) async {
        calls++;
        await r.drain<void>();
        await reply(r, status, {
          'error': {'code': 'synthetic_error'},
        });
      };
      await expectLater(
        api.sync(batch()),
        throwsA(
          isA<HealthDataException>().having(
            (e) => e.statusCode,
            'status',
            status,
          ),
        ),
      );
      expect(calls, 1);
    });
  }
  test(
    'unrecognized successful receipt is uncertain rather than successful or silently retried',
    () async {
      for (final body in [
        null,
        {},
        {'batchId': 'wrong', 'records': []},
      ]) {
        var calls = 0;
        resource = (r) async {
          calls++;
          await r.drain<void>();
          await reply(r, 200, body);
        };
        await expectLater(
          api.sync(batch()),
          throwsA(
            isA<HealthDataException>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
        expect(calls, 1);
      }
    },
  );
}
