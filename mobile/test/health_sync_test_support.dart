import 'dart:convert';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'package:smart_nutrition_mobile/features/health/health_data_api.dart';

const healthConnectionId = '11111111-1111-4111-8111-111111111111';
const healthClientId = '22222222-2222-4222-8222-222222222222';
final syncFrom = DateTime.utc(2026, 11, 19, 8);

DeviceHealthSample syncSample({
  DeviceHealthMetric metric = DeviceHealthMetric.steps,
  String id = 'native-synthetic-id',
  int second = 0,
  double? raw,
  String provider = 'healthConnect',
}) {
  final start = syncFrom.add(Duration(seconds: second));
  final unit = switch (metric) {
    DeviceHealthMetric.steps => 'COUNT',
    DeviceHealthMetric.distance => 'METER',
    DeviceHealthMetric.exercise => 'MINUTE',
    DeviceHealthMetric.activeEnergy => 'KILOCALORIE',
    DeviceHealthMetric.heartRate => 'BEATS_PER_MINUTE',
  };
  final type = switch (metric) {
    DeviceHealthMetric.steps => 'STEPS',
    DeviceHealthMetric.distance =>
      provider == 'healthKit' ? 'DISTANCE_CYCLING' : 'DISTANCE_DELTA',
    DeviceHealthMetric.exercise => 'WORKOUT',
    DeviceHealthMetric.activeEnergy => 'ACTIVE_ENERGY_BURNED',
    DeviceHealthMetric.heartRate => 'HEART_RATE',
  };
  final value =
      raw ??
      (metric == DeviceHealthMetric.exercise
          ? 1
          : metric == DeviceHealthMetric.heartRate
          ? 70
          : 1250);
  return DeviceHealthSample(
    metric: metric,
    externalRecordId: id,
    provider: provider,
    sourceId: 'example.synthetic.health',
    sourceName: 'Synthetic health source',
    start: start,
    end: metric == DeviceHealthMetric.heartRate
        ? start
        : start.add(const Duration(minutes: 1)),
    value: metric == DeviceHealthMetric.distance ? value / 1000 : value,
    rawValue: value,
    rawUnit: unit,
    rawType: type,
    recordingMethod: '2',
    exerciseType: metric == DeviceHealthMetric.exercise ? 'WALKING' : null,
  );
}

WearableConnection syncConnection({
  String status = 'active',
  int version = 1,
  DateTime? lastSyncedAt,
}) => WearableConnection(
  id: healthConnectionId,
  provider: 'health_connect',
  status: status,
  versionNumber: version,
  lastSyncedAt: lastSyncedAt,
  lastAttemptAt: lastSyncedAt,
  lastSyncStatus: lastSyncedAt == null ? 'never' : 'succeeded',
  lastErrorCode: null,
);

class SyncTestApi extends HealthDataApi {
  SyncTestApi(super.session);
  WearableConnection? connection;
  HealthDataException? syncFailure, readFailure;
  Future<WearableSyncReceipt>? pendingSync;
  int creates = 0, reads = 0, statusWrites = 0;
  final payloads = <Map<String, Object?>>[];
  final sources = <String, WearableRecord>{};
  bool tombstones = false;
  @override
  Future<WearableConnection?> connectionFor(String provider) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return connection;
  }

  @override
  Future<WearableConnection> connect(String provider) async {
    creates++;
    return connection = syncConnection();
  }

  @override
  Future<WearableConnection> changeStatus(
    WearableConnection c,
    String status,
  ) async {
    statusWrites++;
    return connection = syncConnection(
      status: status,
      version: c.versionNumber + 1,
      lastSyncedAt: c.lastSyncedAt,
    );
  }

  @override
  Future<WearableRecord?> record(
    String connectionId,
    String source,
    String type,
    String external,
  ) async => tombstones
      ? WearableRecord(
          id: healthClientId,
          sourceId: source,
          rawType: type,
          externalRecordId: external,
          versionNumber: 2,
          isDeleted: true,
        )
      : sources['$source|$type|$external'];
  @override
  Future<WearableSyncReceipt> sync(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (syncFailure != null) throw syncFailure!;
    if (pendingSync != null) return pendingSync!;
    final changes = payload['changes'] as List;
    for (final change in changes) {
      final key =
          '${change['sourceId']}|${change['rawType']}|${change['externalRecordId']}';
      sources[key] = WearableRecord(
        id: healthClientId,
        sourceId: change['sourceId'] as String,
        rawType: change['rawType'] as String,
        externalRecordId: change['externalRecordId'] as String,
        versionNumber: (change['expectedVersionNumber'] as int) + 1,
        isDeleted: false,
      );
    }
    connection = syncConnection(lastSyncedAt: DateTime.utc(2026, 11, 19, 12));
    return WearableSyncReceipt(
      payload['batchId'] as String,
      connection!.lastSyncedAt!,
      changes.length,
    );
  }

  @override
  Future<ActivityDailySummary> dailySummary(dynamic day) async {
    if (readFailure != null) throw readFailure!;
    return ActivityDailySummary(
      from: day.from.toUtc(),
      to: day.to.toUtc(),
      values: Map.unmodifiable({
        'steps': payloads.isEmpty ? null : 1250,
        'distanceKm': null,
        'activeEnergyKcal': null,
        'exerciseMinutes': null,
        'heartRateMeanBpm': null,
      }),
      isPartial: false,
      excludedOverlapCount: 0,
      unallocatedCount: 0,
    );
  }

  String get lastJson => jsonEncode(payloads.last);
}
