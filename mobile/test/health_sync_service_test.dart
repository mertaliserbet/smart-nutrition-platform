import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'package:smart_nutrition_mobile/features/health/health_data_api.dart';
import 'package:smart_nutrition_mobile/features/health/health_sync_service.dart';
import 'health_sync_test_support.dart';
import 'device_health_test_support.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late SyncTestApi api;
  late HealthSyncService service;
  setUp(() {
    session = WaterTestSession();
    api = SyncTestApi(session);
    service = HealthSyncService(api);
  });
  tearDown(() => session.dispose());
  Future<HealthSyncOutcome> send(
    List<DeviceHealthSample> samples, {
    bool consent = true,
    HealthAccessCheck? canSend,
  }) => service.synchronize(
    provider: 'health_connect',
    samples: samples,
    consent: consent,
    isCurrent: () => true,
    canSend: canSend ?? (_) async => true,
  );

  test(
    'no consent or no observations never opens a connection or posts',
    () async {
      await expectLater(
        send([syncSample()], consent: false),
        throwsA(isA<HealthDataException>()),
      );
      expect((await send([])).receipts, isEmpty);
      expect(api.creates, 0);
      expect(api.payloads, isEmpty);
    },
  );
  test(
    'five metric mapping preserves native IDs, raw units and UTC intervals',
    () async {
      await send([
        for (final metric in DeviceHealthMetric.values)
          syncSample(metric: metric),
      ]);
      final changes = api.payloads.single['changes'] as List;
      expect(changes.map((c) => c['metric']), [
        'steps',
        'distance',
        'exercise',
        'active_energy',
        'heart_rate',
      ]);
      final distance = changes[1];
      expect(distance['rawUnit'], 'METER');
      expect(distance['samples'][0]['rawValue'], 1250);
      expect(distance['externalRecordId'], 'native-synthetic-id');
      expect(distance['sourceId'], 'example.synthetic.health');
      expect(distance['recordingMethod'], '2');
      expect(distance['samples'][0]['startedAt'], endsWith('Z'));
      expect(changes[2]['exerciseType'], 'WALKING');
      expect(changes[3].containsKey('exerciseType'), false);
    },
  );
  test('HR same native ID is one source with individual timestamps', () async {
    await send([
      syncSample(metric: DeviceHealthMetric.heartRate),
      syncSample(metric: DeviceHealthMetric.heartRate, second: 1, raw: 71),
    ]);
    final changes = api.payloads.single['changes'] as List;
    expect(changes.length, 1);
    expect((changes.single['samples'] as List).length, 2);
  });
  test(
    'subsequent sync asks current header version instead of inventing record identity',
    () async {
      final samples = [syncSample()];
      await send(samples);
      await send(samples);
      expect(api.sources.length, 1);
      expect(
        (api.payloads[0]['changes'] as List).single['expectedVersionNumber'],
        0,
      );
      expect(
        (api.payloads[1]['changes'] as List).single['expectedVersionNumber'],
        1,
      );
    },
  );
  test(
    'uncertain failure retains exact batch and content; retry only on manual action',
    () async {
      final samples = [syncSample()];
      api.syncFailure = const HealthDataException(
        'synthetic timeout',
        uncertain: true,
      );
      await expectLater(send(samples), throwsA(isA<HealthDataException>()));
      expect(api.payloads.length, 1);
      expect(service.hasPending, true);
      final original = api.lastJson;
      api.syncFailure = null;
      await send(samples);
      expect(api.payloads.length, 2);
      expect(api.lastJson, original);
      expect(service.hasPending, false);
    },
  );
  test(
    'source conflict never auto increments version or retries POST',
    () async {
      api.syncFailure = const HealthDataException(
        'synthetic conflict',
        statusCode: 409,
      );
      await expectLater(
        send([syncSample()]),
        throwsA(isA<HealthDataException>()),
      );
      expect(api.payloads.length, 1);
      expect(service.hasPending, false);
    },
  );
  test(
    'failed/empty read cannot replay data from a previously successful read',
    () async {
      api.syncFailure = const HealthDataException(
        'synthetic timeout',
        uncertain: true,
      );
      await expectLater(
        send([syncSample()]),
        throwsA(isA<HealthDataException>()),
      );
      api.syncFailure = null;
      await expectLater(send([]), throwsA(isA<HealthDataException>()));
      expect(api.payloads.length, 1);
      expect(service.hasPending, false);
    },
  );
  test(
    'transient connection read failure retains an uncertain POST receipt key',
    () async {
      final samples = [syncSample()];
      api.syncFailure = const HealthDataException(
        'synthetic timeout',
        uncertain: true,
      );
      await expectLater(send(samples), throwsA(isA<HealthDataException>()));
      final original = api.lastJson;
      api.syncFailure = null;
      api.readFailure = const HealthDataException('synthetic read outage');
      await expectLater(send(samples), throwsA(isA<HealthDataException>()));
      expect(service.hasPending, true);
      expect(api.payloads.length, 1);
      api.readFailure = null;
      await send(samples);
      expect(api.lastJson, original);
    },
  );
  test(
    'permission revoked before send drops pending queue without POST',
    () async {
      await expectLater(
        send([syncSample()], canSend: (_) async => false),
        throwsA(isA<HealthDataException>()),
      );
      expect(api.payloads, isEmpty);
      expect(api.creates, 0);
    },
  );
  test('revoked connection is never silently reactivated', () async {
    api.connection = syncConnection(status: 'revoked');
    await expectLater(
      send([syncSample()]),
      throwsA(isA<HealthDataException>()),
    );
    expect(api.statusWrites, 0);
    expect(api.payloads, isEmpty);
  });
  test(
    'server tombstones are not resurrected and omitted OS records are never deleted',
    () async {
      api.tombstones = true;
      final result = await send([syncSample()]);
      expect(result.skippedDeletedRecords, 1);
      expect(api.payloads, isEmpty);
    },
  );
  test(
    'batches respect limits and split a large HR source without losing points',
    () async {
      await send([
        for (var i = 0; i < 1101; i++)
          syncSample(metric: DeviceHealthMetric.heartRate, second: i),
      ]);
      expect(api.payloads.length, 3);
      var points = 0;
      for (final payload in api.payloads) {
        final changes = payload['changes'] as List;
        expect(changes.length, lessThanOrEqualTo(100));
        final count = changes.fold<int>(
          0,
          (n, c) => n + (c['samples'] as List).length,
        );
        points += count;
        expect(count, lessThanOrEqualTo(1000));
        expect(utf8.encode(jsonEncode(payload)).length, lessThan(524288));
      }
      expect(points, 1101);
      expect(
        (api.payloads[2]['changes'] as List).single['expectedVersionNumber'],
        2,
      );
    },
  );
  test('101 distinct native sources split into 100 and 1', () async {
    await send([for (var i = 0; i < 101; i++) syncSample(id: 'synthetic-$i')]);
    expect((api.payloads[0]['changes'] as List).length, 100);
    expect((api.payloads[1]['changes'] as List).length, 1);
  });
  test(
    'account/lifecycle cancellation discards late response and pending data',
    () async {
      final completer = Completer<WearableSyncReceipt>();
      api.pendingSync = completer.future;
      final operation = send([syncSample()]);
      await Future<void>.delayed(Duration.zero);
      service.cancel();
      completer.complete(WearableSyncReceipt('synthetic', DateTime.now(), 1));
      await expectLater(operation, throwsA(isA<HealthReadCancelled>()));
      expect(service.hasPending, false);
      expect(api.payloads.length, 1);
    },
  );
  test(
    'HealthKit unknown permission requires pending samples to remain readable',
    () async {
      final source = FakeDeviceHealthSource()..isIOS = true;
      final sample = syncSample(
        metric: DeviceHealthMetric.heartRate,
        provider: 'healthKit',
      );
      final reader = DeviceHealthReader(source: source);
      expect(
        await reader.canTransmit(
          [sample],
          from: syncFrom,
          to: syncFrom.add(const Duration(hours: 1)),
          isCurrent: () => true,
        ),
        false,
      );
      source.rows[HealthDataType.HEART_RATE] = [sample];
      expect(
        await reader.canTransmit(
          [sample],
          from: syncFrom,
          to: syncFrom.add(const Duration(hours: 1)),
          isCurrent: () => true,
        ),
        true,
      );
    },
  );
}
