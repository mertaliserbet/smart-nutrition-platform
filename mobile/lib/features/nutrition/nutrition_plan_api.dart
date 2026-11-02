import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';

const nutritionMealLabels = <String, String>{
  'breakfast': 'Kahvaltı',
  'lunch': 'Öğle',
  'dinner': 'Akşam',
  'snack': 'Ara öğün',
  'other': 'Diğer',
};

class NutritionPlanItem {
  const NutritionPlanItem({
    required this.id,
    required this.nutritionPlanId,
    required this.dayOfWeek,
    required this.mealType,
    required this.description,
    required this.recommendedQuantity,
    required this.sortOrder,
    required this.alternativeGroupId,
  });
  final String id, nutritionPlanId, mealType, description;
  final int? dayOfWeek;
  final String? recommendedQuantity, alternativeGroupId;
  final int sortOrder;
}

class NutritionPlanResponse {
  const NutritionPlanResponse({
    required this.id,
    required this.clientId,
    required this.dietitianId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.dailyCaloriesTargetKcal,
    required this.dailyWaterTargetMl,
    required this.createdAt,
    required this.versionId,
    required this.versionNumber,
    required this.items,
  });
  final String id, clientId, title, startDate, versionId;
  final String? dietitianId, endDate;
  final num? dailyCaloriesTargetKcal, dailyWaterTargetMl;
  final DateTime createdAt;
  final int versionNumber;
  final List<NutritionPlanItem> items;
}

class NutritionPlanApi {
  NutritionPlanApi(this.session);
  final AuthSession session;

  Future<NutritionPlanResponse?> active() async {
    try {
      final response = await session.authorizedRequest(
        path: '/api/v1/nutrition-plans/active',
        profileContext: 'client',
        // A full 100-item program can exceed the default small Auth response cap.
        maxResponseBytes: 1024 * 1024,
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        final code = apiErrorCode(response.body);
        throw NutritionPlanApiException(switch ((response.statusCode, code)) {
          (401, _) => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
          (403, _) => 'Beslenme programınıza erişim izniniz doğrulanamadı.',
          (429, _) =>
            'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
          (>= 500, _) =>
            'Beslenme programı servisi şu anda kullanılamıyor. Daha sonra tekrar deneyin.',
          _ => 'Beslenme programı alınamadı. Lütfen yeniden deneyin.',
        }, statusCode: response.statusCode);
      }
      return _plan(response.body);
    } on LoginApiException catch (error) {
      throw NutritionPlanApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
      );
    } on HandshakeException {
      throw const NutritionPlanApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Sertifika ve bağlantı ayarlarını kontrol edin.',
      );
    } on IOException {
      throw const NutritionPlanApiException(
        'Bağlantı kurulamadı veya kesildi. Programı yeniden yükleyin.',
      );
    } on TimeoutException {
      throw const NutritionPlanApiException(
        'Program isteği zaman aşımına uğradı. Lütfen yeniden deneyin.',
      );
    } on FormatException {
      throw const NutritionPlanApiException.invalidResponse();
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const NutritionPlanApiException.invalidResponse();
    }
    return value;
  }

  static bool _uuid(Object? value) =>
      value is String &&
      value != '00000000-0000-0000-0000-000000000000' &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);
  static bool _text(Object? value, int max) =>
      value is String && value.trim().isNotEmpty && value.runes.length <= max;
  static bool _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null &&
        date.year >= 1 &&
        date.toIso8601String().substring(0, 10) == value;
  }

  static bool _target(Object? value) =>
      value == null || (value is num && value.isFinite && value > 0);
  static NutritionPlanResponse _plan(Object? value) {
    final row = _object(value, const [
      'id',
      'clientId',
      'dietitianId',
      'title',
      'status',
      'startDate',
      'endDate',
      'dailyCaloriesTargetKcal',
      'dailyWaterTargetMl',
      'createdAt',
      'items',
      'versionId',
      'versionNumber',
    ]);
    final created = row['createdAt'];
    if (!_uuid(row['id']) ||
        !_uuid(row['clientId']) ||
        (row['dietitianId'] != null && !_uuid(row['dietitianId'])) ||
        !_uuid(row['versionId']) ||
        row['status'] != 'active' ||
        !_text(row['title'], 120) ||
        !_date(row['startDate']) ||
        (row['endDate'] != null &&
            (!_date(row['endDate']) ||
                (row['endDate'] as String).compareTo(
                      row['startDate'] as String,
                    ) <
                    0)) ||
        !_target(row['dailyCaloriesTargetKcal']) ||
        !_target(row['dailyWaterTargetMl']) ||
        created is! String ||
        !RegExp(r'(Z|\+00:00)$').hasMatch(created) ||
        DateTime.tryParse(created) == null ||
        row['versionNumber'] is! int ||
        (row['versionNumber'] as int) < 1 ||
        row['items'] is! List ||
        (row['items'] as List).isEmpty ||
        (row['items'] as List).length > 100) {
      throw const NutritionPlanApiException.invalidResponse();
    }
    final items = (row['items'] as List).map((value) {
      final item = _object(value, const [
        'id',
        'nutritionPlanId',
        'dayOfWeek',
        'mealType',
        'description',
        'recommendedQuantity',
        'sortOrder',
        'recipeId',
        'alternativeGroupId',
      ]);
      final day = item['dayOfWeek'];
      if (!_uuid(item['id']) ||
          item['nutritionPlanId'] != row['id'] ||
          (day != null && (day is! int || day < 1 || day > 7)) ||
          !nutritionMealLabels.containsKey(item['mealType']) ||
          !_text(item['description'], 2000) ||
          (item['recommendedQuantity'] != null &&
              !_text(item['recommendedQuantity'], 200)) ||
          item['sortOrder'] is! int ||
          (item['sortOrder'] as int) < 0 ||
          item['recipeId'] != null ||
          (item['alternativeGroupId'] != null &&
              !_uuid(item['alternativeGroupId']))) {
        throw const NutritionPlanApiException.invalidResponse();
      }
      return NutritionPlanItem(
        id: item['id'] as String,
        nutritionPlanId: item['nutritionPlanId'] as String,
        dayOfWeek: day as int?,
        mealType: item['mealType'] as String,
        description: item['description'] as String,
        recommendedQuantity: item['recommendedQuantity'] as String?,
        sortOrder: item['sortOrder'] as int,
        alternativeGroupId: item['alternativeGroupId'] as String?,
      );
    }).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final groups = <String, List<NutritionPlanItem>>{};
    for (final item in items) {
      if (item.alternativeGroupId != null) {
        (groups[item.alternativeGroupId!] ??= []).add(item);
      }
    }
    if (items.map((i) => i.id).toSet().length != items.length ||
        items.map((i) => i.sortOrder).toSet().length != items.length ||
        groups.values.any(
          (group) =>
              group.length < 2 ||
              group.any(
                (item) =>
                    item.dayOfWeek != group.first.dayOfWeek ||
                    item.mealType != group.first.mealType,
              ),
        )) {
      throw const NutritionPlanApiException.invalidResponse();
    }
    return NutritionPlanResponse(
      id: row['id'] as String,
      clientId: row['clientId'] as String,
      dietitianId: row['dietitianId'] as String?,
      title: row['title'] as String,
      startDate: row['startDate'] as String,
      endDate: row['endDate'] as String?,
      dailyCaloriesTargetKcal: row['dailyCaloriesTargetKcal'] as num?,
      dailyWaterTargetMl: row['dailyWaterTargetMl'] as num?,
      createdAt: DateTime.parse(created),
      versionId: row['versionId'] as String,
      versionNumber: row['versionNumber'] as int,
      items: List.unmodifiable(items),
    );
  }
}

class NutritionPlanApiException implements Exception {
  const NutritionPlanApiException(this.message, {this.statusCode});
  const NutritionPlanApiException.invalidResponse()
    : message = 'Program yanıtı doğrulanamadı. Lütfen yeniden yükleyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  @override
  String toString() => 'NutritionPlanApiException';
}
