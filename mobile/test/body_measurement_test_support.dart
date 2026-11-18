import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';
import 'water_test_support.dart';

const bodyId = '11111111-1111-4111-8111-111111111111';
const bodyClientId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> bodyJson({String id = bodyId, num? weight = 73.125}) => {
  'id': id,
  'clientId': bodyClientId,
  'measuredAt': '2026-11-18T09:00:00Z',
  'source': 'manual',
  'weightKg': weight,
  'waistCm': null,
  'hipCm': null,
  'chestCm': null,
  'bodyFatPercent': null,
  'note': null,
};
BodyMeasurement bodySample({
  String id = bodyId,
  num? weight = 73.125,
  num? waist,
  num? hip,
  num? chest,
  num? fat,
  String? note,
  DateTime? at,
}) => BodyMeasurement(
  id: id,
  clientId: bodyClientId,
  measuredAt: at ?? DateTime.utc(2026, 11, 18, 9),
  source: 'manual',
  weightKg: weight,
  waistCm: waist,
  hipCm: hip,
  chestCm: chest,
  bodyFatPercent: fat,
  note: note,
);

class BodyTestSession extends WaterTestSession {}

class BodyTestApi extends BodyMeasurementApi {
  BodyTestApi(super.session);
  List<BodyMeasurement> rows = [];
  Future<List<BodyMeasurement>>? pendingHistory;
  Future<BodyMeasurement>? pendingWrite;
  BodyMeasurementApiException? failure;
  int reads = 0, creates = 0, updates = 0, deletes = 0;
  Map<String, Object?>? changes;
  void check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<List<BodyMeasurement>> history() async {
    reads++;
    check();
    return pendingHistory ?? rows;
  }

  @override
  Future<BodyMeasurement> get(String id) async {
    check();
    return rows.firstWhere((row) => row.id == id);
  }

  @override
  Future<BodyMeasurement> create({
    required Map<String, num?> values,
    required DateTime measuredAt,
    String? note,
  }) async {
    creates++;
    check();
    changes = {...values, 'note': note};
    final row =
        await (pendingWrite ??
            Future.value(
              bodySample(
                weight: values['weightKg'],
                waist: values['waistCm'],
                hip: values['hipCm'],
                chest: values['chestCm'],
                fat: values['bodyFatPercent'],
                note: note,
                at: measuredAt,
              ),
            ));
    rows = [...rows, row];
    return row;
  }

  @override
  Future<BodyMeasurement> update(String id, Map<String, Object?> values) async {
    updates++;
    check();
    changes = values;
    final old = rows.firstWhere((row) => row.id == id);
    final all = {...old.values, ...values};
    final row = bodySample(
      id: id,
      weight: all['weightKg'] as num?,
      waist: all['waistCm'] as num?,
      hip: all['hipCm'] as num?,
      chest: all['chestCm'] as num?,
      fat: all['bodyFatPercent'] as num?,
      note: values.containsKey('note') ? values['note'] as String? : old.note,
      at: values.containsKey('measuredAt')
          ? DateTime.parse(values['measuredAt'] as String)
          : old.measuredAt,
    );
    rows = [
      for (final value in rows)
        if (value.id == id) row else value,
    ];
    return row;
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    check();
    rows = rows.where((row) => row.id != id).toList();
  }
}
