import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'client_task_api.dart';
import 'client_task_detail_page.dart';

class ClientTaskPage extends StatefulWidget {
  const ClientTaskPage({this.api, super.key});
  final ClientTaskApi? api;
  @override
  State<ClientTaskPage> createState() => _ClientTaskPageState();
}

class _ClientTaskPageState extends State<ClientTaskPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  ClientTaskApi? _api;
  String? _owner, _error;
  bool _changedOwner = false, _started = false, _loading = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  int _revision = 0, _page = 1, _total = 0;
  List<ClientTask> _rows = [];
  bool get _authorized =>
      !_changedOwner &&
      _foreground &&
      _owner != null &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  bool _current(int revision) =>
      mounted && _authorized && _revision == revision;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api?.session;
    if (_session != null &&
        (!identical(_session, session) || session?.user?.id != _owner)) {
      ++_revision;
      _changedOwner = true;
      _rows = [];
      _total = 0;
      _error = null;
    }
    _session = session;
    _owner ??= session?.user?.id;
    _api = widget.api ?? (session == null ? null : ClientTaskApi(session));
    if (!_started && _authorized) {
      _started = true;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        ++_revision;
        _rows = [];
        _total = 0;
        _loading = false;
        _error = null;
      }
    });
    if (_authorized) _load();
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    if (!_authorized || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _total = 0;
      _page = page ?? _page;
    });
    try {
      final result = await _api!.list(page: _page);
      if (!_current(revision)) return;
      if (result.items.isEmpty && result.totalCount > 0 && _page > 1) {
        setState(() => _loading = false);
        await _load(page: 1);
        return;
      }
      setState(() {
        _rows = result.items;
        _total = result.totalCount;
      });
    } on ClientTaskApiException catch (e) {
      if (_current(revision)) setState(() => _error = e.message);
    } catch (_) {
      if (_current(revision)) {
        setState(() => _error = 'Görevler yüklenemedi. Yeniden deneyin.');
      }
    } finally {
      if (_current(revision)) setState(() => _loading = false);
    }
  }

  Future<void> _open(ClientTask task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ClientTaskDetailPage(api: _api!, taskId: task.id),
      ),
    );
    if (_authorized) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Görevlerim'),
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _authorized && !_loading ? () => _load() : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !_authorized
        ? const Center(
            child: Text('Bu ekranı mevcut hesabınızla yeniden açın.'),
          )
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () => _load(),
                    child: const Text('Yeniden dene'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Bekleyen, devam eden ve geçmiş görevleriniz'),
                if (_total == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('Henüz atanmış göreviniz yok.'),
                  ),
                for (final task in _rows)
                  Card(
                    child: ListTile(
                      key: ValueKey(task.id),
                      isThreeLine: true,
                      title: Text(task.description),
                      subtitle: Text(
                        '${task.status.label}\nSon tarih: '
                        '${task.dueAt == null ? 'Belirlenmedi' : clientTaskDate(task.dueAt!)}'
                        '${task.isOpen && task.dueAt != null && task.dueAt!.isBefore(DateTime.now()) ? '\nSon tarihi geçti' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(task),
                    ),
                  ),
                if (_total > 0) ...[
                  Text('$_total görev · Sayfa $_page'),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _page > 1
                            ? () => _load(page: _page - 1)
                            : null,
                        child: const Text('Önceki'),
                      ),
                      TextButton(
                        onPressed: _page * ClientTaskApi.pageSize < _total
                            ? () => _load(page: _page + 1)
                            : null,
                        child: const Text('Sonraki'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
  );
}
