import 'dart:async';
import 'dart:io';

import '../auth/auth_session.dart';
import '../auth/login_api.dart';
import '../water/water_log_api.dart' show WaterDayRange;

class WearableConnection {
  const WearableConnection({
    required this.id,
    required this.provider,
    required this.status,
    required this.versionNumber,
    required this.lastSyncedAt,
    required this.lastAttemptAt,
    required this.lastSyncStatus,
    required this.lastErrorCode,
  });
  final String id, provider, status, lastSyncStatus;
  final int versionNumber;
  final DateTime? lastSyncedAt, lastAttemptAt;
  final String? lastErrorCode;
}

class WearableRecord {
  const WearableRecord({
    required this.id,
    required this.sourceId,
    required this.rawType,
    required this.externalRecordId,
    required this.versionNumber,
    required this.isDeleted,
  });
  final String id, sourceId, rawType, externalRecordId;
  final int versionNumber;
  final bool isDeleted;
}

class ActivityDailySummary {
  const ActivityDailySummary({
    required this.from,
    required this.to,
    required this.values,
    required this.isPartial,
    required this.excludedOverlapCount,
    required this.unallocatedCount,
  });
  final Map<String, num?> values;
  final DateTime from, to;
  final bool isPartial;
  final int excludedOverlapCount, unallocatedCount;
}

class WearableSyncReceipt {
  const WearableSyncReceipt(this.batchId, this.committedAt, this.recordCount);
  final String batchId;
  final DateTime committedAt;
  final int recordCount;
}

class HealthDataApi {
  HealthDataApi(this.session);
  final AuthSession session;
  static const _root = '/api/v1/wearable-connections';
  Future<WearableConnection?> connectionFor(String provider) async {
    _provider(provider);
    final page = object(await _send('$_root?page=1&pageSize=100'));
    final items = page['items'], total = page['totalCount'];
    if (items is! List ||
        total is! int ||
        total != items.length ||
        total > 2 ||
        total < 0) {
      throw const HealthDataException.invalid();
    }
    final rows = items.map(_connection).toList();
    if (rows.map((r) => r.provider).toSet().length != rows.length) {
      throw const HealthDataException.invalid();
    }
    return rows.where((r) => r.provider == provider).firstOrNull;
  }

  Future<WearableConnection> connect(String provider) async {
    _provider(provider);
    final row = _connection(
      await _send(_root, method: 'POST', payload: {'provider': provider}),
    );
    if (row.provider != provider) {
      throw const HealthDataException.invalid(uncertain: true);
    }
    return row;
  }

  Future<WearableConnection> getConnection(String id) async {
    _id(id);
    final row = _connection(await _send('$_root/$id'));
    if (row.id != id) throw const HealthDataException.invalid();
    return row;
  }

  Future<WearableConnection> changeStatus(
    WearableConnection connection,
    String status,
  ) async {
    _id(connection.id);
    if (status != 'active' && status != 'revoked') {
      throw ArgumentError('Invalid status');
    }
    final row = _connection(
      await _send(
        '$_root/${connection.id}',
        method: 'PATCH',
        payload: {
          'expectedVersionNumber': connection.versionNumber,
          'status': status,
        },
      ),
    );
    if (row.id != connection.id || row.status != status) {
      throw const HealthDataException.invalid(uncertain: true);
    }
    return row;
  }

  Future<WearableRecord?> record(
    String connectionId,
    String sourceId,
    String rawType,
    String externalRecordId,
  ) async {
    _id(connectionId);
    final path = Uri(
      path: '$_root/$connectionId/records',
      queryParameters: {
        'page': '1',
        'pageSize': '100',
        'sourceId': sourceId,
        'rawType': rawType,
        'externalRecordId': externalRecordId,
      },
    ).toString();
    final page = object(await _send(path));
    final items = page['items'];
    if (items is! List ||
        page['totalCount'] != items.length ||
        items.length > 1) {
      throw const HealthDataException.invalid();
    }
    if (items.isEmpty) return null;
    final row = object(items.single);
    if (row['wearableConnectionId'] != connectionId ||
        row['sourceId'] != sourceId ||
        row['rawType'] != rawType ||
        row['externalRecordId'] != externalRecordId ||
        row['isDeleted'] is! bool) {
      throw const HealthDataException.invalid();
    }
    return WearableRecord(
      id: _id(row['id']),
      sourceId: sourceId,
      rawType: rawType,
      externalRecordId: externalRecordId,
      versionNumber: _version(row['versionNumber']),
      isDeleted: row['isDeleted'] as bool,
    );
  }

  Future<WearableSyncReceipt> sync(Map<String, Object?> payload) async {
    final body = await _send('$_root/sync', method: 'POST', payload: payload);
    try {
      final row = object(body);
      final records = row['records'];
      if (row['batchId'] != payload['batchId'] ||
          row['wearableConnectionId'] != payload['wearableConnectionId'] ||
          records is! List ||
          records.length != (payload['changes'] as List).length) {
        throw const HealthDataException.invalid();
      }
      final expected = <String, String>{
        for (final change in payload['changes'] as List)
          _sourceKey(change as Map): change['metric'] as String,
      };
      final returned = <String>{};
      for (final item in records) {
        final record = object(item);
        _id(record['id']);
        _version(record['versionNumber']);
        if (record['wearableConnectionId'] != payload['wearableConnectionId'] ||
            record['isDeleted'] != false ||
            !returned.add(_sourceKey(record)) ||
            expected[_sourceKey(record)] != record['metric']) {
          throw const HealthDataException.invalid();
        }
      }
      return WearableSyncReceipt(
        row['batchId'] as String,
        instant(row['committedAt']),
        records.length,
      );
    } on HealthDataException {
      throw const HealthDataException.invalid(uncertain: true);
    }
  }

  static String _sourceKey(Map row) =>
      '${row['sourceId']}\u0000${row['rawType']}\u0000${row['externalRecordId']}';

  Future<ActivityDailySummary> dailySummary(WaterDayRange day) async {
    final row = object(
      await _send(
        Uri(
          path: '/api/v1/activity-logs/daily-summary',
          queryParameters: day.query,
        ).toString(),
      ),
    );
    if (instant(row['from']) != day.from.toUtc() ||
        instant(row['to']) != day.to.toUtc() ||
        row['calculationPolicy'] != 'conservative_overlap_v1' ||
        row['isPartial'] is! bool) {
      throw const HealthDataException.invalid();
    }
    const values = [
      'steps',
      'distanceKm',
      'activeEnergyKcal',
      'exerciseMinutes',
      'heartRateMeanBpm',
      'heartRateMinBpm',
      'heartRateMaxBpm',
    ];
    final totals = <String, num?>{};
    for (final key in values) {
      final value = row[key];
      if (!row.containsKey(key) ||
          value != null && (value is! num || !value.isFinite || value < 0)) {
        throw const HealthDataException.invalid();
      }
      totals[key] = value as num?;
    }
    for (final key in [
      'exerciseCount',
      'heartRateSampleCount',
      'excludedOverlapCount',
      'unallocatedCount',
    ]) {
      if (row[key] is! int || (row[key] as int) < 0) {
        throw const HealthDataException.invalid();
      }
    }
    return ActivityDailySummary(
      from: instant(row['from']),
      to: instant(row['to']),
      values: Map.unmodifiable(totals),
      isPartial: row['isPartial'] as bool,
      excludedOverlapCount: row['excludedOverlapCount'] as int,
      unallocatedCount: row['unallocatedCount'] as int,
    );
  }

  Future<Object?> _send(
    String path, {
    String method = 'GET',
    Map<String, Object?>? payload,
  }) async {
    final owner = session.user?.id, write = method != 'GET';
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: method,
        payload: payload,
        profileContext: 'client',
        maxResponseBytes: 1048576,
      );
      if (owner == null ||
          owner != session.user?.id ||
          !session.isAuthenticated) {
        throw HealthDataException(
          'Oturum değişti. Ekranı yeniden açın.',
          statusCode: 401,
          uncertain: write,
        );
      }
      if (response.statusCode != 200) {
        final body = response.body;
        final error = body is Map ? body['error'] : null;
        final code = error is Map && error['code'] is String
            ? error['code'] as String
            : null;
        throw HealthDataException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 =>
              'Aktarım kapalı veya erişim izniniz yok. Bağlantı durumunu yenileyin.',
            404 => 'Sağlık servisi veya kayıt bulunamadı.',
            409 =>
              'Sunucu kaydı değişmiş. Otomatik üzerine yazılmadı; güncel verilerle yeniden hazırlayın.',
            413 => 'Aktarım sunucunun boyut sınırını aştı.',
            400 || 422 =>
              'Sağlık verisi isteği kabul edilmedi. Veriler değiştirilmedi.',
            429 => 'Çok fazla istek yapıldı. Daha sonra yeniden deneyin.',
            _ => 'Sağlık servisine erişilemedi. Yeniden deneyin.',
          },
          statusCode: response.statusCode,
          code: code,
          uncertain: write && response.statusCode >= 500,
        );
      }
      return response.body;
    } on LoginApiException catch (e) {
      throw HealthDataException(
        e.message,
        statusCode: e.unauthorized ? 401 : null,
        uncertain: write,
      );
    } on IOException {
      throw HealthDataException(
        'Sunucuyla güvenli bağlantı kurulamadı veya kesildi.',
        uncertain: write,
      );
    } on TimeoutException {
      throw HealthDataException(
        'Sağlık isteği zaman aşımına uğradı.',
        uncertain: write,
      );
    } on FormatException {
      throw HealthDataException.invalid(uncertain: write);
    }
  }

  static WearableConnection _connection(Object? value) {
    final row = object(value);
    _id(row['clientId']);
    _provider(row['provider']);
    if (!['active', 'revoked'].contains(row['status']) ||
        !['never', 'succeeded', 'failed'].contains(row['lastSyncStatus']) ||
        !row.containsKey('lastSyncedAt') ||
        !row.containsKey('lastAttemptAt') ||
        (row['lastErrorCode'] != null && row['lastErrorCode'] is! String)) {
      throw const HealthDataException.invalid();
    }
    return WearableConnection(
      id: _id(row['id']),
      provider: row['provider'] as String,
      status: row['status'] as String,
      versionNumber: _version(row['versionNumber']),
      lastSyncedAt: row['lastSyncedAt'] == null
          ? null
          : instant(row['lastSyncedAt']),
      lastAttemptAt: row['lastAttemptAt'] == null
          ? null
          : instant(row['lastAttemptAt']),
      lastSyncStatus: row['lastSyncStatus'] as String,
      lastErrorCode: row['lastErrorCode'] as String?,
    );
  }

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const HealthDataException.invalid();
    }
    return value;
  }

  static DateTime instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const HealthDataException.invalid();
    }
    final date = DateTime.tryParse(value);
    if (date == null) throw const HealthDataException.invalid();
    return date.toUtc();
  }

  static String _id(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
        ).hasMatch(value) ||
        value == '00000000-0000-0000-0000-000000000000') {
      throw const HealthDataException.invalid();
    }
    return value;
  }

  static int _version(Object? value) {
    if (value is! int || value < 1) throw const HealthDataException.invalid();
    return value;
  }

  static void _provider(Object? value) {
    if (!['health_connect', 'health_kit'].contains(value)) {
      throw const HealthDataException.invalid();
    }
  }
}

class HealthDataException implements Exception {
  const HealthDataException(
    this.message, {
    this.statusCode,
    this.code,
    this.uncertain = false,
  });
  const HealthDataException.invalid({this.uncertain = false})
    : message = 'Sağlık servisinden geçerli yanıt alınamadı.',
      statusCode = null,
      code = null;
  final String message;
  final int? statusCode;
  final String? code;
  final bool uncertain;
}
