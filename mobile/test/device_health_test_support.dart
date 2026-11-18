import 'package:health/health.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';

final healthFrom = DateTime.utc(2026, 11, 18);
final healthTo = DateTime.utc(2026, 11, 18, 12);

DeviceHealthSample healthSample({
  DeviceHealthMetric metric = DeviceHealthMetric.steps,
  DateTime? start,
  String id = 'synthetic-record',
  String source = 'synthetic.source',
  double value = 123,
}) => DeviceHealthSample(
  metric: metric,
  externalRecordId: id,
  provider: 'healthConnect',
  sourceId: source,
  sourceName: source,
  start: start ?? healthFrom,
  end: start ?? healthFrom,
  value: value,
  rawValue: value,
  rawUnit: metric.unit,
  rawType: metric.name,
  recordingMethod: 'automatic',
);

class FakeDeviceHealthSource implements DeviceHealthSource {
  @override
  bool isIOS = false;
  DeviceHealthAvailability support = DeviceHealthAvailability.available;
  final permissions = <HealthDataType, bool?>{};
  final rows = <HealthDataType, List<DeviceHealthSample>>{};
  final errors = <HealthDataType, Object>{};
  final readTypes = <HealthDataType>[];
  List<HealthDataType>? requested;
  Future<List<DeviceHealthSample>>? pending;
  Future<bool>? pendingPermission;
  int reads = 0;
  int installs = 0;
  int requests = 0;
  bool requestResult = true;

  @override
  Future<DeviceHealthAvailability> availability() async => support;
  @override
  List<HealthDataType> types(DeviceHealthMetric metric) => [
    switch (metric) {
      DeviceHealthMetric.steps => HealthDataType.STEPS,
      DeviceHealthMetric.distance => HealthDataType.DISTANCE_DELTA,
      DeviceHealthMetric.exercise => HealthDataType.WORKOUT,
      DeviceHealthMetric.activeEnergy => HealthDataType.ACTIVE_ENERGY_BURNED,
      DeviceHealthMetric.heartRate => HealthDataType.HEART_RATE,
    },
  ];
  @override
  Future<bool?> hasReadPermission(HealthDataType type) async =>
      isIOS ? null : permissions[type] ?? true;
  @override
  Future<bool> requestReadPermissions(List<HealthDataType> types) async {
    requests++;
    requested = types;
    return pendingPermission ?? requestResult;
  }

  @override
  Future<List<DeviceHealthSample>> read(
    DeviceHealthMetric metric,
    HealthDataType type,
    DateTime from,
    DateTime to,
  ) async {
    reads++;
    readTypes.add(type);
    if (errors.containsKey(type)) throw errors[type]!;
    return pending ?? rows[type] ?? [];
  }

  @override
  Future<void> install() async {
    installs++;
  }
}
