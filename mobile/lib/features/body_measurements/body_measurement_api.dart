import 'dart:async';
import 'dart:io';
import '../../core/network/json_api.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';

const measurementLabels = {
  'weightKg': 'Kilo',
  'waistCm': 'Bel',
  'hipCm': 'Kalça',
  'chestCm': 'Göğüs',
  'bodyFatPercent': 'Vücut yağ oranı',
};
String measurementUnit(String key) => key == 'weightKg'
    ? 'kg'
    : key == 'bodyFatPercent'
    ? '%'
    : 'cm';
String measurementValue(num value, {bool minimumDecimal = false}) {
  final fixed = value.toStringAsFixed(3);
  if (!fixed.contains('.') || value != 0 && num.tryParse(fixed) == 0) {
    return value.toString().replaceAll('.', ',');
  }
  final parts = fixed.split('.');
  var fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  if (fraction.isEmpty && minimumDecimal) fraction = '0';
  return fraction.isEmpty ? parts[0] : '${parts[0]},$fraction';
}

const measurementMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
String measurementDate(DateTime value, {bool year = true}) {
  final local = value.toLocal();
  return '${local.day} ${measurementMonths[local.month - 1]}${year ? ' ${local.year}' : ''}';
}

String measurementClock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String measurementSource(String source) => switch (source) {
  'manual' => 'Manuel',
  'wearable' => 'Cihaz',
  _ => 'AI destekli',
};
String formatMeasurementTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day}.${local.month}.${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.clientId,
    required this.measuredAt,
    required this.source,
    this.weightKg,
    this.waistCm,
    this.hipCm,
    this.chestCm,
    this.bodyFatPercent,
    this.note,
  });
  final String id, clientId, source;
  final DateTime measuredAt;
  final num? weightKg, waistCm, hipCm, chestCm, bodyFatPercent;
  final String? note;
  Map<String, num?> get values => {
    'weightKg': weightKg,
    'waistCm': waistCm,
    'hipCm': hipCm,
    'chestCm': chestCm,
    'bodyFatPercent': bodyFatPercent,
  };
  bool get canEdit => source == 'manual';
}

typedef BodyMeasurementPage = ({List<BodyMeasurement> items, int totalCount});

class BodyMeasurementApi {
  BodyMeasurementApi(this.session);
  final AuthSession session;
  static const _root = '/api/v1/body-measurements';
  Future<BodyMeasurementPage> list({
    int page = 1,
    int pageSize = 10,
    String sortOrder = 'desc',
    DateTime? from,
    DateTime? to,
  }) async {
    final path = Uri(
      path: _root,
      queryParameters: {
        'page': '$page',
        'pageSize': '$pageSize',
        'sortOrder': sortOrder,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
    ).toString();
    final row = _object((await _send(path)).body, ['items', 'totalCount']);
    if (row['items'] is! List ||
        row['totalCount'] is! int ||
        (row['totalCount'] as int) < 0) {
      throw const BodyMeasurementApiException.invalid();
    }
    final items = (row['items'] as List).map(_record).toList(growable: false);
    if (items.length > pageSize ||
        (items.isNotEmpty &&
            (page - 1) * pageSize + items.length >
                (row['totalCount'] as int)) ||
        items.map((x) => x.id).toSet().length != items.length ||
        items.map((x) => x.clientId).toSet().length > 1) {
      throw const BodyMeasurementApiException.invalid();
    }
    return (
      items: List<BodyMeasurement>.unmodifiable(items),
      totalCount: row['totalCount'] as int,
    );
  }

  Future<List<BodyMeasurement>> history() async {
    final owner = session.user?.id;
    final rows = <BodyMeasurement>[];
    final ids = <String>{};
    int? total;
    for (var page = 1; ; page++) {
      final result = await list(page: page, pageSize: 100, sortOrder: 'asc');
      if (owner == null ||
          !session.isAuthenticated ||
          session.user?.id != owner) {
        throw const BodyMeasurementApiException(
          'Oturum değişti.',
          statusCode: 401,
        );
      }
      total ??= result.totalCount;
      if (total != result.totalCount ||
          result.items.isEmpty && rows.length < total) {
        throw const BodyMeasurementApiException.invalid();
      }
      for (final row in result.items) {
        if (!ids.add(row.id) ||
            rows.isNotEmpty &&
                (row.clientId != rows.first.clientId ||
                    row.measuredAt.isBefore(rows.last.measuredAt) ||
                    row.measuredAt == rows.last.measuredAt &&
                        row.id.compareTo(rows.last.id) < 0)) {
          throw const BodyMeasurementApiException.invalid();
        }
        rows.add(row);
      }
      if (rows.length == total) return List.unmodifiable(rows);
    }
  }

  Future<BodyMeasurement> get(String id) async {
    _checkId(id);
    final row = _record((await _send('$_root/$id')).body);
    if (row.id != id) throw const BodyMeasurementApiException.invalid();
    return row;
  }

  Future<BodyMeasurement> create({
    required Map<String, num?> values,
    required DateTime measuredAt,
    String? note,
  }) {
    if (values.keys.any((key) => !measurementLabels.containsKey(key))) {
      throw const BodyMeasurementApiException.invalid();
    }
    return _write(
      _root,
      {
        'measuredAt': measuredAt.toUtc().toIso8601String(),
        'source': 'manual',
        ...values,
        'note': note,
      },
      'POST',
      201,
    );
  }

  Future<BodyMeasurement> update(
    String id,
    Map<String, Object?> changes,
  ) async {
    _checkId(id);
    if (changes.isEmpty ||
        changes.keys.any(
          (key) =>
              !measurementLabels.containsKey(key) &&
              key != 'measuredAt' &&
              key != 'note',
        )) {
      throw const BodyMeasurementApiException.invalid();
    }
    final row = await _write('$_root/$id', changes, 'PATCH', 200);
    if (row.id != id) {
      throw const BodyMeasurementApiException.invalid(uncertain: true);
    }
    return row;
  }

  Future<void> delete(String id) async {
    _checkId(id);
    final response = await _send('$_root/$id', method: 'DELETE', expected: 204);
    if (response.hasBody) {
      throw const BodyMeasurementApiException.invalid(uncertain: true);
    }
  }

  Future<BodyMeasurement> _write(
    String path,
    Map<String, Object?> body,
    String method,
    int expected,
  ) async {
    final response = await _send(
      path,
      method: method,
      body: body,
      expected: expected,
    );
    try {
      return _record(response.body);
    } on BodyMeasurementApiException {
      throw const BodyMeasurementApiException.invalid(uncertain: true);
    }
  }

  Future<JsonApiResponse> _send(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    int expected = 200,
  }) async {
    final owner = session.user?.id, mutation = method != 'GET';
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: method,
        payload: body,
        profileContext: 'client',
        maxResponseBytes: 1048576,
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw BodyMeasurementApiException(
          'Oturum değişti. Lütfen tekrar giriş yapın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != expected) {
        throw BodyMeasurementApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 => 'Ölçüm kayıtlarına erişim izniniz doğrulanamadı.',
            404 => 'Ölçüm kaydı bulunamadı veya artık erişilemiyor.',
            400 || 422 =>
              'Ölçüm veya tarih bilgisi kabul edilmedi. Alanları kontrol edin.',
            429 => 'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
            _ => 'Ölçüm servisi şu anda kullanılamıyor. Durumu yenileyin.',
          },
          statusCode: response.statusCode,
          uncertain: mutation && response.statusCode >= 500,
        );
      }
      return response;
    } on LoginApiException catch (error) {
      throw BodyMeasurementApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on HandshakeException {
      throw BodyMeasurementApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Sertifika ayarlarını kontrol edin.',
        uncertain: mutation,
      );
    } on IOException {
      throw BodyMeasurementApiException(
        'Bağlantı kurulamadı veya kesildi.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw BodyMeasurementApiException(
        'Ölçüm kaydı isteği zaman aşımına uğradı.',
        uncertain: mutation,
      );
    } on FormatException {
      throw BodyMeasurementApiException.invalid(uncertain: mutation);
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const BodyMeasurementApiException.invalid();
    }
    return value;
  }

  static bool _uuid(Object? value) =>
      value is String &&
      value != '00000000-0000-0000-0000-000000000000' &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);
  static void _checkId(String id) {
    if (!_uuid(id)) throw const BodyMeasurementApiException.invalid();
  }

  static DateTime _instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const BodyMeasurementApiException.invalid();
    }
    final instant = DateTime.tryParse(value);
    if (instant == null) throw const BodyMeasurementApiException.invalid();
    return instant.toUtc();
  }

  static BodyMeasurement _record(Object? value) {
    final row = _object(value, [
      'id',
      'clientId',
      'measuredAt',
      'source',
      ...measurementLabels.keys,
      'note',
    ]);
    if (!_uuid(row['id']) ||
        !_uuid(row['clientId']) ||
        !const ['manual', 'wearable', 'ai_assisted'].contains(row['source']) ||
        !(row['note'] == null || row['note'] is String)) {
      throw const BodyMeasurementApiException.invalid();
    }
    final values = <String, num?>{};
    for (final key in measurementLabels.keys) {
      final number = row[key];
      if (number != null &&
          (number is! num ||
              !number.isFinite ||
              (key == 'bodyFatPercent'
                  ? number < 0 || number > 100
                  : number <= 0))) {
        throw const BodyMeasurementApiException.invalid();
      }
      values[key] = number as num?;
    }
    if (values.values.every((v) => v == null)) {
      throw const BodyMeasurementApiException.invalid();
    }
    return BodyMeasurement(
      id: row['id'],
      clientId: row['clientId'],
      measuredAt: _instant(row['measuredAt']),
      source: row['source'],
      weightKg: values['weightKg'],
      waistCm: values['waistCm'],
      hipCm: values['hipCm'],
      chestCm: values['chestCm'],
      bodyFatPercent: values['bodyFatPercent'],
      note: row['note'],
    );
  }
}

class BodyMeasurementApiException implements Exception {
  const BodyMeasurementApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const BodyMeasurementApiException.invalid({this.uncertain = false})
    : message = 'Ölçüm yanıtı doğrulanamadı. Durumu yenileyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
}
