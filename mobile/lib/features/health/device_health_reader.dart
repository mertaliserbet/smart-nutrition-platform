import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

enum DeviceHealthMetric {
  steps('Adım', 'adım'),
  distance('Mesafe', 'km'),
  exercise('Egzersiz', 'dk (zaman aralığı)'),
  activeEnergy('Aktif kalori', 'kcal'),
  heartRate('Nabız', 'atım/dk');

  const DeviceHealthMetric(this.label, this.unit);
  final String label, unit;
}

enum DeviceHealthAvailability { available, installRequired, unsupported }

enum DeviceHealthReadState { data, empty, denied, unavailable, error }

/// Local read model, NOT an ActivityLog or an approved backend sync DTO.
/// Values from different providers/overlapping intervals must not be summed.
class DeviceHealthSample {
  const DeviceHealthSample({
    required this.metric,
    required this.externalRecordId,
    required this.provider,
    required this.sourceId,
    required this.sourceName,
    required this.start,
    required this.end,
    required this.value,
    required this.rawValue,
    required this.rawUnit,
    required this.rawType,
    required this.recordingMethod,
    this.exerciseType,
  });

  final DeviceHealthMetric metric;
  final String externalRecordId, provider, sourceId, sourceName;
  final DateTime start, end;
  final double value, rawValue;
  final String rawUnit, rawType, recordingMethod;
  final String? exerciseType;

  // A HeartRateRecord can contain multiple samples with the SAME record ID.
  // Keep sample time/type as well as provider/source identity for future M3.
  String get identity =>
      '$provider|$sourceId|$rawType|$externalRecordId|'
      '${start.microsecondsSinceEpoch}|${end.microsecondsSinceEpoch}';
}

class DeviceHealthReading {
  DeviceHealthReading(this.state, [List<DeviceHealthSample> samples = const []])
    : samples = List.unmodifiable(samples);
  final DeviceHealthReadState state;
  final List<DeviceHealthSample> samples;
}

/// Injectable OS boundary. No token, HTTP, persistent cache or logging here.
abstract class DeviceHealthSource {
  bool get isIOS;
  Future<DeviceHealthAvailability> availability();
  List<HealthDataType> types(DeviceHealthMetric metric);
  Future<bool?> hasReadPermission(HealthDataType type);
  Future<bool> requestReadPermissions(List<HealthDataType> types);
  Future<List<DeviceHealthSample>> read(
    DeviceHealthMetric metric,
    HealthDataType type,
    DateTime from,
    DateTime to,
  );
  Future<void> install();
}

class PluginDeviceHealthSource implements DeviceHealthSource {
  PluginDeviceHealthSource({Health? health, TargetPlatform? platform})
    : _health = health ?? Health(),
      _platform = platform ?? defaultTargetPlatform;
  final Health _health;
  final TargetPlatform _platform;
  bool _configured = false;
  static const _androidRead = MethodChannel('smart_nutrition/health_read');
  // health 13.3.2 exposes this HealthKit check natively, without a Dart wrapper.
  static const _healthChannel = MethodChannel('flutter_health');

  @override
  bool get isIOS => _platform == TargetPlatform.iOS;

  @override
  Future<DeviceHealthAvailability> availability() async {
    if (kIsWeb || (!isIOS && _platform != TargetPlatform.android)) {
      return DeviceHealthAvailability.unsupported;
    }
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    if (isIOS) {
      return await _healthChannel.invokeMethod<bool>(
                'checkIfHealthDataAvailable',
              ) ==
              true
          ? DeviceHealthAvailability.available
          : DeviceHealthAvailability.unsupported;
    }
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => DeviceHealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        DeviceHealthAvailability.installRequired,
      HealthConnectSdkStatus.sdkUnavailable =>
        DeviceHealthAvailability.unsupported,
      null => throw StateError('Health Connect availability check failed'),
    };
  }

  @override
  List<HealthDataType> types(DeviceHealthMetric metric) => switch (metric) {
    DeviceHealthMetric.steps => [HealthDataType.STEPS],
    DeviceHealthMetric.distance =>
      isIOS
          ? [
              HealthDataType.DISTANCE_WALKING_RUNNING,
              HealthDataType.DISTANCE_CYCLING,
              HealthDataType.DISTANCE_SWIMMING,
            ]
          : [HealthDataType.DISTANCE_DELTA],
    DeviceHealthMetric.exercise => [HealthDataType.WORKOUT],
    DeviceHealthMetric.activeEnergy => [HealthDataType.ACTIVE_ENERGY_BURNED],
    DeviceHealthMetric.heartRate => [HealthDataType.HEART_RATE],
  };

  @override
  Future<bool?> hasReadPermission(HealthDataType type) async => isIOS
      ? null // HealthKit intentionally does not disclose READ authorization.
      : _health.hasPermissions([type], permissions: [HealthDataAccess.READ]);

  @override
  Future<bool> requestReadPermissions(List<HealthDataType> types) =>
      _health.requestAuthorization(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );

  @override
  Future<void> install() => _health.installHealthConnect();

  @override
  Future<List<DeviceHealthSample>> read(
    DeviceHealthMetric metric,
    HealthDataType type,
    DateTime from,
    DateTime to,
  ) async {
    if (!isIOS) {
      // The plugin swallows Android read failures as [] and its WORKOUT reader
      // additionally requires unrelated TOTAL calories/steps/distance access.
      // This small native reader propagates failures and reads only its type.
      final rows = await _androidRead.invokeListMethod<dynamic>('read', {
        'type': type.name,
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });
      return [
        for (final row in rows ?? [])
          DeviceHealthSample(
            metric: metric,
            externalRecordId: row['id'] as String,
            provider: 'healthConnect',
            sourceId: row['sourceId'] as String,
            sourceName: row['sourceId'] as String,
            start: DateTime.fromMillisecondsSinceEpoch(
              row['from'] as int,
              isUtc: true,
            ),
            end: DateTime.fromMillisecondsSinceEpoch(
              row['to'] as int,
              isUtc: true,
            ),
            value:
                (row['value'] as num).toDouble() /
                (metric == DeviceHealthMetric.distance ? 1000 : 1),
            rawValue: (row['value'] as num).toDouble(),
            rawUnit: row['unit'] as String,
            rawType: type.name,
            recordingMethod: row['recordingMethod'].toString(),
            exerciseType: row['exerciseType']?.toString(),
          ),
      ];
    }
    final rows = await _health.getHealthDataFromTypes(
      types: [type],
      startTime: from,
      endTime: to,
    );
    return [for (final row in rows) normalizeHealthKitSample(metric, row)];
  }
}

DeviceHealthSample normalizeHealthKitSample(
  DeviceHealthMetric metric,
  HealthDataPoint point,
) {
  final value = point.value;
  final double raw;
  final String unit;
  final String? exerciseType;
  if (metric == DeviceHealthMetric.exercise && value is WorkoutHealthValue) {
    raw = point.dateTo.difference(point.dateFrom).inMilliseconds / 60000;
    unit = 'MINUTE';
    exerciseType = value.workoutActivityType.name;
  } else if (value is NumericHealthValue) {
    raw = value.numericValue.toDouble();
    unit = point.unit.name;
    exerciseType = null;
    final expected = switch (metric) {
      DeviceHealthMetric.steps => HealthDataUnit.COUNT,
      DeviceHealthMetric.distance => HealthDataUnit.METER,
      DeviceHealthMetric.activeEnergy => HealthDataUnit.KILOCALORIE,
      DeviceHealthMetric.heartRate => HealthDataUnit.BEATS_PER_MINUTE,
      DeviceHealthMetric.exercise => HealthDataUnit.MINUTE,
    };
    if (point.unit != expected) throw const FormatException('Unexpected unit');
  } else {
    throw const FormatException('Unsupported health value');
  }
  return DeviceHealthSample(
    metric: metric,
    externalRecordId: point.uuid,
    provider: 'healthKit',
    sourceId: point.sourceId,
    sourceName: point.sourceName,
    start: point.dateFrom.toUtc(),
    end: point.dateTo.toUtc(),
    value: metric == DeviceHealthMetric.distance ? raw / 1000 : raw,
    rawValue: raw,
    rawUnit: unit,
    rawType: point.type.name,
    recordingMethod: point.recordingMethod.name,
    exerciseType: exerciseType,
  );
}

class HealthReadCancelled implements Exception {
  const HealthReadCancelled();
}

class DeviceHealthReader {
  DeviceHealthReader({DeviceHealthSource? source})
    : source = source ?? PluginDeviceHealthSource();
  final DeviceHealthSource source;

  Future<void> requestPermissions({required bool Function() isCurrent}) async {
    if (await source.availability() != DeviceHealthAvailability.available ||
        !isCurrent()) {
      return;
    }
    final missing = <HealthDataType>[];
    for (final metric in DeviceHealthMetric.values) {
      for (final type in source.types(metric)) {
        if (!isCurrent()) throw const HealthReadCancelled();
        if (await source.hasReadPermission(type) != true) missing.add(type);
      }
    }
    if (!isCurrent()) throw const HealthReadCancelled();
    if (missing.isNotEmpty) {
      final shown = await source.requestReadPermissions(
        missing.toSet().toList(),
      );
      // Android supports partial grants; read() checks every type separately.
      // On iOS true means the request completed, never proof of read access.
      if (source.isIOS && !shown) throw StateError('Permission request failed');
    }
  }

  /// Records STARTING in [from, to). Keep original intervals, never clip or
  /// prorate counts/energy. UI reads today only; no background/history permission.
  Future<Map<DeviceHealthMetric, DeviceHealthReading>> read({
    required DateTime from,
    required DateTime to,
    required bool Function() isCurrent,
  }) async {
    // A local calendar day can exceed 24 hours at a daylight-saving transition.
    if (!from.isBefore(to) || to.difference(from) > const Duration(hours: 26)) {
      throw ArgumentError(
        'Read interval must be positive and at most 26 hours',
      );
    }
    if (await source.availability() != DeviceHealthAvailability.available) {
      return {
        for (final metric in DeviceHealthMetric.values)
          metric: DeviceHealthReading(DeviceHealthReadState.unavailable),
      };
    }
    final result = <DeviceHealthMetric, DeviceHealthReading>{};
    for (final metric in DeviceHealthMetric.values) {
      final samples = <String, DeviceHealthSample>{};
      var denied = false;
      var failed = false;
      final types = source.types(metric);
      for (final type in types) {
        if (!isCurrent()) throw const HealthReadCancelled();
        try {
          final permission = await source.hasReadPermission(type);
          if (!isCurrent()) throw const HealthReadCancelled();
          if (permission == false) {
            denied = true;
            continue;
          }
          final rows = await source.read(metric, type, from, to);
          if (!isCurrent()) throw const HealthReadCancelled();
          // Re-check revocation during an Android read before exposing results.
          if (!source.isIOS && await source.hasReadPermission(type) != true) {
            denied = true;
            continue;
          }
          for (final row in rows) {
            if (!row.value.isFinite ||
                row.value < 0 ||
                row.end.isBefore(row.start) ||
                row.externalRecordId.isEmpty) {
              throw const FormatException('Invalid health sample');
            }
            if (!row.start.isBefore(from) && row.start.isBefore(to)) {
              samples[row.identity] = row;
            }
          }
        } on HealthReadCancelled {
          rethrow;
        } on PlatformException catch (error) {
          if (error.code == 'permission_denied') {
            denied = true;
          } else {
            failed = true;
          }
        } catch (_) {
          failed = true;
        }
      }
      final rows = samples.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      // An incomplete metric is not presented as a successful complete read.
      result[metric] = DeviceHealthReading(
        failed
            ? DeviceHealthReadState.error
            : denied
            ? DeviceHealthReadState.denied
            : types.isEmpty
            ? DeviceHealthReadState.unavailable
            : rows.isEmpty
            ? DeviceHealthReadState.empty
            : DeviceHealthReadState.data,
        failed || denied ? [] : rows,
      );
    }
    if (!isCurrent()) throw const HealthReadCancelled();
    return result;
  }
}
