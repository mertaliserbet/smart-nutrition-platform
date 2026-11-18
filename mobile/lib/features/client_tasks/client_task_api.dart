import 'dart:async';
import 'dart:io';

import '../auth/auth_session.dart';
import '../auth/login_api.dart';

enum ClientTaskStatus {
  pending('pending', 'Bekliyor'),
  inProgress('in_progress', 'Devam ediyor'),
  completed('completed', 'Tamamlandı'),
  cancelled('cancelled', 'İptal edildi');

  const ClientTaskStatus(this.value, this.label);
  final String value, label;
}

class ClientTask {
  const ClientTask({
    required this.id,
    required this.clientId,
    required this.dietitianId,
    required this.relationshipId,
    required this.description,
    required this.status,
    required this.dueAt,
    required this.isReminderEnabled,
    required this.createdAt,
    required this.updatedAt,
    required this.versionNumber,
  });
  final String id, clientId, dietitianId, relationshipId, description;
  final ClientTaskStatus status;
  final DateTime? dueAt;
  final bool isReminderEnabled;
  final DateTime createdAt, updatedAt;
  final int versionNumber;
  bool get isOpen =>
      status == ClientTaskStatus.pending ||
      status == ClientTaskStatus.inProgress;
  List<ClientTaskStatus> get allowedStatuses => switch (status) {
    ClientTaskStatus.pending => [
      ClientTaskStatus.inProgress,
      ClientTaskStatus.completed,
    ],
    ClientTaskStatus.inProgress => [ClientTaskStatus.completed],
    _ => [],
  };
}

class ClientTaskVersion {
  const ClientTaskVersion({
    required this.id,
    required this.clientTaskId,
    required this.versionNumber,
    required this.createdAt,
    required this.snapshot,
  });
  final String id, clientTaskId;
  final int versionNumber;
  final DateTime createdAt;
  final ClientTask snapshot;
}

typedef ClientTaskPageResult<T> = ({List<T> items, int totalCount});

class ClientTaskApi {
  ClientTaskApi(this.session);
  final AuthSession session;
  static const pageSize = 10;
  static const _root = '/api/v1/client-tasks';

  Future<ClientTaskPageResult<ClientTask>> list({int page = 1}) async {
    _checkPage(page);
    return _page(
      await _send('$_root?page=$page&pageSize=$pageSize'),
      page,
      _task,
    );
  }

  Future<ClientTask> get(String id) async {
    _checkId(id);
    final task = _task(await _send('$_root/$id'));
    if (task.id != id) throw const ClientTaskApiException.invalid();
    return task;
  }

  Future<ClientTaskPageResult<ClientTaskVersion>> versions(
    String id, {
    int page = 1,
  }) async {
    _checkId(id);
    _checkPage(page);
    final result = _page(
      await _send('$_root/$id/versions?page=$page&pageSize=$pageSize'),
      page,
      (value) {
        final row = _object(value, [
          'id',
          'clientTaskId',
          'versionNumber',
          'createdAt',
          'snapshot',
        ]);
        final snapshot = _task(row['snapshot']);
        if (row['clientTaskId'] != id ||
            snapshot.id != id ||
            row['versionNumber'] != snapshot.versionNumber) {
          throw const ClientTaskApiException.invalid();
        }
        return ClientTaskVersion(
          id: _id(row['id']),
          clientTaskId: id,
          versionNumber: snapshot.versionNumber,
          createdAt: _instant(row['createdAt']),
          snapshot: snapshot,
        );
      },
    );
    for (var i = 1; i < result.items.length; i++) {
      if (result.items[i - 1].versionNumber <= result.items[i].versionNumber) {
        throw const ClientTaskApiException.invalid();
      }
    }
    return result;
  }

  Future<ClientTask> patch(
    ClientTask task, {
    ClientTaskStatus? status,
    bool? isReminderEnabled,
  }) async {
    _checkId(task.id);
    if (!task.isOpen ||
        (status == null && isReminderEnabled == null) ||
        (status != null && !task.allowedStatuses.contains(status)) ||
        (isReminderEnabled == true && task.dueAt == null)) {
      throw const ClientTaskApiException(
        'Bu görev değişikliği desteklenmiyor.',
        statusCode: 422,
      );
    }
    final body = await _send(
      '$_root/${task.id}',
      payload: {
        'expectedVersionNumber': task.versionNumber,
        if (status != null) 'status': status.value,
        'isReminderEnabled': ?isReminderEnabled,
      },
    );
    try {
      final updated = _task(body);
      if (updated.id != task.id ||
          updated.clientId != task.clientId ||
          updated.relationshipId != task.relationshipId ||
          updated.versionNumber < task.versionNumber ||
          (status != null && updated.status != status) ||
          (isReminderEnabled != null &&
              updated.isReminderEnabled != isReminderEnabled)) {
        throw const ClientTaskApiException.invalid();
      }
      return updated;
    } on ClientTaskApiException {
      throw const ClientTaskApiException.invalid(uncertain: true);
    }
  }

  Future<Object?> _send(String path, {Map<String, Object?>? payload}) async {
    final owner = session.user?.id, mutation = payload != null;
    try {
      final response = await session.authorizedRequest(
        path: path,
        method: mutation ? 'PATCH' : 'GET',
        payload: payload,
        profileContext: 'client',
        maxResponseBytes: 262144,
      );
      if (owner == null ||
          session.user?.id != owner ||
          !session.isAuthenticated) {
        throw ClientTaskApiException(
          'Oturum değişti. Ekranı yeniden açın.',
          statusCode: 401,
          uncertain: mutation,
        );
      }
      if (response.statusCode != 200) {
        throw ClientTaskApiException(
          switch (response.statusCode) {
            401 => 'Oturumunuz doğrulanamadı. Lütfen tekrar giriş yapın.',
            403 => 'Bu göreve erişim izniniz yok.',
            404 => 'Görev bulunamadı veya artık erişilemiyor.',
            409 =>
              'Görev değişmiş. Güncel kaydı kontrol edip işleminizi yeniden seçin.',
            400 || 422 =>
              'Görev değişikliği kabul edilmedi. Güncel kaydı kontrol edin.',
            429 => 'Çok fazla istek yapıldı. Bir süre sonra yeniden deneyin.',
            _ => 'Görev servisine erişilemedi. Yeniden deneyin.',
          },
          statusCode: response.statusCode,
          uncertain: mutation && response.statusCode >= 500,
        );
      }
      return response.body;
    } on LoginApiException catch (e) {
      throw ClientTaskApiException(
        e.message,
        statusCode: e.unauthorized ? 401 : null,
        uncertain: mutation,
      );
    } on IOException {
      throw ClientTaskApiException(
        'Sunucuyla bağlantı kurulamadı veya kesildi.',
        uncertain: mutation,
      );
    } on TimeoutException {
      throw ClientTaskApiException(
        'Görev isteği zaman aşımına uğradı.',
        uncertain: mutation,
      );
    } on FormatException {
      throw ClientTaskApiException.invalid(uncertain: mutation);
    }
  }

  static ClientTaskPageResult<T> _page<T>(
    Object? value,
    int page,
    T Function(Object?) parse,
  ) {
    final json = _object(value, ['items', 'totalCount']);
    final items = json['items'], count = json['totalCount'];
    if (items is! List ||
        items.length > pageSize ||
        count is! int ||
        count < 0 ||
        (items.isNotEmpty && count < (page - 1) * pageSize + items.length)) {
      throw const ClientTaskApiException.invalid();
    }
    return (items: List<T>.unmodifiable(items.map(parse)), totalCount: count);
  }

  static ClientTask _task(Object? value) {
    final row = _object(value, [
      'id',
      'clientId',
      'dietitianId',
      'relationshipId',
      'description',
      'status',
      'dueAt',
      'isReminderEnabled',
      'createdAt',
      'updatedAt',
      'versionNumber',
    ]);
    final description = row['description'],
        reminder = row['isReminderEnabled'],
        version = row['versionNumber'];
    final states = ClientTaskStatus.values.where(
      (s) => s.value == row['status'],
    );
    if (description is! String ||
        description.trim().isEmpty ||
        description.runes.length > 2000 ||
        description.contains('\u0000') ||
        reminder is! bool ||
        version is! int ||
        version < 1 ||
        states.length != 1) {
      throw const ClientTaskApiException.invalid();
    }
    final created = _instant(row['createdAt']),
        updated = _instant(row['updatedAt']);
    final due = row['dueAt'] == null ? null : _instant(row['dueAt']);
    if (updated.isBefore(created) || (reminder && due == null)) {
      throw const ClientTaskApiException.invalid();
    }
    return ClientTask(
      id: _id(row['id']),
      clientId: _id(row['clientId']),
      dietitianId: _id(row['dietitianId']),
      relationshipId: _id(row['relationshipId']),
      description: description,
      status: states.single,
      dueAt: due,
      isReminderEnabled: reminder,
      createdAt: created,
      updatedAt: updated,
      versionNumber: version,
    );
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        keys.any((key) => !value.containsKey(key))) {
      throw const ClientTaskApiException.invalid();
    }
    return value;
  }

  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
  );
  static void _checkId(String id) {
    _id(id);
  }

  static String _id(Object? value) {
    if (value is! String ||
        !_uuid.hasMatch(value) ||
        value == '00000000-0000-0000-0000-000000000000') {
      throw const ClientTaskApiException.invalid();
    }
    return value;
  }

  static DateTime _instant(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const ClientTaskApiException.invalid();
    }
    final time = DateTime.tryParse(value);
    if (time == null) throw const ClientTaskApiException.invalid();
    return time.toUtc();
  }

  static void _checkPage(int page) {
    if (page < 1 || (page - 1) * pageSize > 2147483647) {
      throw const ClientTaskApiException.invalid();
    }
  }
}

class ClientTaskApiException implements Exception {
  const ClientTaskApiException(
    this.message, {
    this.statusCode,
    this.uncertain = false,
  });
  const ClientTaskApiException.invalid({this.uncertain = false})
    : message = 'Görev servisinden geçerli yanıt alınamadı.',
      statusCode = null;
  final String message;
  final int? statusCode;
  final bool uncertain;
}

String clientTaskDate(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
