import 'dart:async';
import 'dart:io';

import '../../core/network/json_api.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';

class DietitianListItem {
  const DietitianListItem(this.id, this.displayName);
  final String id;
  final String displayName;
}

class RelationshipResponse {
  const RelationshipResponse({
    required this.id,
    required this.clientId,
    required this.dietitianId,
    required this.status,
  });
  final String id, clientId, dietitianId, status;
}

typedef DietitianPage<T> = ({List<T> items, int totalCount});

class DietitianApi {
  DietitianApi(this.session);
  final AuthSession session;
  static const pageSize = 10;

  Future<DietitianPage<DietitianListItem>> search({
    required int page,
    String query = '',
  }) => _safe(() async {
    final path = Uri(
      path: '/api/v1/dietitians',
      queryParameters: {
        'page': '$page',
        'pageSize': '$pageSize',
        if (query.trim().isNotEmpty) 'query': query.trim(),
      },
    );
    final response = await session.authorizedRequest(path: path.toString());
    _success(response, 200);
    return _page(response.body, (value) {
      final row = _object(value, const ['id', 'displayName']);
      if (!_uuid(row['id']) ||
          row['displayName'] is! String ||
          (row['displayName'] as String).trim().isEmpty) {
        throw const DietitianApiException.invalidResponse();
      }
      return DietitianListItem(
        row['id'] as String,
        row['displayName'] as String,
      );
    }, (item) => item.id);
  });

  Future<DietitianPage<RelationshipResponse>> relationships({
    required String status,
    int page = 1,
  }) => _safe(() async {
    final path = Uri(
      path: '/api/v1/dietitian-relationships',
      queryParameters: {
        'page': '$page',
        'pageSize': '$pageSize',
        'status': status,
      },
    );
    final response = await session.authorizedRequest(
      path: path.toString(),
      profileContext: 'client',
    );
    _success(response, 200);
    final result = _page(response.body, _relationship, (item) => item.id);
    if (result.items.any((row) => row.status != status) ||
        (status == 'active' &&
            (result.totalCount > 1 ||
                result.items.length != result.totalCount))) {
      throw const DietitianApiException.invalidResponse();
    }
    return result;
  });

  Future<RelationshipResponse> request({
    String? dietitianId,
    String? invitationCode,
  }) => _safe(() async {
    if ((dietitianId == null) == (invitationCode == null) ||
        (dietitianId != null && !_uuid(dietitianId))) {
      throw const DietitianApiException(
        'Bir diyetisyen veya geçerli davet kodu seçin.',
      );
    }
    final code = invitationCode?.trim().toUpperCase();
    if (code != null && !RegExp(r'^[A-Z2-7]{16}$').hasMatch(code)) {
      throw const DietitianApiException(
        'Davet kodu 16 karakter olmalı; A–Z ve 2–7 içermelidir.',
      );
    }
    final response = await session.authorizedRequest(
      path: '/api/v1/dietitian-relationships',
      profileContext: 'client',
      payload: {'dietitianId': ?dietitianId, 'invitationCode': ?code},
    );
    _success(response, 201, invitation: code != null);
    final result = _relationship(response.body);
    if (result.status != 'pending' ||
        (dietitianId != null && result.dietitianId != dietitianId)) {
      throw const DietitianApiException.invalidResponse();
    }
    return result;
  });

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const DietitianApiException.invalidResponse();
    }
    return value;
  }

  static bool _uuid(Object? value) =>
      value is String &&
      value != '00000000-0000-0000-0000-000000000000' &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static RelationshipResponse _relationship(Object? value) {
    final row = _object(value, const [
      'id',
      'clientId',
      'dietitianId',
      'status',
      'requestedAt',
      'respondedAt',
      'endedAt',
    ]);
    bool time(Object? value) =>
        value is String &&
        RegExp(r'(Z|\+00:00)$').hasMatch(value) &&
        DateTime.tryParse(value) != null;
    if (!['id', 'clientId', 'dietitianId'].every((key) => _uuid(row[key])) ||
        !const [
          'pending',
          'active',
          'rejected',
          'ended',
        ].contains(row['status']) ||
        !time(row['requestedAt']) ||
        (row['respondedAt'] != null && !time(row['respondedAt'])) ||
        (row['endedAt'] != null && !time(row['endedAt'])) ||
        (row['status'] == 'pending' &&
            (row['respondedAt'] != null || row['endedAt'] != null)) ||
        (row['status'] == 'active' &&
            (row['respondedAt'] == null || row['endedAt'] != null))) {
      throw const DietitianApiException.invalidResponse();
    }
    return RelationshipResponse(
      id: row['id'] as String,
      clientId: row['clientId'] as String,
      dietitianId: row['dietitianId'] as String,
      status: row['status'] as String,
    );
  }

  static DietitianPage<T> _page<T>(
    Object? value,
    T Function(Object?) parse,
    String Function(T) id,
  ) {
    final body = _object(value, const ['items', 'totalCount']);
    if (body['items'] is! List ||
        body['totalCount'] is! int ||
        (body['totalCount'] as int) < 0) {
      throw const DietitianApiException.invalidResponse();
    }
    final items = (body['items'] as List).map(parse).toList();
    if (items.length > pageSize ||
        body['totalCount'] < items.length ||
        items.map(id).toSet().length != items.length) {
      throw const DietitianApiException.invalidResponse();
    }
    return (items: items, totalCount: body['totalCount'] as int);
  }

  static void _success(
    JsonApiResponse response,
    int status, {
    bool invitation = false,
  }) {
    if (response.statusCode == status) return;
    final code = apiErrorCode(response.body);
    final message = switch ((response.statusCode, code)) {
      (401, _) => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
      (403, _) =>
        'Bu işlem için danışan profilinizle erişim izniniz bulunmuyor.',
      (404, _) => 'Diyetisyen artık erişilebilir değil. Listeyi yenileyin.',
      (409, _) =>
        'Bekleyen isteğiniz veya aktif diyetisyeniniz olabilir. Bağlantılarınızı yenileyin.',
      (422, _) when invitation =>
        'Davet kodu geçersiz, süresi dolmuş veya kullanılmış olabilir. Kodu ve seçiminizi kontrol edin.',
      (422, _) =>
        'Seçilen diyetisyene bağlantı isteği gönderilemedi. Kendinize istek gönderemezsiniz.',
      (429, _) =>
        'Çok fazla istek gönderildi. Bir süre bekleyip tekrar deneyin.',
      (400, 'invalid_request') =>
        'İstek bilgileri doğrulanamadı. Bilgileri kontrol edin.',
      (>= 500, _) =>
        'Diyetisyen servisi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
      _ => 'Sunucu yanıtı doğrulanamadı. Bağlantılarınızı yenileyin.',
    };
    throw DietitianApiException(
      message,
      statusCode: response.statusCode,
      retryAfter: response.retryAfter,
    );
  }

  static Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on LoginApiException catch (error) {
      throw DietitianApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
      );
    } on HandshakeException {
      throw const DietitianApiException(
        'Sunucuyla güvenli bağlantı kurulamadı. Sertifika ve bağlantı ayarlarını kontrol edin.',
      );
    } on IOException {
      throw const DietitianApiException(
        'Bağlantı kurulamadı veya kesildi. İşlem sonucunu bağlantılarınızı yenileyerek kontrol edin.',
      );
    } on TimeoutException {
      throw const DietitianApiException(
        'İstek zaman aşımına uğradı. Tekrar göndermeden bağlantılarınızı yenileyin.',
      );
    } on FormatException {
      throw const DietitianApiException.invalidResponse();
    }
  }
}

class DietitianApiException implements Exception {
  const DietitianApiException(this.message, {this.statusCode, this.retryAfter});
  const DietitianApiException.invalidResponse()
    : message = 'Sunucu yanıtı doğrulanamadı. Bağlantılarınızı yenileyin.',
      statusCode = null,
      retryAfter = null;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  @override
  String toString() => 'DietitianApiException';
}
