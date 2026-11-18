import 'package:smart_nutrition_mobile/features/client_tasks/client_task_api.dart';

const taskId = '11111111-1111-4111-8111-111111111111';
const taskClientId = '22222222-2222-4222-8222-222222222222';
const taskExpertId = '33333333-3333-4333-8333-333333333333';
const taskRelationId = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> taskJson({
  String status = 'pending',
  int version = 1,
  String description = 'Sentetik danışan görevi',
}) => {
  'id': taskId,
  'clientId': taskClientId,
  'dietitianId': taskExpertId,
  'relationshipId': taskRelationId,
  'description': description,
  'status': status,
  'dueAt': '2026-12-20T12:00:00Z',
  'isReminderEnabled': false,
  'createdAt': '2026-11-19T10:00:00Z',
  'updatedAt': '2026-11-19T10:00:00Z',
  'versionNumber': version,
};

ClientTask taskSample({
  ClientTaskStatus status = ClientTaskStatus.pending,
  int version = 1,
  String description = 'Sentetik danışan görevi',
  bool reminder = false,
}) => ClientTask(
  id: taskId,
  clientId: taskClientId,
  dietitianId: taskExpertId,
  relationshipId: taskRelationId,
  description: description,
  status: status,
  dueAt: DateTime.utc(2026, 12, 20, 12),
  isReminderEnabled: reminder,
  createdAt: DateTime.utc(2026, 11, 19, 10),
  updatedAt: DateTime.utc(2026, 11, 19, 10),
  versionNumber: version,
);

class TaskTestApi extends ClientTaskApi {
  TaskTestApi(super.session);
  List<ClientTask> rows = [taskSample()];
  ClientTask task = taskSample();
  int total = 1, historyTotal = 1, writes = 0, gets = 0;
  ClientTaskApiException? failure, writeFailure;
  Future<ClientTaskPageResult<ClientTask>>? pendingList;
  Future<ClientTask>? pendingWrite;
  final pages = <int>[], historyPages = <int>[];
  final statuses = <ClientTaskStatus?>[];
  final reminders = <bool?>[];
  @override
  Future<ClientTaskPageResult<ClientTask>> list({int page = 1}) async {
    pages.add(page);
    if (failure != null) throw failure!;
    return pendingList ?? (items: rows, totalCount: total);
  }

  @override
  Future<ClientTask> get(String id) async {
    gets++;
    if (failure != null) throw failure!;
    return task;
  }

  @override
  Future<ClientTaskPageResult<ClientTaskVersion>> versions(
    String id, {
    int page = 1,
  }) async {
    historyPages.add(page);
    return (
      items: [
        ClientTaskVersion(
          id: taskExpertId,
          clientTaskId: taskId,
          versionNumber: task.versionNumber,
          createdAt: task.updatedAt,
          snapshot: task,
        ),
      ],
      totalCount: historyTotal,
    );
  }

  @override
  Future<ClientTask> patch(
    ClientTask row, {
    ClientTaskStatus? status,
    bool? isReminderEnabled,
  }) async {
    writes++;
    statuses.add(status);
    reminders.add(isReminderEnabled);
    if (writeFailure != null) throw writeFailure!;
    task =
        await (pendingWrite ??
            Future.value(
              taskSample(
                status: status ?? row.status,
                version: row.versionNumber + 1,
                reminder: isReminderEnabled ?? row.isReminderEnabled,
              ),
            ));
    rows = [task];
    return task;
  }
}
