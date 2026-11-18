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

class DataSharingPermission {
  const DataSharingPermission({
    required this.id,
    required this.relationshipId,
    required this.isGranted,
    this.category = 'nutrition_plans',
  });
  final String id, relationshipId, category;
  final bool isGranted;
}

typedef DietitianPage<T> = ({List<T> items, int totalCount});
typedef DietitianStatusResponse = ({
  String id,
  String displayName,
  bool isVerified,
});
typedef ClientListItem = ({String id, String displayName});

class DietitianApi {
  DietitianApi(this.session);
  final AuthSession session;
  static const pageSize = 10;
  static const sharingCategories = [
    'nutrition_plans',
    'meal_logs',
    'body_measurements',
  ];

  Future<DietitianStatusResponse?> profile() => _safe(() async {
    final response = await session.authorizedRequest(
      path: '/api/v1/dietitians/me',
    );
    if (response.statusCode == 404) return null;
    _success(response, 200);
    return _profile(response.body);
  });

  Future<DietitianStatusResponse> applyExisting(
    String displayName,
    String licenseInfo,
  ) => _safe(() async {
    final response = await session.authorizedRequest(
      path: '/api/v1/dietitians/me/application',
      payload: {'displayName': displayName, 'licenseInfo': licenseInfo},
    );
    if (response.statusCode == 409) {
      throw const DietitianApiException(
        'Bu hesabın zaten bir başvurusu var. Durumu yenileyin.',
        statusCode: 409,
      );
    }
    _success(response, 201);
    final result = _profile(response.body);
    if (result.isVerified) throw const DietitianApiException.invalidResponse();
    return result;
  });

  Future<DietitianPage<ClientListItem>> clients(int page) => _safe(() async {
    final response = await session.authorizedRequest(
      path: '/api/v1/dietitian/clients?page=$page&pageSize=$pageSize',
      profileContext: 'dietitian',
    );
    _success(response, 200, asDietitian: true);
    return _page<ClientListItem>(response.body, (value) {
      final row = _object(value, const ['id', 'displayName']);
      if (!_uuid(row['id']) ||
          row['displayName'] is! String ||
          (row['displayName'] as String).trim().isEmpty) {
        throw const DietitianApiException.invalidResponse();
      }
      return (
        id: row['id'] as String,
        displayName: row['displayName'] as String,
      );
    }, (item) => item.id);
  });

  Future<({String invitationCode, DateTime expiresAt})> invitation() => _safe(
    () async {
      final response = await session.authorizedRequest(
        path: '/api/v1/dietitians/me/invitation-code',
        method: 'POST',
        profileContext: 'dietitian',
      );
      _success(response, 200, asDietitian: true);
      final row = _object(response.body, const ['invitationCode', 'expiresAt']);
      final code = row['invitationCode'];
      final expiresAt = row['expiresAt'] is String
          ? DateTime.tryParse(row['expiresAt'] as String)
          : null;
      if (code is! String ||
          !RegExp(r'^[A-Z2-7]{16}$').hasMatch(code) ||
          expiresAt == null ||
          !expiresAt.isUtc) {
        throw const DietitianApiException.invalidResponse();
      }
      return (invitationCode: code, expiresAt: expiresAt);
    },
  );

  static DietitianStatusResponse _profile(Object? value) {
    final row = _object(value, const ['id', 'displayName', 'isVerified']);
    if (!_uuid(row['id']) ||
        row['displayName'] is! String ||
        (row['displayName'] as String).trim().isEmpty ||
        row['isVerified'] is! bool) {
      throw const DietitianApiException.invalidResponse();
    }
    return (
      id: row['id'] as String,
      displayName: row['displayName'] as String,
      isVerified: row['isVerified'] as bool,
    );
  }

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
  }) => _relationships(status, page);

  Future<DietitianPage<RelationshipResponse>> expertRelationships({
    required String status,
    required String dietitianId,
    int page = 1,
  }) => _relationships(status, page, dietitianId: dietitianId);

  Future<DietitianPage<RelationshipResponse>> _relationships(
    String status,
    int page, {
    String? dietitianId,
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
      profileContext: dietitianId == null ? 'client' : 'dietitian',
    );
    _success(response, 200, asDietitian: dietitianId != null);
    final result = _page(response.body, _relationship, (item) => item.id);
    if (result.items.any(
          (row) =>
              row.status != status ||
              (dietitianId != null && row.dietitianId != dietitianId),
        ) ||
        (dietitianId == null &&
            status == 'active' &&
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

  Future<RelationshipResponse> endRelationship(
    RelationshipResponse relationship,
  ) => changeRelationship(relationship, 'end');

  Future<RelationshipResponse> changeRelationship(
    RelationshipResponse relationship,
    String action, {
    bool asDietitian = false,
  }) => _safe(() async {
    final expected = switch (action) {
      'accept' when asDietitian => 'active',
      'reject' when asDietitian => 'rejected',
      'end' => 'ended',
      _ => null,
    };
    if (!_uuid(relationship.id) ||
        expected == null ||
        (relationship.status != 'pending' &&
            (action != 'end' || relationship.status != 'active'))) {
      throw const DietitianApiException(
        'Bağlantının durumu bu işleme uygun değil.',
      );
    }
    final response = await session.authorizedRequest(
      path: '/api/v1/dietitian-relationships/${relationship.id}/$action',
      method: 'POST',
      profileContext: asDietitian ? 'dietitian' : 'client',
    );
    _success(response, 200, connectionAction: true, asDietitian: asDietitian);
    final result = _relationship(response.body);
    if (result.id != relationship.id ||
        result.clientId != relationship.clientId ||
        result.dietitianId != relationship.dietitianId ||
        result.status != expected) {
      throw const DietitianApiException.invalidResponse();
    }
    return result;
  });

  Future<DataSharingPermission?> permission(String relationshipId) async =>
      (await permissions(
        relationshipId,
      )).where((row) => row.category == 'nutrition_plans').firstOrNull;

  Future<List<DataSharingPermission>> permissions(String relationshipId) =>
      _safe(() async {
        if (!_uuid(relationshipId)) {
          throw const DietitianApiException.invalidResponse();
        }
        final owner = session.user?.id;
        final rows = <DataSharingPermission>[];
        int? expected;
        for (var page = 1; ; page++) {
          final path = Uri(
            path: '/api/v1/data-sharing-permissions',
            queryParameters: {
              'relationshipId': relationshipId,
              'page': '$page',
              'pageSize': '$pageSize',
            },
          );
          final response = await session.authorizedRequest(
            path: path.toString(),
            profileContext: 'client',
          );
          _permissionOwner(owner);
          _success(response, 200, connectionAction: true);
          final result = _page(response.body, _permission, (row) => row.id);
          expected ??= result.totalCount;
          rows.addAll(result.items);
          if (result.totalCount != expected ||
              expected > sharingCategories.length ||
              (result.items.isEmpty && rows.length < expected) ||
              rows.length > expected ||
              rows.map((row) => row.category).toSet().length != rows.length ||
              rows.map((row) => row.id).toSet().length != rows.length ||
              rows.any((row) => row.relationshipId != relationshipId)) {
            throw const DietitianApiException.invalidResponse();
          }
          if (rows.length == expected) {
            return List<DataSharingPermission>.unmodifiable(rows);
          }
        }
      });

  void _permissionOwner(String? owner) {
    if (owner == null ||
        !session.isAuthenticated ||
        session.user?.id != owner) {
      throw const DietitianApiException(
        'Oturum değişti. Paylaşım durumunu yeniden yükleyin.',
        statusCode: 401,
      );
    }
  }

  Future<DataSharingPermission> setPermission({
    required String relationshipId,
    required bool isGranted,
    DataSharingPermission? current,
    String category = 'nutrition_plans',
  }) => _safe(() async {
    if (!_uuid(relationshipId) ||
        !sharingCategories.contains(category) ||
        (current != null &&
            (!_uuid(current.id) ||
                current.relationshipId != relationshipId ||
                current.category != category))) {
      throw const DietitianApiException.invalidResponse();
    }
    final owner = session.user?.id;
    final response = await session.authorizedRequest(
      path: current == null
          ? '/api/v1/data-sharing-permissions'
          : '/api/v1/data-sharing-permissions/${current.id}',
      method: current == null ? 'POST' : 'PATCH',
      profileContext: 'client',
      payload: {
        if (current == null) ...{
          'relationshipId': relationshipId,
          'category': category,
        },
        'isGranted': isGranted,
      },
    );
    _permissionOwner(owner);
    _success(response, current == null ? 201 : 200, connectionAction: true);
    final result = _permission(response.body);
    if (result.relationshipId != relationshipId ||
        result.category != category ||
        result.isGranted != isGranted ||
        (current != null && current.id != result.id)) {
      throw const DietitianApiException.invalidResponse();
    }
    return result;
  });

  static DataSharingPermission _permission(Object? value) {
    final row = _object(value, const [
      'id',
      'relationshipId',
      'category',
      'isGranted',
      'consentRecordId',
      'createdAt',
      'updatedAt',
    ]);
    DateTime? time(Object? value) =>
        value is String && RegExp(r'(Z|\+00:00)$').hasMatch(value)
        ? DateTime.tryParse(value)
        : null;
    final created = time(row['createdAt']), updated = time(row['updatedAt']);
    if (!_uuid(row['id']) ||
        !_uuid(row['relationshipId']) ||
        !sharingCategories.contains(row['category']) ||
        row['isGranted'] is! bool ||
        row['consentRecordId'] != null ||
        created == null ||
        updated == null ||
        updated.isBefore(created)) {
      throw const DietitianApiException.invalidResponse();
    }
    return DataSharingPermission(
      id: row['id'] as String,
      relationshipId: row['relationshipId'] as String,
      isGranted: row['isGranted'] as bool,
      category: row['category'] as String,
    );
  }

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
            (row['respondedAt'] == null || row['endedAt'] != null)) ||
        (row['status'] == 'rejected' &&
            (row['respondedAt'] == null || row['endedAt'] != null)) ||
        (row['status'] == 'ended' && row['endedAt'] == null)) {
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
    bool connectionAction = false,
    bool asDietitian = false,
  }) {
    if (response.statusCode == status) return;
    final code = apiErrorCode(response.body);
    final message = switch ((response.statusCode, code)) {
      (401, _) => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
      (403, _) when asDietitian =>
        'Bu işlem için onaylı diyetisyen erişimi gerekiyor.',
      (403, _) =>
        'Bu işlem için danışan profilinizle erişim izniniz bulunmuyor.',
      (404, _) when connectionAction =>
        'Bağlantı veya paylaşım izni bulunamadı. Güncel durumu yenileyin.',
      (404, _) => 'Diyetisyen artık erişilebilir değil. Listeyi yenileyin.',
      (409, 'active_relationship_conflict') when asDietitian =>
        'Danışanın zaten aktif bir diyetisyeni var. Mevcut bağlantı sonlanınca talebi kabul edebilirsiniz.',
      (409, 'active_relationship_conflict') =>
        'Zaten aktif bir diyetisyeniniz var. Yeni istek için önce mevcut bağlantınızı sonlandırın.',
      (409, _) when connectionAction =>
        'Bağlantı veya paylaşım durumu değişmiş olabilir. Tekrar işlem yapmadan yenileyin.',
      (409, _) =>
        'Bekleyen isteğiniz veya aktif diyetisyeniniz olabilir. Bağlantılarınızı yenileyin.',
      (422, _) when invitation =>
        'Davet kodu geçersiz, süresi dolmuş veya kullanılmış olabilir. Kodu ve seçiminizi kontrol edin.',
      (422, _) when connectionAction =>
        'Paylaşım veya bağlantı bilgileri doğrulanamadı. Güncel durumu yenileyin.',
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
      code: code,
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
  const DietitianApiException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.code,
  });
  const DietitianApiException.invalidResponse()
    : message = 'Sunucu yanıtı doğrulanamadı. Bağlantılarınızı yenileyin.',
      statusCode = null,
      code = null,
      retryAfter = null;
  final String message;
  final int? statusCode;
  final String? code;
  final Duration? retryAfter;
  @override
  String toString() => 'DietitianApiException';
}
