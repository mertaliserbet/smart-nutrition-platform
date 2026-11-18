import 'dart:async';
import 'dart:io';

import '../auth/auth_session.dart';
import '../auth/login_api.dart';

class MealLogComment {
  const MealLogComment({
    required this.id,
    required this.mealLogId,
    required this.authorUserId,
    required this.text,
    required this.createdAt,
    required this.parentCommentId,
  });
  final String id, mealLogId, authorUserId, text;
  final DateTime createdAt;
  final String? parentCommentId;
  bool get isRoot => parentCommentId == null;
}

typedef MealLogCommentPage = ({List<MealLogComment> items, int totalCount});

class MealLogCommentApi {
  MealLogCommentApi(this.session);
  final AuthSession session;
  static bool validText(String text) =>
      text.trim().isNotEmpty &&
      !text.contains('\u0000') &&
      text.trim().runes.length <= 2000;
  Future<MealLogCommentPage> list(String mealLogId, {int page = 1}) async {
    _checkId(mealLogId);
    if (page < 1 || (page - 1) * 10 > 2147483647) {
      throw const MealLogCommentApiException.invalid();
    }
    final body = _object(
      await _send(
        '/api/v1/meal-logs/$mealLogId/comments?page=$page&pageSize=10',
      ),
      const ['items', 'totalCount'],
    );
    final values = body['items'], count = body['totalCount'];
    if (values is! List ||
        values.length > 10 ||
        count is! int ||
        count < 0 ||
        (values.isNotEmpty && count < (page - 1) * 10 + values.length)) {
      throw const MealLogCommentApiException.invalid();
    }
    final rows = values.map((value) => _comment(value, mealLogId)).toList();
    if (rows.map((row) => row.id).toSet().length != rows.length ||
        rows.any(
          (row) =>
              row.parentCommentId != null &&
              rows.any(
                (parent) => parent.id == row.parentCommentId && !parent.isRoot,
              ),
        )) {
      throw const MealLogCommentApiException.invalid();
    }
    for (var i = 1; i < rows.length; i++) {
      if (rows[i - 1].createdAt.isAfter(rows[i].createdAt) ||
          (rows[i - 1].createdAt == rows[i].createdAt &&
              rows[i - 1].id.compareTo(rows[i].id) > 0)) {
        throw const MealLogCommentApiException.invalid();
      }
    }
    return (items: List<MealLogComment>.unmodifiable(rows), totalCount: count);
  }

  Future<MealLogComment> reply(
    String mealLogId,
    MealLogComment parent,
    String text,
  ) async {
    _checkId(mealLogId);
    _checkId(parent.id);
    if (parent.mealLogId != mealLogId || !parent.isRoot || !validText(text)) {
      throw const MealLogCommentApiException(
        'Kendi öğününüzdeki diyetisyen yorumuna 1–2000 karakterlik bir yanıt yazın.',
        statusCode: 422,
      );
    }
    final owner = session.user?.id;
    final response = await _send(
      '/api/v1/meal-logs/$mealLogId/comments',
      payload: {'text': text.trim(), 'parentCommentId': parent.id},
    );
    try {
      final row = _comment(response, mealLogId);
      if (row.parentCommentId != parent.id ||
          row.text != text.trim() ||
          row.authorUserId != owner) {
        throw const MealLogCommentApiException.invalid();
      }
      return row;
    } on MealLogCommentApiException {
      throw const MealLogCommentApiException.invalid(uncertain: true);
    }
  }

  Future<Object?> _send(String path, {Map<String, Object?>? payload}) async {
    final owner = session.user?.id, mutation = payload != null;
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: mutation ? 'POST' : 'GET',
        payload: payload,
        profileContext: 'client',
        maxResponseBytes: 256 * 1024,
      );
      if (!session.isAuthenticated ||
          owner == null ||
          session.user?.id != owner) {
        throw MealLogCommentApiException(
          'Oturum değişti. Lütfen yeniden giriş yapın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != (mutation ? 201 : 200)) {
        throw MealLogCommentApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen yeniden giriş yapın.',
            403 => 'Bu öğünün yorumlarına erişim yetkiniz doğrulanamadı.',
            404 =>
              'Öğün veya ilgili yorum bulunamadı; kayıt silinmiş olabilir.',
            422 =>
              'Yanıt 1–2000 karakter olmalı ve aynı öğünün kök yorumuna bağlanmalıdır.',
            _ =>
              mutation
                  ? 'Gönderim sonucu doğrulanamadı. Yorumları yenileyip kontrol edin.'
                  : 'Yorumlar alınamadı. Yeniden deneyin.',
          },
          statusCode: response.statusCode,
          uncertain:
              mutation &&
              ![400, 401, 403, 404, 422, 429].contains(response.statusCode),
        );
      }
      return response.body;
    } on LoginApiException catch (error) {
      throw MealLogCommentApiException(
        error.message,
        statusCode: error.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on IOException {
      throw MealLogCommentApiException(
        'Güvenli bağlantı kurulamadı veya kesildi. Yorumları yenileyip kontrol edin.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw MealLogCommentApiException(
        'İstek zaman aşımına uğradı. Yorumları yenileyip kontrol edin.',
        uncertain: mutation,
      );
    } on FormatException {
      throw MealLogCommentApiException.invalid(uncertain: mutation);
    }
  }

  static bool _uuid(Object? value) =>
      value is String &&
      value != '00000000-0000-0000-0000-000000000000' &&
      RegExp(
        r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
      ).hasMatch(value);
  static void _checkId(String id) {
    if (!_uuid(id)) {
      throw const MealLogCommentApiException.invalid();
    }
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const MealLogCommentApiException.invalid();
    }
    return value;
  }

  static MealLogComment _comment(Object? value, String mealLogId) {
    final row = _object(value, const [
      'id',
      'mealLogId',
      'authorUserId',
      'text',
      'createdAt',
      'parentCommentId',
    ]);
    final text = row['text'],
        time = row['createdAt'],
        parent = row['parentCommentId'];
    if (!_uuid(row['id']) ||
        row['mealLogId'] != mealLogId ||
        !_uuid(row['authorUserId']) ||
        text is! String ||
        !validText(text) ||
        text != text.trim() ||
        (parent != null && (!_uuid(parent) || parent == row['id'])) ||
        time is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$',
        ).hasMatch(time) ||
        DateTime.tryParse(time) == null) {
      throw const MealLogCommentApiException.invalid();
    }
    return MealLogComment(
      id: row['id'] as String,
      mealLogId: mealLogId,
      authorUserId: row['authorUserId'] as String,
      text: text,
      createdAt: DateTime.parse(time).toUtc(),
      parentCommentId: parent as String?,
    );
  }
}

class MealLogCommentApiException implements Exception {
  const MealLogCommentApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const MealLogCommentApiException.invalid({this.uncertain = false})
    : message = 'Yorum yanıtı doğrulanamadı. Yorumları yenileyip kontrol edin.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
  @override
  String toString() => 'MealLogCommentApiException';
}
