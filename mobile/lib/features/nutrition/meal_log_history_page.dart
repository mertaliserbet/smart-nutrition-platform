import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'meal_log_api.dart';
import 'meal_log_detail_page.dart';
import 'manual_meal_log_page.dart';

class MealLogHistoryPage extends StatefulWidget {
  const MealLogHistoryPage({this.api, super.key});
  final MealLogApi? api;
  @override
  State<MealLogHistoryPage> createState() => _MealLogHistoryPageState();
}

class _MealLogHistoryPageState extends State<MealLogHistoryPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  MealLogApi? _api;
  String? _owner, _error;
  MealLogPage? _data;
  int _page = 1, _generation = 0;
  bool _loading = false, _foreground = true;
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api?.session;
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _page = 1;
      _session = session;
      _owner = session?.user?.id;
      _api = widget.api ?? (session == null ? null : MealLogApi(session));
    }
    if (!_authorized) {
      _clear();
    } else if (_data == null && !_loading && _error == null) {
      _load();
    }
  }

  void _clear() {
    ++_generation;
    _data = null;
    _error = null;
    _loading = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_clear);
    if (_authorized) _load();
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    if (!_authorized || _api == null || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _data = null;
      _error = null;
      _page = page ?? _page;
    });
    try {
      final data = await _api!.list(page: _page);
      if (mounted && _authorized && generation == _generation) {
        setState(() => _data = data);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is MealLogApiException
              ? error.message
              : 'Öğünler yüklenemedi.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Widget page) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
    if (!mounted || !_authorized) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Öğün işlemi tamamlandı.')));
    }
    await _load(page: 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Öğün geçmişi')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (!_authorized)
            const Text('Öğünleri görüntülemek için oturumunuz doğrulanmalıdır.')
          else ...[
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : () => _open(ManualMealLogPage(api: _api)),
              icon: const Icon(Icons.add),
              label: const Text('Öğün ekle'),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Öğünler yükleniyor',
                ),
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_data != null) ...[
              Text('${_data!.totalCount} öğün · Sayfa $_page'),
              if (_data!.items.isEmpty)
                Text(
                  _data!.totalCount == 0
                      ? 'Henüz öğün yok. İlk öğününüzü ekleyebilirsiniz.'
                      : 'Bu sayfada öğün kaydı yok.',
                ),
              for (final meal in _data!.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${mealTypeLabels[meal.mealType]} · ${meal.items.first.displayName}',
                    ),
                    subtitle: Text(
                      '${formatMealLogTime(meal.consumedAt)} · ${meal.items.length} besin',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(MealLogDetailPage(id: meal.id, api: _api)),
                  ),
                ),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (_page > 1)
                  TextButton(
                    onPressed: _loading ? null : () => _load(page: _page - 1),
                    child: const Text('Önceki sayfa'),
                  ),
                if (_data != null &&
                    _page * MealLogApi.pageSize < _data!.totalCount)
                  TextButton(
                    onPressed: _loading ? null : () => _load(page: _page + 1),
                    child: const Text('Sonraki sayfa'),
                  ),
                TextButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Geçmişi yenile'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
