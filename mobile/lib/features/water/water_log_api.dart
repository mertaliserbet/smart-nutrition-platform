import 'dart:async';
import 'dart:io';
import '../../core/network/json_api.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';

class WaterDayRange {
  const WaterDayRange(this.from, this.to);
  factory WaterDayRange.forDate(
    DateTime date, {
    DateTime Function(int, int, int)? localDate,
  }) {
    final create =
        localDate ?? (year, month, day) => DateTime(year, month, day);
    // Construct two local midnights independently: a calendar day is not always 24 hours.
    return WaterDayRange(
      create(date.year, date.month, date.day),
      create(date.year, date.month, date.day + 1),
    );
  }
  final DateTime from, to;
  String get key => '${waterOffsetIso(from)}/${waterOffsetIso(to)}';
  Map<String, String> get query => {
    'from': waterOffsetIso(from),
    'to': waterOffsetIso(to),
  };
}

String waterOffsetIso(DateTime value) {
  if (value.isUtc) return value.toIso8601String();
  final offset = value.timeZoneOffset;
  final absolute = offset.abs();
  return '${value.toIso8601String()}${offset.isNegative ? '-' : '+'}'
      '${absolute.inHours.toString().padLeft(2, '0')}:${(absolute.inMinutes % 60).toString().padLeft(2, '0')}';
}

class WaterLog {
  const WaterLog({
    required this.id,
    required this.clientId,
    required this.amountMl,
    required this.consumedAt,
    required this.source,
  });
  final String id, clientId, source;
  final num amountMl;
  final DateTime consumedAt;
}

typedef WaterLogPage = ({List<WaterLog> items, int totalCount});

class WaterLogApi {
  WaterLogApi(this.session);
  final AuthSession session;
  static const pageSize = 10;
  static const _root = '/api/v1/water-logs';

  Future<num> dailyTotal(WaterDayRange day) async {
    final path = Uri(
      path: '$_root/daily-total',
      queryParameters: day.query,
    ).toString();
    final row = _object((await _send(path)).body, [
      'from',
      'to',
      'totalAmountMl',
    ]);
    final total = row['totalAmountMl'];
    if (!_instant(row['from']).isAtSameMomentAs(day.from.toUtc()) ||
        !_instant(row['to']).isAtSameMomentAs(day.to.toUtc()) ||
        total is! num ||
        !total.isFinite ||
        total < 0) {
      throw const WaterLogApiException.invalid();
    }
    return total;
  }

  Future<WaterLogPage> list({int page = 1}) async {
    final row = _object(
      (await _send('$_root?page=$page&pageSize=$pageSize')).body,
      ['items', 'totalCount'],
    );
    if (row['items'] is! List ||
        row['totalCount'] is! int ||
        (row['totalCount'] as int) < 0) {
      throw const WaterLogApiException.invalid();
    }
    final items = (row['items'] as List)
        .map<WaterLog>(_record)
        .toList(growable: false);
    if (items.length > pageSize ||
        items.length > (row['totalCount'] as int) ||
        items.map((x) => x.id).toSet().length != items.length ||
        items.map((x) => x.clientId).toSet().length > 1) {
      throw const WaterLogApiException.invalid();
    }
    return (
      items: List<WaterLog>.unmodifiable(items),
      totalCount: row['totalCount'] as int,
    );
  }

  Future<WaterLog> get(String id) async {
    _checkId(id);
    final row = _record((await _send('$_root/$id')).body);
    if (row.id != id) throw const WaterLogApiException.invalid();
    return row;
  }

  Future<WaterLog> create({
    required num amountMl,
    required DateTime consumedAt,
  }) => _write(
    _root,
    {
      'amountMl': amountMl,
      'consumedAt': waterOffsetIso(consumedAt),
      'source': 'manual',
    },
    'POST',
    201,
  );
  Future<WaterLog> update(
    String id, {
    required num amountMl,
    required DateTime consumedAt,
  }) async {
    _checkId(id);
    final row = await _write(
      '$_root/$id',
      {'amountMl': amountMl, 'consumedAt': waterOffsetIso(consumedAt)},
      'PATCH',
      200,
    );
    if (row.id != id) throw const WaterLogApiException.invalid(uncertain: true);
    return row;
  }

  Future<void> delete(String id) async {
    _checkId(id);
    final response = await _send('$_root/$id', method: 'DELETE', expected: 204);
    if (response.hasBody) {
      throw const WaterLogApiException.invalid(uncertain: true);
    }
  }

  Future<WaterLog> _write(
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
    } on WaterLogApiException {
      throw const WaterLogApiException.invalid(uncertain: true);
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
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw WaterLogApiException(
          'Oturum değişti. Lütfen tekrar giriş yapın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != expected) {
        throw WaterLogApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 => 'Su kayıtlarına erişim izniniz doğrulanamadı.',
            404 => 'Su kaydı bulunamadı veya artık erişilemiyor.',
            400 || 422 =>
              'Miktar veya tarih bilgisi kabul edilmedi. Alanları kontrol edin.',
            429 => 'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
            _ =>
              'Su tüketimi servisi şu anda kullanılamıyor. Durumu yenileyin.',
          },
          statusCode: response.statusCode,
          uncertain: mutation && response.statusCode >= 500,
        );
      }
      return response;
    } on LoginApiException catch (error) {
      throw WaterLogApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on HandshakeException {
      throw WaterLogApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Sertifika ayarlarını kontrol edin.',
        uncertain: mutation,
      );
    } on IOException {
      throw WaterLogApiException(
        'Bağlantı kurulamadı veya kesildi.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw WaterLogApiException(
        'Su kaydı isteği zaman aşımına uğradı.',
        uncertain: mutation,
      );
    } on FormatException {
      throw WaterLogApiException.invalid(uncertain: mutation);
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const WaterLogApiException.invalid();
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
    if (!_uuid(id)) throw const WaterLogApiException.invalid();
  }

  static DateTime _instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const WaterLogApiException.invalid();
    }
    final instant = DateTime.tryParse(value);
    if (instant == null) throw const WaterLogApiException.invalid();
    return instant.toUtc();
  }

  static WaterLog _record(Object? value) {
    final row = _object(value, [
      'id',
      'clientId',
      'amountMl',
      'consumedAt',
      'source',
    ]);
    final amount = row['amountMl'];
    if (!_uuid(row['id']) ||
        !_uuid(row['clientId']) ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        !const ['manual', 'wearable', 'ai_assisted'].contains(row['source'])) {
      throw const WaterLogApiException.invalid();
    }
    return WaterLog(
      id: row['id'],
      clientId: row['clientId'],
      amountMl: amount,
      consumedAt: _instant(row['consumedAt']),
      source: row['source'],
    );
  }
}

class WaterLogApiException implements Exception {
  const WaterLogApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const WaterLogApiException.invalid({this.uncertain = false})
    : message = 'Su tüketimi yanıtı doğrulanamadı. Durumu yenileyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
}
