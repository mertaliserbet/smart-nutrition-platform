import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'device_health_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDeviceHealthSource source;
  late DeviceHealthReader reader;
  setUp(() {
    source = FakeDeviceHealthSource();
    reader = DeviceHealthReader(source: source);
  });
  Future<Map<DeviceHealthMetric, DeviceHealthReading>> read() =>
      reader.read(from: healthFrom, to: healthTo, isCurrent: () => true);

  test('unsupported device never requests permission or reads', () async {
    source.support = DeviceHealthAvailability.unsupported;
    await reader.requestPermissions(isCurrent: () => true);
    expect(
      (await read()).values.every(
        (r) => r.state == DeviceHealthReadState.unavailable,
      ),
      true,
    );
    expect(source.reads, 0);
    expect(source.requested, null);
  });
  test(
    'only missing read types requested, existing permissions untouched',
    () async {
      source.permissions[HealthDataType.HEART_RATE] = false;
      await reader.requestPermissions(isCurrent: () => true);
      expect(source.requested, [HealthDataType.HEART_RATE]);
      expect(source.reads, 0);
      source.permissions.clear();
      await reader.requestPermissions(isCurrent: () => true);
      expect(source.requests, 1);
    },
  );
  test('partial Android permission denial skips only denied type', () async {
    source.permissions[HealthDataType.HEART_RATE] = false;
    source.rows[HealthDataType.STEPS] = [healthSample()];
    final result = await read();
    expect(
      result[DeviceHealthMetric.heartRate]!.state,
      DeviceHealthReadState.denied,
    );
    expect(source.readTypes, isNot(contains(HealthDataType.HEART_RATE)));
    expect(result[DeviceHealthMetric.steps]!.samples.single.value, 123);
    expect(result[DeviceHealthMetric.distance]!.samples, isEmpty);
    expect(source.requests, 0); // Reads never open authorization dialogs.
  });
  test(
    'HealthKit unknown READ permission is queried and never called denied',
    () async {
      source.isIOS = true;
      await reader.requestPermissions(isCurrent: () => true);
      expect(source.requested!.length, 5);
      final result = await read();
      expect(
        result.values.every((r) => r.state == DeviceHealthReadState.empty),
        true,
      );
      expect(source.reads, 5);
    },
  );
  test('one provider failure is error, other metrics still read', () async {
    source.errors[HealthDataType.STEPS] = PlatformException(
      code: 'read_failed',
    );
    source.rows[HealthDataType.HEART_RATE] = [
      healthSample(metric: DeviceHealthMetric.heartRate, value: 70),
    ];
    final result = await read();
    expect(
      result[DeviceHealthMetric.steps]!.state,
      DeviceHealthReadState.error,
    );
    expect(result[DeviceHealthMetric.steps]!.samples, isEmpty);
    expect(result[DeviceHealthMetric.heartRate]!.samples.single.value, 70);
  });
  test('revocation error is denied and no stale samples exposed', () async {
    source.errors[HealthDataType.STEPS] = PlatformException(
      code: 'permission_denied',
    );
    expect(
      (await read())[DeviceHealthMetric.steps]!.state,
      DeviceHealthReadState.denied,
    );
  });
  test(
    'start-based half-open interval, chronological order, identity dedup',
    () async {
      final first = healthSample();
      source.rows[HealthDataType.STEPS] = [
        healthSample(start: healthTo),
        healthSample(start: healthFrom.add(const Duration(hours: 2))),
        healthSample(start: healthFrom.subtract(const Duration(seconds: 1))),
        first,
        first,
        healthSample(source: 'second.source'),
      ];
      final rows = (await read())[DeviceHealthMetric.steps]!.samples;
      expect(rows.length, 3);
      expect(rows.first.start, healthFrom);
      expect(rows.last.start, healthFrom.add(const Duration(hours: 2)));
      expect(rows.where((r) => r.start == healthFrom).length, 2);
    },
  );
  test(
    'heart samples sharing record UUID retain individual timestamps',
    () async {
      source.rows[HealthDataType.HEART_RATE] = [
        healthSample(metric: DeviceHealthMetric.heartRate, value: 70),
        healthSample(
          metric: DeviceHealthMetric.heartRate,
          value: 71,
          start: healthFrom.add(const Duration(seconds: 1)),
        ),
      ];
      expect((await read())[DeviceHealthMetric.heartRate]!.samples.length, 2);
    },
  );
  test(
    'account change during OS read cancels without starting next query',
    () async {
      final completer = Completer<List<DeviceHealthSample>>();
      source.pending = completer.future;
      var current = true;
      final pending = reader.read(
        from: healthFrom,
        to: healthTo,
        isCurrent: () => current,
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      completer.complete([healthSample()]);
      await expectLater(pending, throwsA(isA<HealthReadCancelled>()));
      expect(source.reads, 1);
    },
  );
  test('invalid ranges and malformed samples cannot become zeros', () async {
    await expectLater(
      reader.read(from: healthTo, to: healthFrom, isCurrent: () => true),
      throwsArgumentError,
    );
    source.rows[HealthDataType.STEPS] = [healthSample(value: double.nan)];
    expect(
      (await read())[DeviceHealthMetric.steps]!.state,
      DeviceHealthReadState.error,
    );
  });
  test(
    'long local day allowed without permitting unbounded historical reads',
    () async {
      final result = await reader.read(
        from: healthFrom,
        to: healthFrom.add(const Duration(hours: 25)),
        isCurrent: () => true,
      );
      expect(result.length, 5);
      await expectLater(
        reader.read(
          from: healthFrom,
          to: healthFrom.add(const Duration(hours: 27)),
          isCurrent: () => true,
        ),
        throwsArgumentError,
      );
    },
  );

  HealthDataPoint point(
    HealthDataType type,
    HealthDataUnit unit,
    HealthValue value,
  ) => HealthDataPoint(
    uuid: 'synthetic-uuid',
    value: value,
    type: type,
    unit: unit,
    dateFrom: healthFrom,
    dateTo: healthFrom.add(const Duration(minutes: 25)),
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'reader-device',
    sourceId: 'synthetic.watch',
    sourceName: 'Synthetic Watch',
  );
  test(
    'HealthKit distance preserves raw meters, converts km and source UUID',
    () {
      final sample = normalizeHealthKitSample(
        DeviceHealthMetric.distance,
        point(
          HealthDataType.DISTANCE_CYCLING,
          HealthDataUnit.METER,
          NumericHealthValue(numericValue: 1234.5),
        ),
      );
      expect(sample.value, 1.2345);
      expect(sample.rawValue, 1234.5);
      expect(sample.rawUnit, 'METER');
      expect(sample.sourceId, 'synthetic.watch');
      expect(sample.externalRecordId, 'synthetic-uuid');
      expect(sample.start.isUtc, true);
    },
  );
  test(
    'exercise elapsed interval does not fabricate energy/distance values',
    () {
      final sample = normalizeHealthKitSample(
        DeviceHealthMetric.exercise,
        point(
          HealthDataType.WORKOUT,
          HealthDataUnit.NO_UNIT,
          WorkoutHealthValue(
            workoutActivityType: HealthWorkoutActivityType.WALKING,
          ),
        ),
      );
      expect(sample.value, 25);
      expect(sample.exerciseType, 'WALKING');
      expect(sample.rawUnit, 'MINUTE');
    },
  );
  test('unexpected units rejected instead of silently converted', () {
    expect(
      () => normalizeHealthKitSample(
        DeviceHealthMetric.activeEnergy,
        point(
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataUnit.JOULE,
          NumericHealthValue(numericValue: 1000),
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'Android bridge keeps errors, HR sample identity and decimal values',
    () async {
      const channel = MethodChannel('smart_nutrition/health_read');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'read');
        expect(call.arguments['type'], 'DISTANCE_DELTA');
        expect(call.arguments['from'], healthFrom.millisecondsSinceEpoch);
        return [
          {
            'id': 'id',
            'sourceId': 'synthetic.provider',
            'from': healthFrom.millisecondsSinceEpoch,
            'to': healthTo.millisecondsSinceEpoch,
            'value': 1234.5,
            'unit': 'METER',
            'recordingMethod': 2,
          },
        ];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final adapter = PluginDeviceHealthSource(
        platform: TargetPlatform.android,
      );
      final samples = await adapter.read(
        DeviceHealthMetric.distance,
        HealthDataType.DISTANCE_DELTA,
        healthFrom,
        healthTo,
      );
      expect(samples.single.value, 1.2345);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'read_failed'),
      );
      await expectLater(
        adapter.read(
          DeviceHealthMetric.steps,
          HealthDataType.STEPS,
          healthFrom,
          healthTo,
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'plugin authorization requests only READ and the five scoped metrics',
    () async {
      final health = ReadPermissionHealth();
      final adapter = PluginDeviceHealthSource(
        health: health,
        platform: TargetPlatform.android,
      );
      await DeviceHealthReader(
        source: adapter,
      ).requestPermissions(isCurrent: () => true);
      expect(health.requested, [
        HealthDataType.STEPS,
        HealthDataType.DISTANCE_DELTA,
        HealthDataType.WORKOUT,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
      ]);
      expect(health.access, everyElement(HealthDataAccess.READ));
      expect(health.access!.length, 5);
    },
  );
  test(
    'HealthKit availability is checked before any permission dialog',
    () async {
      const channel = MethodChannel('flutter_health');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'checkIfHealthDataAvailable');
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final health = ReadPermissionHealth();
      final adapter = PluginDeviceHealthSource(
        health: health,
        platform: TargetPlatform.iOS,
      );
      await DeviceHealthReader(
        source: adapter,
      ).requestPermissions(isCurrent: () => true);
      expect(health.requested, null);
      expect(adapter.types(DeviceHealthMetric.distance), [
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.DISTANCE_CYCLING,
        HealthDataType.DISTANCE_SWIMMING,
      ]);
    },
  );
}

class ReadPermissionHealth extends Health {
  List<HealthDataType>? requested;
  List<HealthDataAccess>? access;
  @override
  Future<void> configure() async {}
  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      HealthConnectSdkStatus.sdkAvailable;
  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    expect(permissions, [HealthDataAccess.READ]);
    return false;
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requested = types;
    access = permissions;
    return true;
  }
}
