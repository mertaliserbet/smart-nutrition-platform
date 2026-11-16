import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';

const mealTypeLabels = {
  'breakfast': 'Kahvaltı',
  'lunch': 'Öğle',
  'dinner': 'Akşam',
  'snack': 'Ara öğün',
  'other': 'Diğer',
};

class MealLogItem {
  const MealLogItem({
    required this.id,
    required this.mealLogId,
    required this.displayName,
    required this.isEstimated,
    this.foodItemId,
    this.recipeId,
    this.quantityGrams,
    this.caloriesKcal,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
  });
  final String id, mealLogId, displayName;
  final bool isEstimated;
  final String? foodItemId, recipeId;
  final num? quantityGrams, caloriesKcal, proteinGrams, carbsGrams, fatGrams;
  Map<String, Object?> toInput() => {
    'displayName': displayName,
    'isEstimated': isEstimated,
    'quantityGrams': quantityGrams,
    'caloriesKcal': caloriesKcal,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
  };
}

class MealLog {
  const MealLog({
    required this.id,
    required this.clientId,
    required this.mealType,
    required this.consumedAt,
    required this.createdAt,
    required this.source,
    required this.items,
    this.note,
    this.foodAnalysisId,
  });
  final String id, clientId, mealType, source;
  final DateTime consumedAt, createdAt;
  final String? note, foodAnalysisId;
  final List<MealLogItem> items;
  bool get canEdit =>
      source == 'manual' &&
      foodAnalysisId == null &&
      items.every((item) => item.foodItemId == null && item.recipeId == null);
}

typedef MealLogPage = ({List<MealLog> items, int totalCount});

class MealLogApi {
  MealLogApi(this.session);
  final AuthSession session;
  static const pageSize = 10;
  static const _root = '/api/v1/meal-logs';

  Future<MealLogPage> list({int page = 1}) async {
    final response = await _send('$_root?page=$page&pageSize=$pageSize');
    final body = _object(response.body, ['items', 'totalCount']);
    if (body['items'] is! List ||
        body['totalCount'] is! int ||
        (body['totalCount'] as int) < 0) {
      throw const MealLogApiException.invalid();
    }
    final rows = (body['items'] as List)
        .map<MealLog>(_meal)
        .toList(growable: false);
    if (rows.length > pageSize ||
        rows.length > (body['totalCount'] as int) ||
        rows.map((row) => row.id).toSet().length != rows.length ||
        rows.map((row) => row.clientId).toSet().length > 1) {
      throw const MealLogApiException.invalid();
    }
    return (
      items: List<MealLog>.unmodifiable(rows),
      totalCount: body['totalCount'] as int,
    );
  }

  Future<MealLog> get(String id) async {
    _checkId(id);
    final row = _meal((await _send('$_root/$id')).body);
    if (row.id != id) throw const MealLogApiException.invalid();
    return row;
  }

  Future<MealLog> create(Map<String, Object?> body) async =>
      _mutation(_root, body, method: 'POST', expected: 201);

  Future<MealLog> update(String id, Map<String, Object?> body) async {
    _checkId(id);
    final row = await _mutation(
      '$_root/$id',
      body,
      method: 'PATCH',
      expected: 200,
    );
    if (row.id != id) throw const MealLogApiException.invalid(uncertain: true);
    return row;
  }

  Future<void> delete(String id) async {
    _checkId(id);
    final response = await _send('$_root/$id', method: 'DELETE', expected: 204);
    if (response.hasBody) {
      throw const MealLogApiException.invalid(uncertain: true);
    }
  }

  Future<MealLog> _mutation(
    String path,
    Map<String, Object?> body, {
    required String method,
    required int expected,
  }) async {
    final response = await _send(
      path,
      method: method,
      payload: body,
      expected: expected,
    );
    try {
      return _meal(response.body);
    } on MealLogApiException {
      throw const MealLogApiException.invalid(uncertain: true);
    }
  }

  Future<JsonApiResponse> _send(
    String path, {
    String method = 'GET',
    Map<String, Object?>? payload,
    int expected = 200,
  }) async {
    final mutation = method != 'GET';
    final owner = session.user?.id;
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: method,
        payload: payload,
        profileContext: 'client',
        maxResponseBytes: 4 * 1024 * 1024,
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw MealLogApiException(
          'Oturum değişti. Lütfen tekrar giriş yapın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != expected) {
        throw MealLogApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 => 'Bu öğün işlemine erişim izniniz bulunmuyor.',
            404 => 'Öğün bulunamadı veya artık erişilemiyor.',
            400 ||
            422 => 'Öğün bilgileri kabul edilmedi. Alanları kontrol edin.',
            413 => 'Öğün çok büyük. Besin veya not miktarını azaltın.',
            429 => 'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
            _ => 'Öğün işlemi tamamlanamadı. Durumu yenileyin.',
          },
          statusCode: response.statusCode,
          uncertain: mutation && response.statusCode >= 500,
        );
      }
      return response;
    } on LoginApiException catch (error) {
      throw MealLogApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on HandshakeException {
      throw MealLogApiException(
        'Güvenli bağlantı kurulamadı. Sertifika ayarlarını kontrol edin.',
        uncertain: mutation,
      );
    } on IOException {
      throw MealLogApiException(
        'Bağlantı kurulamadı veya kesildi.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw MealLogApiException(
        'Öğün isteği zaman aşımına uğradı.',
        uncertain: mutation,
      );
    } on FormatException {
      throw MealLogApiException.invalid(uncertain: mutation);
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const MealLogApiException.invalid();
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
    if (!_uuid(id)) throw const MealLogApiException.invalid();
  }

  static DateTime _instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const MealLogApiException.invalid();
    }
    final result = DateTime.tryParse(value);
    if (result == null) throw const MealLogApiException.invalid();
    return result.toUtc();
  }

  static MealLog _meal(Object? value) {
    final row = _object(value, [
      'id',
      'clientId',
      'mealType',
      'consumedAt',
      'note',
      'source',
      'foodAnalysisId',
      'createdAt',
      'items',
    ]);
    if (!_uuid(row['id']) ||
        !_uuid(row['clientId']) ||
        !mealTypeLabels.containsKey(row['mealType']) ||
        !const ['manual', 'wearable', 'ai_assisted'].contains(row['source']) ||
        row['note'] != null && row['note'] is! String ||
        row['foodAnalysisId'] != null && !_uuid(row['foodAnalysisId']) ||
        row['items'] is! List) {
      throw const MealLogApiException.invalid();
    }
    final items = (row['items'] as List)
        .map((value) {
          final item = _object(value, [
            'id',
            'mealLogId',
            'foodItemId',
            'recipeId',
            'displayName',
            'quantityGrams',
            'caloriesKcal',
            'proteinGrams',
            'carbsGrams',
            'fatGrams',
            'isEstimated',
          ]);
          if (!_uuid(item['id']) ||
              item['mealLogId'] != row['id'] ||
              item['displayName'] is! String ||
              (item['displayName'] as String).trim().isEmpty ||
              item['isEstimated'] is! bool ||
              item['foodItemId'] != null && !_uuid(item['foodItemId']) ||
              item['recipeId'] != null && !_uuid(item['recipeId'])) {
            throw const MealLogApiException.invalid();
          }
          for (final key in [
            'quantityGrams',
            'caloriesKcal',
            'proteinGrams',
            'carbsGrams',
            'fatGrams',
          ]) {
            final number = item[key];
            if (number != null &&
                (number is! num ||
                    !number.isFinite ||
                    number < 0 ||
                    key == 'quantityGrams' && number == 0)) {
              throw const MealLogApiException.invalid();
            }
          }
          return MealLogItem(
            id: item['id'],
            mealLogId: row['id'],
            displayName: item['displayName'],
            isEstimated: item['isEstimated'],
            foodItemId: item['foodItemId'],
            recipeId: item['recipeId'],
            quantityGrams: item['quantityGrams'],
            caloriesKcal: item['caloriesKcal'],
            proteinGrams: item['proteinGrams'],
            carbsGrams: item['carbsGrams'],
            fatGrams: item['fatGrams'],
          );
        })
        .toList(growable: false);
    if (items.isEmpty ||
        items.length > 100 ||
        items.map((item) => item.id).toSet().length != items.length) {
      throw const MealLogApiException.invalid();
    }
    return MealLog(
      id: row['id'],
      clientId: row['clientId'],
      mealType: row['mealType'],
      consumedAt: _instant(row['consumedAt']),
      createdAt: _instant(row['createdAt']),
      source: row['source'],
      note: row['note'],
      foodAnalysisId: row['foodAnalysisId'],
      items: List.unmodifiable(items),
    );
  }
}

class MealLogApiException implements Exception {
  const MealLogApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const MealLogApiException.invalid({this.uncertain = false})
    : message = 'Öğün yanıtı doğrulanamadı. Durumu yenileyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
}
