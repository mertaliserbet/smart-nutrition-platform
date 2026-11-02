import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import '../auth/login_page.dart';
import 'dietitian_api.dart';

class DietitianFinderPage extends StatefulWidget {
  const DietitianFinderPage({this.api, super.key});
  final DietitianApi? api;
  @override
  State<DietitianFinderPage> createState() => _DietitianFinderPageState();
}

class _DietitianFinderPageState extends State<DietitianFinderPage> {
  final _query = TextEditingController();
  final _code = TextEditingController();
  final _names = <String, String>{};
  final _knownPending = <String>{};
  DietitianApi? _api;
  List<DietitianListItem> _experts = [];
  List<RelationshipResponse> _pending = [];
  RelationshipResponse? _active;
  int _page = 1, _total = 0, _pendingPage = 1, _pendingTotal = 0;
  int _searchRevision = 0, _connectionRevision = 0;
  String _submittedQuery = '';
  String? _searchError, _connectionError, _message, _codeError;
  bool _searching = false,
      _checking = false,
      _sending = false,
      _connectionsReady = false;
  DateTime? _retryAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (_api == null && session?.isAuthenticated == true) {
      _api = widget.api ?? DietitianApi(session!);
      _search();
      _loadConnections();
    }
  }

  @override
  void dispose() {
    ++_searchRevision;
    ++_connectionRevision;
    _query.dispose();
    _code.dispose();
    super.dispose();
  }

  String _error(Object error) => error is DietitianApiException
      ? error.message
      : 'İşlem tamamlanamadı. Lütfen tekrar deneyin.';
  bool get _canSend =>
      _connectionsReady &&
      !_checking &&
      !_sending &&
      _active == null &&
      (_retryAt == null || !DateTime.now().isBefore(_retryAt!));

  Future<void> _search({int page = 1, bool submitted = false}) async {
    if (_api == null || _sending) return;
    final revision = ++_searchRevision;
    if (submitted) _submittedQuery = _query.text.trim();
    setState(() {
      _searching = true;
      _searchError = null;
      _experts = [];
    });
    try {
      final result = await _api!.search(page: page, query: _submittedQuery);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _experts = result.items;
        _total = result.totalCount;
        _page = page;
        for (final expert in _experts) {
          _names[expert.id] = expert.displayName;
        }
      });
    } catch (error) {
      if (mounted && revision == _searchRevision) {
        setState(() => _searchError = _error(error));
      }
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadConnections({int page = 1}) async {
    if (_api == null) return;
    final revision = ++_connectionRevision;
    setState(() {
      _checking = true;
      _connectionsReady = false;
      _connectionError = null;
      _pending = [];
      _active = null;
    });
    try {
      final results = await Future.wait([
        _api!.relationships(status: 'active'),
        _api!.relationships(status: 'pending', page: page),
      ]);
      if (!mounted || revision != _connectionRevision) return;
      final all = [...results[0].items, ...results[1].items];
      if (all.map((row) => row.clientId).toSet().length > 1) {
        throw const DietitianApiException.invalidResponse();
      }
      setState(() {
        _active = results[0].items.firstOrNull;
        _pending = results[1].items;
        _pendingTotal = results[1].totalCount;
        _pendingPage = page;
        if (page == 1) _knownPending.clear();
        _knownPending.addAll(_pending.map((row) => row.dietitianId));
        _connectionsReady = true;
      });
    } catch (error) {
      if (mounted && revision == _connectionRevision) {
        setState(() => _connectionError = _error(error));
      }
    } finally {
      if (mounted && revision == _connectionRevision) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _send({String? id, String? code}) async {
    if (!_canSend || (id != null && _knownPending.contains(id))) return;
    setState(() {
      _sending = true;
      _message = null;
      _codeError = null;
    });
    try {
      final result = await _api!.request(dietitianId: id, invitationCode: code);
      if (!mounted) return;
      setState(() {
        _knownPending.add(result.dietitianId);
        _code.clear();
        _message =
            'Bağlantı isteğiniz gönderildi. Diyetisyen onayı bekleniyor.';
      });
      await _loadConnections();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionsReady = false;
        _message =
            '${_error(error)} Tekrar göndermeden “Bağlantıları yenile” ile durumu kontrol edin.';
        if (error is DietitianApiException && error.statusCode == 429) {
          _retryAt = DateTime.now().add(
            error.retryAfter ?? const Duration(minutes: 1),
          );
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _select(DietitianListItem expert) async {
    final pending = _knownPending.contains(expert.id);
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingLarge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  expert.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Admin onaylı diyetisyen'),
                const SizedBox(height: 16),
                const Text(
                  'İsteğiniz diyetisyen kabul ettiğinde aktif olur. Veri paylaşımı ayrıca izninize bağlıdır.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _canSend && !pending
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Text(
                    pending
                        ? 'Onay bekleyen isteğiniz var'
                        : _active != null
                        ? 'Aktif diyetisyeniniz var'
                        : 'Bağlantı İsteği Gönder',
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted && send == true) await _send(id: expert.id);
  }

  void _submitCode() {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-7]{16}$').hasMatch(code)) {
      setState(
        () => _codeError = '16 karakterli davet kodunu girin (A–Z, 2–7).',
      );
      return;
    }
    _send(code: code);
  }

  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _notice(String message) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(message),
    ),
  );
  Widget _pager({
    required int page,
    required int total,
    required bool disabled,
    required void Function(int) load,
    required String label,
  }) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        onPressed: disabled || page <= 1 ? null : () => load(page - 1),
        child: Text('$label önceki'),
      ),
      Text('Sayfa $page'),
      TextButton(
        onPressed: disabled || page * DietitianApi.pageSize >= total
            ? null
            : () => load(page + 1),
        child: Text('$label sonraki'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (AuthSessionScope.maybeOf(context)?.isAuthenticated != true) {
      return const LoginPage();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diyetisyen Bul'),
        actions: [
          IconButton(
            tooltip: 'Bağlantıları yenile',
            onPressed: _sending || _checking ? null : () => _loadConnections(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.spacingMedium),
              children: [
                Text(
                  'Size uygun uzmanla bağlantı kurun',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text(
                  'Yalnızca Admin onaylı diyetisyenler listelenir. Bağlantı isteği otomatik veri paylaşımı başlatmaz.',
                ),
                if (_sending)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Bağlantı isteği gönderiliyor',
                  ),
                if (_message != null) _notice(_message!),
                _card([
                  Text(
                    'Bağlantılarım',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_checking)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Bağlantılar kontrol ediliyor',
                    ),
                  if (_connectionError != null) _notice(_connectionError!),
                  if (!_connectionsReady && !_checking)
                    const Text('İstek göndermeden bağlantılarınızı yenileyin.'),
                  if (_connectionsReady) ...[
                    Text(
                      _active == null
                          ? 'Aktif diyetisyeniniz yok.'
                          : 'Aktif diyetisyeniniz',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_active != null)
                      Text(
                        _names[_active!.dietitianId] ??
                            'Bağlantınız aktif. Yeni bağlantı isteği gönderemezsiniz.',
                      ),
                    const SizedBox(height: 12),
                    Text('Bekleyen istekler ($_pendingTotal)'),
                    if (_pending.isEmpty)
                      const Text('Bekleyen bağlantı isteğiniz yok.'),
                    for (final row in _pending)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${_names[row.dietitianId] ?? 'Diyetisyen bağlantısı'} · Onay bekleniyor',
                        ),
                      ),
                    if (_pendingTotal > DietitianApi.pageSize ||
                        _pendingPage > 1)
                      _pager(
                        page: _pendingPage,
                        total: _pendingTotal,
                        disabled: _sending || _checking,
                        label: 'İstekler',
                        load: (page) => _loadConnections(page: page),
                      ),
                  ],
                  TextButton.icon(
                    onPressed: _sending || _checking
                        ? null
                        : () => _loadConnections(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Bağlantıları yenile'),
                  ),
                ]),
                _card([
                  Text(
                    'Davet koduyla bağlan',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextField(
                    controller: _code,
                    enabled: !_sending,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Davet kodu',
                      hintText: '16 karakter',
                      errorText: _codeError,
                    ),
                    onSubmitted: (_) {
                      if (_canSend) _submitCode();
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _canSend ? _submitCode : null,
                    child: const Text('Davet Koduyla İstek Gönder'),
                  ),
                  if (_retryAt != null && DateTime.now().isBefore(_retryAt!))
                    const Text(
                      'Gönderim sınırına ulaşıldı. Bir süre sonra bağlantıları yenileyin.',
                    ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _query,
                  enabled: !_sending,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Diyetisyen adı',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => _search(submitted: true),
                ),
                FilledButton(
                  onPressed: _sending ? null : () => _search(submitted: true),
                  child: const Text('Ara'),
                ),
                if (_searching)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Diyetisyenler aranıyor',
                  ),
                if (_searchError != null) ...[
                  _notice(_searchError!),
                  TextButton(
                    onPressed: () => _search(page: _page),
                    child: const Text('Aramayı yeniden dene'),
                  ),
                ],
                if (!_searching && _searchError == null) ...[
                  if (_experts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Aramanızla eşleşen onaylı diyetisyen bulunamadı.',
                      ),
                    ),
                  for (final expert in _experts)
                    Card(
                      child: ListTile(
                        key: ValueKey(expert.id),
                        onTap: _sending ? null : () => _select(expert),
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(expert.displayName),
                        subtitle: Text(
                          _active?.dietitianId == expert.id
                              ? 'Aktif diyetisyeniniz'
                              : _knownPending.contains(expert.id)
                              ? 'Onay bekleyen isteğiniz var'
                              : 'Onaylı diyetisyen · Profili görüntüle',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  if (_total > DietitianApi.pageSize || _page > 1)
                    _pager(
                      page: _page,
                      total: _total,
                      disabled: _sending,
                      label: 'Uzmanlar',
                      load: (page) => _search(page: page),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
