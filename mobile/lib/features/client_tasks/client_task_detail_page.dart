import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'client_task_api.dart';

class ClientTaskDetailPage extends StatefulWidget {
  const ClientTaskDetailPage({
    required this.api,
    required this.taskId,
    super.key,
  });
  final ClientTaskApi api;
  final String taskId;
  @override
  State<ClientTaskDetailPage> createState() => _ClientTaskDetailPageState();
}

class _ClientTaskDetailPageState extends State<ClientTaskDetailPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  String? _owner, _error, _notice;
  ClientTask? _task;
  List<ClientTaskVersion> _versions = [];
  int _revision = 0, _historyPage = 1, _total = 0;
  bool _changedOwner = false,
      _started = false,
      _loading = false,
      _saving = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _authorized =>
      !_changedOwner &&
      _foreground &&
      _owner != null &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  bool _current(int revision) =>
      mounted && _authorized && revision == _revision;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api.session;
    if (_session != null &&
        (!identical(session, _session) || session.user?.id != _owner)) {
      ++_revision;
      _changedOwner = true;
      _task = null;
      _versions = [];
      _error = null;
      _notice = null;
    }
    _session = session;
    _owner ??= session.user?.id;
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
        _task = null;
        _versions = [];
        _loading = false;
        _error = null;
        _notice = null;
      }
    });
    if (_authorized && !_saving) _load();
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({String? notice, int page = 1}) async {
    if (!_authorized || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _saving = false;
      _error = null;
      _notice = notice;
      _task = null;
      _versions = [];
      _total = 0;
      _historyPage = page;
    });
    try {
      final task = await widget.api.get(widget.taskId);
      if (!_current(revision)) return;
      final history = await widget.api.versions(widget.taskId, page: page);
      if (!_current(revision)) return;
      setState(() {
        _task = task;
        _versions = history.items;
        _total = history.totalCount;
      });
    } on ClientTaskApiException catch (e) {
      if (_current(revision)) setState(() => _error = e.message);
    } catch (_) {
      if (_current(revision)) {
        setState(() => _error = 'Görev yüklenemedi. Yeniden deneyin.');
      }
    } finally {
      if (_current(revision)) setState(() => _loading = false);
    }
  }

  Future<void> _save({ClientTaskStatus? status, bool? reminder}) async {
    if (!_authorized || _saving || _loading || _task == null) return;
    final revision = ++_revision;
    final task = _task!;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.patch(task, status: status, isReminderEnabled: reminder);
      if (_current(revision)) await _load(notice: 'Görev güncellendi.');
    } on ClientTaskApiException catch (e) {
      if (!_current(revision)) return;
      if (e.statusCode == 409) {
        await _load(notice: e.message);
      } else {
        setState(() {
          _task = null;
          _versions = [];
          _error = e.uncertain
              ? 'İşlemin sonucu doğrulanamadı. Tekrar işlem yapmadan önce güncel kaydı yenileyin.'
              : e.message;
        });
      }
    } catch (_) {
      if (_current(revision)) {
        setState(() {
          _task = null;
          _versions = [];
          _error = 'İşlemin sonucu doğrulanamadı. Önce güncel kaydı yenileyin.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Görev detayı'),
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _authorized && !_saving && !_loading
              ? () => _load()
              : null,
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
                    onPressed: _saving ? null : () => _load(),
                    child: const Text('Güncel kaydı yenile'),
                  ),
                ],
              ),
            ),
          )
        : _task == null
        ? Center(
            child: _saving
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: () => _load(),
                    child: const Text('Güncel kaydı yenile'),
                  ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_notice != null) Text(_notice!),
              Text(
                _task!.description,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Durum: ${_task!.status.label}'),
              Text(
                'Son tarih: ${_task!.dueAt == null ? 'Belirlenmedi' : clientTaskDate(_task!.dueAt!)}',
              ),
              Text('Atanma: ${clientTaskDate(_task!.createdAt)}'),
              Text('Son güncelleme: ${clientTaskDate(_task!.updatedAt)}'),
              const Text('Tarihler cihazınızın yerel saatinde gösterilir.'),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              for (final status in _task!.allowedStatuses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(status: status),
                    child: Text(
                      status == ClientTaskStatus.completed
                          ? 'Görevi tamamla'
                          : 'Göreve başla',
                    ),
                  ),
                ),
              if (_task!.isOpen)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hatırlatma tercihi'),
                  subtitle: Text(
                    _task!.dueAt == null
                        ? 'Son tarih belirlenmeden açılamaz.'
                        : 'Yalnız tercih kaydedilir; bildirim gönderimi henüz desteklenmiyor.',
                  ),
                  value: _task!.isReminderEnabled,
                  onChanged: _saving || _task!.dueAt == null
                      ? null
                      : (value) => _save(reminder: value),
                ),
              const SizedBox(height: 20),
              Text(
                'Görev geçmişi',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_versions.isEmpty) const Text('Geçmiş kaydı bulunamadı.'),
              for (final version in _versions)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sürüm ${version.versionNumber} · ${clientTaskDate(version.createdAt)}',
                        ),
                        Text(version.snapshot.description),
                        Text(version.snapshot.status.label),
                        Text(
                          'Son tarih: ${version.snapshot.dueAt == null ? 'Belirlenmedi' : clientTaskDate(version.snapshot.dueAt!)}',
                        ),
                        Text(
                          'Hatırlatma tercihi: ${version.snapshot.isReminderEnabled ? 'Açık' : 'Kapalı'}',
                        ),
                      ],
                    ),
                  ),
                ),
              if (_total > 0)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Geçmiş sayfası $_historyPage'),
                    TextButton(
                      onPressed: !_saving && _historyPage > 1
                          ? () => _load(page: _historyPage - 1)
                          : null,
                      child: const Text('Önceki geçmiş'),
                    ),
                    TextButton(
                      onPressed:
                          !_saving &&
                              _historyPage * ClientTaskApi.pageSize < _total
                          ? () => _load(page: _historyPage + 1)
                          : null,
                      child: const Text('Sonraki geçmiş'),
                    ),
                  ],
                ),
            ],
          ),
  );
}
