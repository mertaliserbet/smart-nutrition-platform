// Opt-in: real Flutter M3 client + HTTPS + isolated PostgreSQL, synthetic inputs.
// This verifies HTTP integration, not native Health Connect/HealthKit reading.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'package:smart_nutrition_mobile/features/health/health_data_api.dart';
import 'package:smart_nutrition_mobile/features/health/health_sync_service.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'water_test_support.dart';

class _ObservedApi extends HealthDataApi {
  _ObservedApi(super.session);
  final payloads = <Map<String, Object?>>[];
  @override
  Future<WearableSyncReceipt> sync(Map<String, Object?> payload) {
    payloads.add(payload);
    return super.sync(payload);
  }
}

void main() {
  test(
    'M3 client: five metrics, retry, readback, summary, consent and isolation',
    () async {
      final database = Platform.environment['SNP_HEALTH_TEST_DATABASE']!;
      expect(RegExp(r'^m3_verify_\d+$').hasMatch(database), isTrue);
      final origin = Uri.parse('https://localhost:7101');
      Future<String> sql(String statement) async {
        final process = await Process.run('docker', [
          'exec',
          'smart-nutrition-postgres',
          'psql',
          '-X',
          '-v',
          'ON_ERROR_STOP=1',
          '-U',
          'smart_nutrition',
          '-d',
          database,
          '-Atqc',
          statement,
        ]);
        expect(
          process.exitCode,
          0,
          reason: 'Scoped synthetic fixture operation',
        );
        return process.stdout.toString().trim();
      }

      expect(
        await sql(
          "SELECT DISTINCT datname FROM pg_stat_activity WHERE application_name='m3-live-verify'",
        ),
        database,
      );
      const password = 'Synthetic M3 integration password 2026!';
      final suffix = DateTime.now().microsecondsSinceEpoch;
      Future<String> register(String label) async {
        final email = 'synthetic-m3-$label-$suffix@example.test';
        final response = await requestJson(
          method: 'POST',
          path: '/api/v1/auth/register',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
          payload: {
            'email': email,
            'password': password,
            'displayName': 'Synthetic M3 account',
            'role': 'client',
          },
        );
        expect(response.statusCode, 201);
        final id = (response.body as Map)['id'] as String;
        expect(RegExp(r'^[a-f0-9-]{36}$').hasMatch(id), isTrue);
        await sql("UPDATE users SET is_email_verified=true WHERE id='$id'");
        return email;
      }

      final ownerEmail = await register('owner');
      final otherEmail = await register('other');
      final session = AuthSession(
        api: LoginApi(baseUri: origin),
        store: WaterMemoryStore(),
      );
      final api = _ObservedApi(session);
      // Use the production service with the real session and HTTP implementation.
      final sync = HealthSyncService(api);
      await session.initialize();
      try {
        expect(
          await session.signIn(email: ownerEmail, password: password),
          isTrue,
        );
        final owner = session.user!.id;
        bool current() => session.user?.id == owner;
        final day = WaterDayRange.forDate(DateTime(2026, 10, 20));
        final start = DateTime(2026, 10, 20, 10);
        DeviceHealthSample sample(
          DeviceHealthMetric metric, {
          String provider = 'healthConnect',
        }) {
          final raw = switch (metric) {
            DeviceHealthMetric.steps => 1200.0,
            DeviceHealthMetric.distance => 1250.0,
            DeviceHealthMetric.exercise => 20.0,
            DeviceHealthMetric.activeEnergy => 80.0,
            DeviceHealthMetric.heartRate => 72.0,
          };
          return DeviceHealthSample(
            metric: metric,
            provider: provider,
            externalRecordId: 'synthetic-native-${metric.name}',
            sourceId: 'example.synthetic.m3',
            sourceName: 'Synthetic M3 source',
            recordingMethod: '2',
            start: start,
            end: metric == DeviceHealthMetric.heartRate
                ? start
                : start.add(const Duration(minutes: 20)),
            value: metric == DeviceHealthMetric.distance ? raw / 1000 : raw,
            rawValue: raw,
            rawUnit: switch (metric) {
              DeviceHealthMetric.steps => 'COUNT',
              DeviceHealthMetric.distance => 'METER',
              DeviceHealthMetric.exercise => 'MINUTE',
              DeviceHealthMetric.activeEnergy => 'KILOCALORIE',
              DeviceHealthMetric.heartRate => 'BEATS_PER_MINUTE',
            },
            rawType: switch (metric) {
              DeviceHealthMetric.steps => 'STEPS',
              DeviceHealthMetric.distance =>
                provider == 'healthKit'
                    ? 'DISTANCE_WALKING_RUNNING'
                    : 'DISTANCE_DELTA',
              DeviceHealthMetric.exercise => 'WORKOUT',
              DeviceHealthMetric.activeEnergy => 'ACTIVE_ENERGY_BURNED',
              DeviceHealthMetric.heartRate => 'HEART_RATE',
            },
            exerciseType: metric == DeviceHealthMetric.exercise ? '8' : null,
          );
        }

        final observations = DeviceHealthMetric.values.map(sample).toList();
        Future<HealthSyncOutcome> send({
          bool consent = true,
          bool allowed = true,
        }) => sync.synchronize(
          provider: 'health_connect',
          samples: observations,
          consent: consent,
          isCurrent: current,
          canSend: (_) async => allowed,
        );
        expect(
          (await api.dailySummary(day)).values.values,
          everyElement(isNull),
        );
        await expectLater(
          send(consent: false),
          throwsA(isA<HealthDataException>()),
        );
        await expectLater(
          send(allowed: false),
          throwsA(isA<HealthDataException>()),
        );
        expect(api.payloads, isEmpty);
        expect(await api.connectionFor('health_connect'), isNull);
        final first = await send();
        expect(first.receipts.single.recordCount, 5);
        final payload = api.payloads.single;
        expect(payload.containsKey('clientId'), isFalse);
        for (final change in payload['changes'] as List) {
          expect(change['sourceId'], 'example.synthetic.m3');
          expect(change['recordingMethod'], '2');
          expect(change['externalRecordId'], startsWith('synthetic-native-'));
          expect(
            change['samples'][0]['startedAt'],
            start.toUtc().toIso8601String(),
          );
          expect(change['samples'][0]['endedAt'], endsWith('Z'));
        }
        final replay = await api.sync(payload);
        expect(replay.committedAt, first.receipts.single.committedAt);
        await send();
        var connection = (await api.connectionFor('health_connect'))!;
        for (final observation in observations) {
          final header = await api.record(
            connection.id,
            observation.sourceId,
            observation.rawType,
            observation.externalRecordId,
          );
          expect(header!.versionNumber, 1);
        }
        expect(await sql('SELECT count(*) FROM wearable_records'), '5');
        expect(await sql('SELECT count(*) FROM health_metric_samples'), '4');
        expect(await sql('SELECT count(*) FROM activity_logs'), '1');
        final summary = await api.dailySummary(day);
        expect(summary.values['steps'], 1200);
        expect(summary.values['distanceKm'], 1.25);
        expect(summary.values['exerciseMinutes'], 20);
        expect(summary.values['activeEnergyKcal'], 80);
        expect(summary.values['heartRateMeanBpm'], 72);
        expect(summary.isPartial, isFalse);
        final samples = await session.authorizedRequest(
          path: '/api/v1/health-metric-samples?page=1&pageSize=100',
          profileContext: 'client',
        );
        expect(samples.statusCode, 200);
        final distance = ((samples.body as Map)['items'] as List).firstWhere(
          (x) => x['metric'] == 'distance',
        );
        expect(distance['rawValue'], 1250);
        expect(distance['value'], 1.25);
        expect(distance['unit'], 'km');
        connection = await api.changeStatus(connection, 'revoked');
        expect((await api.connect('health_connect')).status, 'revoked');
        await expectLater(send(), throwsA(isA<HealthDataException>()));
        await expectLater(
          api.sync(payload),
          throwsA(
            isA<HealthDataException>().having(
              (e) => e.statusCode,
              'status',
              403,
            ),
          ),
        );
        connection = await api.changeStatus(connection, 'active');
        await send();
        expect(
          (await api.getConnection(connection.id)).lastSyncStatus,
          'succeeded',
        );
        final kit = HealthSyncService(api);
        await kit.synchronize(
          provider: 'health_kit',
          samples: [sample(DeviceHealthMetric.distance, provider: 'healthKit')],
          consent: true,
          isCurrent: current,
          canSend: (_) async => true,
        );
        // Identical overlapping HealthKit distance must not double the HC total.
        expect((await api.dailySummary(day)).values['distanceKm'], 1.25);
        expect((await api.dailySummary(day)).isPartial, isTrue);
        final denied = await session.authorizedRequest(
          path: '/api/v1/health-metric-samples?page=1&pageSize=100',
          profileContext: 'dietitian',
        );
        expect(denied.statusCode, 403);
        sync.cancel();
        await session.signOut();
        await expectLater(
          api.getConnection(connection.id),
          throwsA(isA<HealthDataException>()),
        );
        expect(
          await session.signIn(email: otherEmail, password: password),
          isTrue,
        );
        expect(await api.connectionFor('health_connect'), isNull);
        expect(
          (await api.dailySummary(day)).values.values,
          everyElement(isNull),
        );
        await expectLater(
          api.getConnection(connection.id),
          throwsA(
            isA<HealthDataException>().having(
              (e) => e.statusCode,
              'status',
              404,
            ),
          ),
        );
        await expectLater(send(), throwsA(isA<HealthReadCancelled>()));
        final anonymous = await requestJson(
          method: 'GET',
          path: '/api/v1/wearable-connections?page=1&pageSize=100',
          baseUri: origin,
          timeout: const Duration(seconds: 20),
        );
        expect(anonymous.statusCode, 401);
        await File('build/m3-live/flutter-result.json').writeAsString(
          jsonEncode({
            'realFlutterClient': true,
            'httpsPostgres': true,
            'syntheticInput': true,
            'nativeDeviceSync': false,
            'fiveMetrics': true,
            'deduplication': true,
            'serverReadback': true,
            'summary': true,
            'consentAndRevocation': true,
            'accountIsolation': true,
          }),
        );
      } finally {
        sync.cancel();
        if (session.isAuthenticated) await session.signOut();
        session.dispose();
      }
    },
    skip: Platform.environment['SNP_HEALTH_LIVE'] != '1',
  );
}
