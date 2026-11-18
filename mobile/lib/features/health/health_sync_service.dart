import 'dart:convert';
import 'dart:math';

import 'device_health_reader.dart';
import 'health_data_api.dart';

typedef HealthAccessCheck =
    Future<bool> Function(List<DeviceHealthSample> samples);

class HealthSyncOutcome {
  const HealthSyncOutcome(this.receipts, this.skippedDeletedRecords);
  final List<WearableSyncReceipt> receipts;
  final int skippedDeletedRecords;
}

class _SyncUnit {
  _SyncUnit(this.samples);
  final List<DeviceHealthSample> samples;
  DeviceHealthSample get first => samples.first;
}

class _PendingBatch {
  _PendingBatch(this.payload, this.samples, this.units);
  final Map<String, Object?> payload;
  final List<DeviceHealthSample> samples;
  final int units;
}

/// Only foreground, explicitly approved upserts. Missing records never mean delete.
/// No disk queue/health cache; cancelling a session discards all pending data.
class HealthSyncService {
  HealthSyncService(this.api);
  final HealthDataApi api;
  _PendingBatch? _pending;
  List<_SyncUnit> _queue = [];
  String? _connectionId;
  int _generation = 0;
  bool _running = false;
  bool get hasPending => _pending != null;
  void cancel() {
    ++_generation;
    _pending = null;
    _queue = [];
    _connectionId = null;
  }

  Future<HealthSyncOutcome> synchronize({
    required String provider,
    required List<DeviceHealthSample> samples,
    required bool consent,
    required bool Function() isCurrent,
    required HealthAccessCheck canSend,
  }) async {
    if (!consent) {
      throw const HealthDataException(
        'Sunucuya aktarım için açık onayınız gerekiyor.',
      );
    }
    if (_running) throw const HealthDataException('Bir aktarım zaten sürüyor.');
    if (!['health_connect', 'health_kit'].contains(provider)) {
      throw const HealthDataException('Desteklenmeyen sağlık sağlayıcısı.');
    }
    final generation = _generation;
    void current() {
      if (generation != _generation || !isCurrent()) {
        throw const HealthReadCancelled();
      }
    }

    _running = true;
    final receipts = <WearableSyncReceipt>[];
    var skipped = 0;
    try {
      current();
      if (_pending == null) {
        _queue = _units(provider, samples);
        _connectionId = null;
      } else {
        final observed = {
          for (final sample in samples) sample.identity: sample,
        };
        for (final unit in _queue) {
          for (final point in unit.samples) {
            final fresh = observed[point.identity];
            if (fresh == null ||
                fresh.rawValue != point.rawValue ||
                fresh.rawUnit != point.rawUnit ||
                fresh.sourceName != point.sourceName ||
                fresh.recordingMethod != point.recordingMethod ||
                fresh.exerciseType != point.exerciseType) {
              cancel();
              throw const HealthDataException(
                'Bekleyen kayıtlar artık başarıyla okunamıyor veya değişmiş. Yeni aktarım hazırlayın.',
              );
            }
          }
        }
      }
      if (_queue.isEmpty) return const HealthSyncOutcome([], 0);
      if (!await canSend(_pending?.samples ?? samples)) {
        cancel();
        throw const HealthDataException(
          'Okuma izni veya kaynak verisi değişmiş. Verileri yeniden okuyun.',
        );
      }
      current();
      var connection = await api.connectionFor(provider);
      current();
      connection ??= await api.connect(provider);
      current();
      if (connection.status != 'active') {
        cancel();
        throw const HealthDataException(
          'Sunucuya aktarım durdurulmuş. Önce açıkça yeniden etkinleştirin.',
        );
      }
      if (_connectionId != null && _connectionId != connection.id) {
        cancel();
        throw const HealthDataException(
          'Bağlantı değişmiş. Aktarımı yeniden hazırlayın.',
        );
      }
      _connectionId = connection.id;
      while (_queue.isNotEmpty) {
        current();
        if (_pending == null) {
          final changes = <Map<String, Object?>>[],
              batchSamples = <DeviceHealthSample>[];
          final keys = <String>{};
          var units = 0;
          while (units < _queue.length && changes.length < 100) {
            final unit = _queue[units], sample = unit.first;
            final key = _key(sample);
            if (keys.contains(key) ||
                batchSamples.length + unit.samples.length > 1000) {
              break;
            }
            final record = await api.record(
              connection.id,
              sample.sourceId,
              sample.rawType,
              sample.externalRecordId,
            );
            current();
            if (record?.isDeleted == true) {
              // A server tombstone is not automatically resurrected by an old OS sample.
              if (changes.isNotEmpty) break;
              _queue.removeAt(0);
              skipped++;
              continue;
            }
            final change = <String, Object?>{
              'operation': 'upsert',
              'metric': metricValue(sample.metric),
              'sourceId': sample.sourceId,
              'externalRecordId': sample.externalRecordId,
              'rawType': sample.rawType,
              'expectedVersionNumber': record?.versionNumber ?? 0,
              'sourceName': sample.sourceName,
              'recordingMethod': sample.recordingMethod,
              'rawUnit': sample.rawUnit,
              if (sample.exerciseType != null)
                'exerciseType': sample.exerciseType,
              'samples': [
                for (final point in unit.samples)
                  {
                    'startedAt': point.start.toUtc().toIso8601String(),
                    'endedAt': point.end.toUtc().toIso8601String(),
                    'rawValue': point.rawValue,
                  },
              ],
            };
            final candidate = {
              'wearableConnectionId': connection.id,
              'batchId': '0' * 36,
              'changes': [...changes, change],
            };
            if (utf8.encode(jsonEncode(candidate)).length > 512000) {
              if (changes.isEmpty) {
                throw const HealthDataException(
                  'Tek kaynak aktarım sınırını aşıyor.',
                );
              }
              break;
            }
            changes.add(change);
            batchSamples.addAll(unit.samples);
            keys.add(key);
            units++;
          }
          if (changes.isEmpty) continue;
          // The retained payload is never modified, including its version numbers.
          _pending = _PendingBatch(
            Map.unmodifiable({
              'wearableConnectionId': connection.id,
              'batchId': _uuid(),
              'changes': List.unmodifiable(changes.map(_freeze)),
            }),
            List.unmodifiable(batchSamples),
            units,
          );
        }
        final batch = _pending!;
        if (!await canSend(batch.samples)) {
          cancel();
          throw const HealthDataException(
            'Okuma izni veya veri değişmiş; bekleyen aktarım gönderilmedi.',
          );
        }
        current();
        final receipt = await api.sync(batch.payload);
        current();
        // An OS revocation after sending cannot undo a committed HTTP request.
        // It does stop the remainder of this foreground transfer immediately.
        final allowed = await canSend(batch.samples);
        current();
        _queue.removeRange(0, batch.units);
        _pending = null;
        receipts.add(receipt);
        if (!allowed) {
          cancel();
          throw const HealthDataException(
            'Sunucunun onayladığı aktarım tamamlandı. İzin değiştiği için kalan aktarım durduruldu.',
          );
        }
      }
      return HealthSyncOutcome(List.unmodifiable(receipts), skipped);
    } on HealthReadCancelled {
      cancel();
      rethrow;
    } on HealthDataException catch (e) {
      final rejected =
          e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 429;
      // A failed preflight GET does not settle an earlier uncertain POST.
      // Keep its exact receipt key through transient metadata/read failures.
      if (!e.uncertain &&
          generation == _generation &&
          (_pending == null || rejected)) {
        cancel();
      }
      rethrow;
    } finally {
      _running = false;
    }
  }

  static String metricValue(DeviceHealthMetric metric) => switch (metric) {
    DeviceHealthMetric.activeEnergy => 'active_energy',
    DeviceHealthMetric.heartRate => 'heart_rate',
    _ => metric.name,
  };
  static String _key(DeviceHealthSample sample) =>
      jsonEncode([sample.sourceId, sample.rawType, sample.externalRecordId]);
  static List<_SyncUnit> _units(
    String provider,
    List<DeviceHealthSample> samples,
  ) {
    final groups = <String, List<DeviceHealthSample>>{};
    final expectedProvider = provider == 'health_connect'
        ? 'healthConnect'
        : 'healthKit';
    bool text(String value, [int max = 200]) =>
        value.isNotEmpty &&
        value.trim() == value &&
        value.runes.length <= max &&
        !value.runes.any((c) => c < 32 || c == 127);
    for (final sample in samples) {
      final expectedUnit = switch (sample.metric) {
        DeviceHealthMetric.steps => 'COUNT',
        DeviceHealthMetric.distance => 'METER',
        DeviceHealthMetric.exercise => 'MINUTE',
        DeviceHealthMetric.activeEnergy => 'KILOCALORIE',
        DeviceHealthMetric.heartRate => 'BEATS_PER_MINUTE',
      };
      if (sample.provider != expectedProvider ||
          !text(sample.sourceId) ||
          !text(sample.externalRecordId) ||
          !text(sample.rawType, 64) ||
          !text(sample.sourceName) ||
          !text(sample.recordingMethod, 64) ||
          sample.rawUnit != expectedUnit ||
          !sample.rawValue.isFinite ||
          sample.rawValue < 0 ||
          sample.rawValue > 1e12 ||
          (sample.metric == DeviceHealthMetric.steps &&
              sample.rawValue != sample.rawValue.truncateToDouble()) ||
          (sample.metric == DeviceHealthMetric.heartRate
              ? sample.start != sample.end || sample.rawValue <= 0
              : !sample.start.isBefore(sample.end)) ||
          sample.end.difference(sample.start) > const Duration(days: 7) ||
          (sample.metric == DeviceHealthMetric.exercise &&
              (sample.exerciseType == null ||
                  !text(sample.exerciseType!) ||
                  (sample.rawValue * 60000 -
                              sample.end
                                      .difference(sample.start)
                                      .inMicroseconds /
                                  1000)
                          .abs() >
                      1))) {
        throw const HealthDataException(
          'Kaynak kimliği, birimi veya zaman aralığı geçersiz; veri gönderilmedi.',
        );
      }
      groups.putIfAbsent(_key(sample), () => []).add(sample);
    }
    final units = <_SyncUnit>[];
    for (final points in groups.values) {
      final first = points.first;
      if (points.any(
        (p) =>
            p.metric != first.metric ||
            p.rawUnit != first.rawUnit ||
            p.sourceName != first.sourceName ||
            p.recordingMethod != first.recordingMethod ||
            p.exerciseType != first.exerciseType,
      )) {
        throw const HealthDataException(
          'Aynı kaynak başlığında tutarsız veri bulundu.',
        );
      }
      final unique = <String, DeviceHealthSample>{};
      for (final point in points) {
        final key = point.start.toUtc().microsecondsSinceEpoch.toString();
        final existing = unique[key];
        if (existing != null &&
            (existing.rawValue != point.rawValue ||
                existing.end != point.end)) {
          throw const HealthDataException('Aynı örnekte çelişen değerler var.');
        }
        unique[key] = point;
      }
      final sorted = unique.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (first.metric != DeviceHealthMetric.heartRate && sorted.length != 1) {
        throw const HealthDataException(
          'Skaler kaynakta birden fazla örnek bulundu.',
        );
      }
      for (var start = 0; start < sorted.length; start += 500) {
        units.add(
          _SyncUnit(
            List.unmodifiable(
              sorted.sublist(start, min(start + 500, sorted.length)),
            ),
          ),
        );
      }
    }
    return units;
  }

  static dynamic _freeze(dynamic value) => switch (value) {
    Map value => Map<String, Object?>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _freeze(v))),
    ),
    List value => List.unmodifiable(value.map(_freeze)),
    _ => value,
  };
  static String _uuid() {
    final random = Random.secure(), bytes = List.generate(16, (_) => 0);
    for (var i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
