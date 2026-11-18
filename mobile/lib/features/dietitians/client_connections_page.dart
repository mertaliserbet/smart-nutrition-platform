import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import '../auth/login_page.dart';
import 'dietitian_api.dart';

class ClientConnectionsPage extends StatefulWidget {
  const ClientConnectionsPage({this.api, this.names = const {}, super.key});
  final DietitianApi? api;
  final Map<String, String> names;
  @override
  State<ClientConnectionsPage> createState() => _ClientConnectionsPageState();
}

class _ClientConnectionsPageState extends State<ClientConnectionsPage>
    with WidgetsBindingObserver {
  DietitianApi? _api;
  AuthSession? _session;
  String? _owner;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  String _status = 'active';
  List<RelationshipResponse> _rows = [];
  Map<String, DataSharingPermission> _permissions = {};
  int _page = 1, _total = 0, _revision = 0;
  bool _loading = false, _busy = false, _ready = false, _confirming = false;
  String? _error, _message;
  static const _labels = {
    'active': 'Aktif / Kabul edilen',
    'pending': 'Onay bekleyen',
    'rejected': 'Reddedilen',
    'ended': 'Sonlandırılan',
  };
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  bool get _available =>
      _authorized && _ready && !_loading && !_busy && !_confirming;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    ++_revision;
    _ready = false;
    _loading = false;
    _rows = [];
    _permissions = {};
    _total = 0;
    _message = null;
    _error = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _api = session == null
          ? null
          : identical(widget.api?.session, session)
          ? widget.api
          : DietitianApi(session);
    }
    if (!_authorized) {
      _clear();
    } else if (!_ready && !_loading && _error == null && !_busy) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _clear();
    });
    if (_authorized && !_busy) _load();
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _explain(Object error) => error is DietitianApiException
      ? error.message
      : 'İşlem tamamlanamadı. Durumu yenileyip kontrol edin.';

  Future<void> _load({int page = 1}) async {
    if (_api == null || !_authorized) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
      _rows = [];
      _permissions = {};
    });
    try {
      final result = await _api!.relationships(status: _status, page: page);
      if (!mounted || !_authorized || revision != _revision) return;
      List<DataSharingPermission> permissions = [];
      if (_status == 'active' && result.items.isNotEmpty) {
        permissions = await _api!.permissions(result.items.single.id);
      }
      if (!mounted || !_authorized || revision != _revision) return;
      setState(() {
        _rows = result.items;
        _total = result.totalCount;
        _page = page;
        _permissions = {
          for (final permission in permissions) permission.category: permission,
        };
        _ready = true;
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = _explain(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String description, String action) async {
    if (!_available) return false;
    final revision = _revision, owner = _owner;
    setState(() => _confirming = true);
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(description)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
          ) ==
          true;
      return confirmed &&
          mounted &&
          _authorized &&
          owner == _owner &&
          revision == _revision;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _mutate(
    Future<void> Function() operation,
    String success,
  ) async {
    if (!_available) return;
    final revision = _revision, owner = _owner;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await operation();
      if (!mounted ||
          !_authorized ||
          owner != _owner ||
          revision != _revision) {
        return;
      }
      setState(() => _message = success);
      await _load();
    } catch (error) {
      if (!mounted ||
          !_authorized ||
          owner != _owner ||
          revision != _revision) {
        return;
      }
      setState(() {
        _ready = false;
        _rows = [];
        _permissions = {};
        _error =
            '${_explain(error)} Tekrar işlem yapmadan “Durumu yenile” ile kontrol edin.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_authorized && !_ready && _error == null && !_loading) _load();
      }
    }
  }

  Future<void> _end(RelationshipResponse row) async {
    final pending = row.status == 'pending';
    if (!const ['pending', 'active'].contains(row.status)) return;
    final action = pending ? 'İsteği İptal Et' : 'Bağlantıyı Sonlandır';
    final confirmed = await _confirm(
      action,
      pending
          ? 'Bekleyen bağlantı isteğiniz iptal edilecek. Devam etmek istiyor musunuz?'
          : 'Diyetisyenle aktif bağlantınız sona erecek ve yeni veri erişimi kapanacak. Bu uzmanın aktif atanmış programı arşivlenir; kendi geçmiş kayıtlarınız korunur.',
      action,
    );
    if (!mounted || !confirmed) return;
    await _mutate(
      () async {
        await _api!.endRelationship(row);
      },
      pending
          ? 'Bağlantı isteğiniz iptal edildi.'
          : 'Bağlantınız sonlandırıldı. Diyetisyenin yeni erişimi kapatıldı.',
    );
  }

  Future<void> _share(
    RelationshipResponse row,
    String category,
    bool granted,
  ) async {
    if (row.status != 'active') return;
    final current = _permissions[category];
    final label = category == 'meal_logs'
        ? 'Öğün kayıtları'
        : 'Beslenme programları';
    final action = category == 'meal_logs'
        ? (granted ? 'Öğün paylaşımına izin ver' : 'Öğün iznini geri al')
        : (granted ? 'Paylaşıma İzin Ver' : 'İzni Geri Al');
    final confirmed = await _confirm(
      action,
      granted
          ? '$label kategorisinin bu diyetisyenle paylaşılmasına izin veriyor musunuz? Yalnız bu kategori açılır; diğer izinleriniz değişmez. İzninizi daha sonra geri alabilirsiniz.'
          : 'Diyetisyenin $label kategorisine yeni erişimi kapatılacak. Diğer izinleriniz, aktif bağlantınız ve kendi kayıtlarınız korunur.',
      action,
    );
    if (!mounted || !confirmed) return;
    await _mutate(
      () async {
        await _api!.setPermission(
          relationshipId: row.id,
          isGranted: granted,
          current: current,
          category: category,
        );
      },
      granted
          ? '$label için paylaşım izni verildi.'
          : 'Paylaşım izniniz geri alındı.',
    );
  }

  Widget _connection(RelationshipResponse row) {
    return Card(
      key: ValueKey(row.id),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.names[row.dietitianId] ?? 'Diyetisyen bağlantısı',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(switch (row.status) {
              'pending' =>
                'İsteğiniz gönderildi. Diyetisyenin kabul veya ret yanıtı bekleniyor.',
              'active' => 'İsteğiniz kabul edildi; bağlantınız aktif.',
              'rejected' => 'Diyetisyen bağlantı isteğinizi reddetti.',
              _ => 'Bu bağlantı sona erdi. Yeni veri erişimi kapalıdır.',
            }),
            if (row.status == 'pending')
              OutlinedButton(
                onPressed: _available ? () => _end(row) : null,
                child: const Text('İsteği İptal Et'),
              ),
            if (row.status == 'active') ...[
              for (final category in DietitianApi.sharingCategories) ...[
                const SizedBox(height: 16),
                Text(
                  category == 'meal_logs'
                      ? 'Öğün kayıtları'
                      : 'Beslenme programları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  category == 'meal_logs'
                      ? (_permissions[category]?.isGranted == true
                            ? 'Öğün paylaşımı açık.'
                            : 'Öğün paylaşımı kapalı. Bağlantı veya program izni öğün paylaşımını açmaz.')
                      : (_permissions[category]?.isGranted == true
                            ? 'Paylaşım izni açık.'
                            : 'Paylaşım izni kapalı. Bağlantı onayı tek başına paylaşım izni vermez.'),
                ),
                Text(
                  category == 'meal_logs'
                      ? 'Öğün izni bağımsızdır; program izni öğün paylaşımını açmaz.'
                      : 'Bu izin yalnız beslenme programlarını kapsar.',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: ValueKey('sharing-$category'),
                  onPressed: _available
                      ? () => _share(
                          row,
                          category,
                          _permissions[category]?.isGranted != true,
                        )
                      : null,
                  child: Text(
                    category == 'meal_logs'
                        ? (_permissions[category]?.isGranted == true
                              ? 'Öğün iznini geri al'
                              : 'Öğün paylaşımına izin ver')
                        : (_permissions[category]?.isGranted == true
                              ? 'İzni Geri Al'
                              : 'Paylaşıma İzin Ver'),
                  ),
                ),
              ],
              OutlinedButton(
                onPressed: _available ? () => _end(row) : null,
                child: const Text('Bağlantıyı Sonlandır'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AuthSessionScope.maybeOf(context)?.isAuthenticated != true) {
      return const LoginPage();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Bağlantılarım ve paylaşım')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.spacingMedium),
              children: [
                const Text(
                  'İsteği siz başlatırsınız; kabul veya ret yanıtını diyetisyen verir. Program ve öğün paylaşım izinlerini birbirinden bağımsız yönetirsiniz.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Bağlantı durumu',
                  ),
                  items: [
                    for (final entry in _labels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _busy || _loading || _confirming
                      ? null
                      : (value) {
                          if (value == null || value == _status) return;
                          setState(() {
                            _status = value;
                            _message = null;
                          });
                          _load();
                        },
                ),
                TextButton.icon(
                  onPressed: _busy || _loading || _confirming
                      ? null
                      : () => _load(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Durumu yenile'),
                ),
                if (_loading || _busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Bağlantı ve paylaşım işlemi sürüyor',
                  ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (!_ready && !_loading && !_busy)
                  const Text('Güncel durum doğrulanmadan işlem yapılamaz.'),
                if (_ready) ...[
                  if (_rows.isEmpty)
                    Text(switch (_status) {
                      'pending' => 'Onay bekleyen bağlantı isteğiniz yok.',
                      'active' => 'Aktif diyetisyen bağlantınız yok.',
                      'rejected' => 'Reddedilen bağlantı isteğiniz yok.',
                      _ => 'Sonlandırılan bağlantınız yok.',
                    }),
                  for (final row in _rows) _connection(row),
                  if (_total > DietitianApi.pageSize || _page > 1)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _available && _page > 1
                              ? () => _load(page: _page - 1)
                              : null,
                          child: const Text('Önceki bağlantılar'),
                        ),
                        Text('Sayfa $_page'),
                        TextButton(
                          onPressed:
                              _available &&
                                  _page * DietitianApi.pageSize < _total
                              ? () => _load(page: _page + 1)
                              : null,
                          child: const Text('Sonraki bağlantılar'),
                        ),
                      ],
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
