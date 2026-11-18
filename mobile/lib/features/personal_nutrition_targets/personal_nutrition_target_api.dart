import 'dart:async';
import 'dart:io';

import '../auth/auth_session.dart';
import '../auth/login_api.dart';

const personalTargetFields = [
  (
    key: 'dailyCaloriesTargetKcal',
    label: 'Kalori',
    unit: 'kcal',
    maximum: 10000,
  ),
  (key: 'dailyProteinTargetGrams', label: 'Protein', unit: 'g', maximum: 1000),
  (
    key: 'dailyCarbsTargetGrams',
    label: 'Karbonhidrat',
    unit: 'g',
    maximum: 1000,
  ),
  (key: 'dailyFatTargetGrams', label: 'Yağ', unit: 'g', maximum: 1000),
  (key: 'dailyWaterTargetMl', label: 'Su', unit: 'mL', maximum: 15000),
];

class PersonalNutritionTargetResponse {
  const PersonalNutritionTargetResponse({
    this.dailyCaloriesTargetKcal,
    this.dailyProteinTargetGrams,
    this.dailyCarbsTargetGrams,
    this.dailyFatTargetGrams,
    this.dailyWaterTargetMl,
  });
  final num? dailyCaloriesTargetKcal,
      dailyProteinTargetGrams,
      dailyCarbsTargetGrams,
      dailyFatTargetGrams,
      dailyWaterTargetMl;
  String get source => 'personal';
  Map<String, num?> get values => {
    'dailyCaloriesTargetKcal': dailyCaloriesTargetKcal,
    'dailyProteinTargetGrams': dailyProteinTargetGrams,
    'dailyCarbsTargetGrams': dailyCarbsTargetGrams,
    'dailyFatTargetGrams': dailyFatTargetGrams,
    'dailyWaterTargetMl': dailyWaterTargetMl,
  };
}

class PersonalNutritionTargetApi {
  PersonalNutritionTargetApi(this.session);
  final AuthSession session;
  static const path = '/api/v1/personal-nutrition-targets';
  Future<PersonalNutritionTargetResponse> get() => _send();
  Future<PersonalNutritionTargetResponse> patch(Map<String, num?> changes) {
    if (changes.isEmpty ||
        changes.entries.any(
          (entry) => !personalTargetFields.any(
            (f) => f.key == entry.key && valid(entry.value, f.maximum),
          ),
        )) {
      throw const PersonalNutritionTargetApiException.invalid();
    }
    return _send(changes: Map<String, num?>.unmodifiable(changes));
  }

  static bool valid(Object? value, num maximum) =>
      value == null ||
      value is num && value.isFinite && value > 0 && value <= maximum;
  static PersonalNutritionTargetResponse _parse(Object? body) {
    if (body is! Map<String, dynamic> ||
        body.length != 6 ||
        body['source'] != 'personal' ||
        personalTargetFields.any(
          (f) => !body.containsKey(f.key) || !valid(body[f.key], f.maximum),
        )) {
      throw const PersonalNutritionTargetApiException.invalid();
    }
    return PersonalNutritionTargetResponse(
      dailyCaloriesTargetKcal: body['dailyCaloriesTargetKcal'] as num?,
      dailyProteinTargetGrams: body['dailyProteinTargetGrams'] as num?,
      dailyCarbsTargetGrams: body['dailyCarbsTargetGrams'] as num?,
      dailyFatTargetGrams: body['dailyFatTargetGrams'] as num?,
      dailyWaterTargetMl: body['dailyWaterTargetMl'] as num?,
    );
  }

  Future<PersonalNutritionTargetResponse> _send({
    Map<String, num?>? changes,
  }) async {
    final mutation = changes != null, owner = session.user?.id;
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: mutation ? 'PATCH' : 'GET',
        payload: changes,
        profileContext: 'client',
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw PersonalNutritionTargetApiException(
          'Oturum değişti. Lütfen tekrar giriş yapın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != 200) {
        throw PersonalNutritionTargetApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 => 'Kişisel hedeflerinize erişim izniniz doğrulanamadı.',
            400 ||
            422 => 'Hedef değerleri kabul edilmedi. Alanları kontrol edin.',
            429 => 'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
            _ => 'Kişisel hedefler şu anda alınamıyor. Lütfen yeniden deneyin.',
          },
          statusCode: response.statusCode,
          uncertain: mutation && response.statusCode >= 500,
        );
      }
      try {
        return _parse(response.body);
      } on PersonalNutritionTargetApiException {
        throw PersonalNutritionTargetApiException.invalid(uncertain: mutation);
      }
    } on LoginApiException catch (error) {
      throw PersonalNutritionTargetApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on HandshakeException {
      throw PersonalNutritionTargetApiException(
        'Sunucuyla güvenli bağlantı kurulamadı.',
        uncertain: mutation,
      );
    } on IOException {
      throw PersonalNutritionTargetApiException(
        'Bağlantı kurulamadı veya kesildi.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw PersonalNutritionTargetApiException(
        'Hedef isteği zaman aşımına uğradı.',
        uncertain: mutation,
      );
    } on FormatException {
      throw PersonalNutritionTargetApiException.invalid(uncertain: mutation);
    }
  }
}

class PersonalNutritionTargetApiException implements Exception {
  const PersonalNutritionTargetApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const PersonalNutritionTargetApiException.invalid({this.uncertain = false})
    : message = 'Hedef yanıtı doğrulanamadı. Lütfen yeniden yükleyin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
}
