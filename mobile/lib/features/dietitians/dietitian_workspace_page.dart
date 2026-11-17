import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import 'dietitian_api.dart';

class DietitianWorkspacePage extends StatefulWidget {
  const DietitianWorkspacePage({
    required this.api,
    required this.dietitianId,
    super.key,
  });

  final DietitianApi api;
  final String dietitianId;

  @override
  State<DietitianWorkspacePage> createState() => _DietitianWorkspacePageState();
}

class _DietitianWorkspacePageState extends State<DietitianWorkspacePage> {
  static const _filters = {
    'clients': 'Aktif danışanlar',
    'pending': 'Bekleyen talepler',
    'active': 'Aktif bağlantılar',
    'rejected': 'Reddedilenler',
    'ended': 'Sonlananlar',
  };
  List<ClientListItem> _clients = [];
  List<RelationshipResponse> _connections = [];
  ({String invitationCode, DateTime expiresAt})? _invitation;
  String _filter = 'clients';
  String? _error, _notice;
  int _page = 1, _total = 0;
  bool _busy = false;
  late final String? _viewerId;
  bool get _available =>
      !_busy && _viewerId != null && widget.api.session.user?.id == _viewerId;

  @override
  void initState() {
    super.initState();
    _viewerId = widget.api.session.user?.id;
    _load();
  }

  Future<void> _load({int page = 1, String? filter}) async {
    if (!_available) return;
    setState(() {
      _busy = true;
      _error = null;
      _page = page;
      _filter = filter ?? _filter;
      _clients = [];
      _connections = [];
      _total = 0;
    });
    try {
      if (_filter == 'clients') {
        final result = await widget.api.clients(page);
        if (mounted) {
          setState(() {
            _clients = result.items;
            _total = result.totalCount;
          });
        }
      } else {
        final result = await widget.api.expertRelationships(
          status: _filter,
          page: page,
          dietitianId: widget.dietitianId,
        );
        if (mounted) {
          setState(() {
            _connections = result.items;
            _total = result.totalCount;
          });
        }
      }
    } on DietitianApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleError(DietitianApiException error) {
    if (!mounted) return;
    setState(() {
      _error = error.message;
      if (error.statusCode == 401 || error.statusCode == 403) {
        _clients = [];
        _connections = [];
        _total = 0;
        _invitation = null;
      }
    });
  }

  Future<void> _createInvitation() async {
    if (!_available) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _invitation = null;
    });
    try {
      final result = await widget.api.invitation();
      if (mounted) setState(() => _invitation = result);
    } on DietitianApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(
    RelationshipResponse row,
    String action,
    String label,
  ) async {
    if (!_available) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.changeRelationship(row, action, asDietitian: true);
      if (!mounted) return;
      setState(() {
        _notice = label;
        _busy = false;
      });
      await _load();
    } on DietitianApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_viewerId == null ||
        AuthSessionScope.maybeOf(context)?.user?.id != _viewerId) {
      return Scaffold(
        appBar: AppBar(title: const Text('Danışanlar ve bağlantılar')),
        body: const Center(
          child: Text('Devam etmek için yeniden giriş yapın.'),
        ),
      );
    }
    final invitation = _invitation;
    return Scaffold(
      appBar: AppBar(title: const Text('Danışanlar ve bağlantılar')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spacingLarge),
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _createInvitation,
            child: const Text('Davet kodu oluştur'),
          ),
          if (invitation != null) ...[
            SelectableText(invitation.invitationCode),
            Text(
              'Geçerlilik: ${MaterialLocalizations.of(context).formatShortDate(invitation.expiresAt.toLocal())} '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(invitation.expiresAt.toLocal()))}',
            ),
          ],
          const SizedBox(height: 16),
          DropdownButton<String>(
            value: _filter,
            isExpanded: true,
            items: _filters.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (filter) {
                    setState(() => _notice = null);
                    _load(filter: filter);
                  },
          ),
          if (_busy)
            const LinearProgressIndicator(semanticsLabel: 'İşlem sürüyor'),
          if (_error != null) Text(_error!),
          if (_notice != null) Text(_notice!),
          if (!_busy && _error == null && _total == 0)
            const Text('Bu bölümde kayıt bulunmuyor.'),
          for (final client in _clients)
            ListTile(key: ValueKey(client.id), title: Text(client.displayName)),
          for (final row in _connections)
            Card(
              key: ValueKey(row.id),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spacingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Danışan kimliği: ${row.clientId}'),
                    if (row.status == 'pending')
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _change(
                                    row,
                                    'accept',
                                    'Bağlantı kabul edildi.',
                                  ),
                            child: const Text('Kabul et'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _change(
                                    row,
                                    'reject',
                                    'Talep reddedildi.',
                                  ),
                            child: const Text('Reddet'),
                          ),
                        ],
                      ),
                    if (row.status == 'active')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Bağlantı sonlandırılsın mı?',
                                    ),
                                    content: const Text(
                                      'Danışan verilerine erişiminiz kapanır ve bu danışana atadığınız aktif program arşivlenir.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Vazgeç'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Sonlandır'),
                                      ),
                                    ],
                                  ),
                                );
                                if (mounted && confirmed == true) {
                                  await _change(
                                    row,
                                    'end',
                                    'Bağlantı sonlandırıldı.',
                                  );
                                }
                              },
                        child: const Text('Bağlantıyı sonlandır'),
                      ),
                  ],
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Önceki sayfa',
                onPressed: _busy || _page == 1
                    ? null
                    : () => _load(page: _page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Sayfa $_page'),
              IconButton(
                tooltip: 'Sonraki sayfa',
                onPressed: _busy || _page * DietitianApi.pageSize >= _total
                    ? null
                    : () => _load(page: _page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          TextButton(
            onPressed: _busy ? null : () => _load(),
            child: const Text('Listeyi yenile'),
          ),
        ],
      ),
    );
  }
}
