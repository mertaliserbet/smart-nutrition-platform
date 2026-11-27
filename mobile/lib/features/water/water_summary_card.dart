import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../home/dashboard_widgets.dart';
import 'water_log_api.dart';
import 'water_log_form_page.dart';
import '../personal_nutrition_targets/target_progress.dart';
import 'day_water_card.dart';

class WaterHistoryPage extends StatelessWidget {
  const WaterHistoryPage({this.api, this.now = DateTime.now, super.key});
  final WaterLogApi? api;
  final DateTime Function() now;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Su geçmişi')),
    body: WaterSummaryCard(api: api, now: now, showHistory: true),
  );
}

class WaterSummaryCard extends StatefulWidget {
  const WaterSummaryCard({
    this.api,
    this.now = DateTime.now,
    this.active = true,
    this.refreshRevision = 0,
    this.showHistory = false,
    this.target,
    this.limely = false,
    super.key,
  });
  final WaterLogApi? api;
  final EffectiveNutritionTarget? target;
  final bool limely;
  final DateTime Function() now;
  final bool active, showHistory;
  final int refreshRevision;
  @override
  State<WaterSummaryCard> createState() => _WaterSummaryCardState();
}

class _WaterSummaryCardState extends State<WaterSummaryCard>
    with WidgetsBindingObserver {
  AuthSession? _session;
  WaterLogApi? _api;
  String? _owner, _error;
  WaterDayRange? _day;
  WaterLogPage? _rows;
  num? _total;
  Timer? _dayTimer;
  int _generation = 0, _page = 1;
  bool _loading = false, _mutating = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _authorized =>
      widget.active &&
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
      _api = widget.api ?? (session == null ? null : WaterLogApi(session));
    }
    if (!_authorized) {
      _clear();
    } else if (_total == null && !_loading && _error == null && !_mutating) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant WaterSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.refreshRevision != oldWidget.refreshRevision ||
        widget.api != oldWidget.api) {
      _clear();
      _api = widget.api ?? (_session == null ? null : WaterLogApi(_session!));
      if (_authorized) _load();
    }
  }

  void _clear() {
    ++_generation;
    _total = null;
    _rows = null;
    _day = null;
    _error = null;
    _loading = false;
    _dayTimer?.cancel();
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
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleDayChange() {
    _dayTimer?.cancel();
    if (!_authorized) return;
    final now = widget.now().toLocal();
    final next = WaterDayRange.forDate(now).to;
    final delay = next.difference(now) + const Duration(milliseconds: 50);
    _dayTimer = Timer(
      delay.isNegative ? const Duration(milliseconds: 50) : delay,
      () {
        if (!mounted || !_authorized) return;
        setState(_clear);
        _load();
      },
    );
  }

  Future<void> _load({int? page}) async {
    if (!_authorized || _api == null || _loading || _mutating) return;
    final generation = ++_generation,
        day = WaterDayRange.forDate(widget.now().toLocal());
    setState(() {
      _loading = true;
      _error = null;
      _total = null;
      _rows = null;
      _day = day;
      _page = page ?? _page;
    });
    _scheduleDayChange();
    try {
      final values = await Future.wait<Object>([
        _api!.dailyTotal(day),
        if (widget.showHistory) _api!.list(page: _page),
      ]);
      if (!mounted || !_authorized || generation != _generation) return;
      if (WaterDayRange.forDate(widget.now().toLocal()).key != day.key) {
        setState(_clear);
        await _load();
        return;
      }
      setState(() {
        _total = values[0] as num;
        _rows = widget.showHistory ? values[1] as WaterLogPage : null;
      });
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is WaterLogApiException
              ? error.message
              : 'Su tüketimi yüklenemedi.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Widget page) async {
    if (_mutating || _loading) return;
    final owner = _owner;
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
    if (!mounted || !_authorized || owner != _owner) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Su kaydı tamamlandı.')));
    }
    await _load(page: 1);
  }

  Future<void> _delete(WaterLog row) async {
    if (_mutating || _loading || !_authorized) return;
    final owner = _owner, generation = _generation;
    setState(() => _mutating = true);
    var changed = false;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Su kaydı silinsin mi?'),
          content: const Text(
            'Bu kayıt geçmişinizden ve tüketim toplamından kaldırılacak.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          !_authorized ||
          owner != _owner ||
          generation != _generation) {
        return;
      }
      await _api!.delete(row.id);
      changed = true;
    } catch (error) {
      if (mounted &&
          _authorized &&
          owner == _owner &&
          generation == _generation) {
        setState(() {
          _total = null;
          _rows = null;
          _error =
              '${error is WaterLogApiException ? error.message : 'Silme işlemi doğrulanamadı.'} Yeniden işlem yapmadan önce su bilgilerini yenileyin.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
        if (_authorized && (changed || generation != _generation)) {
          await _load(page: 1);
        }
      }
    }
  }

  Future<void> _quickAdd() async {
    if (!_authorized ||
        _api == null ||
        _loading ||
        _mutating ||
        _error != null ||
        _total == null) {
      return;
    }
    final now = widget.now().toLocal();
    if (_day?.key != WaterDayRange.forDate(now).key) {
      await _load();
      return;
    }
    final owner = _owner, generation = _generation;
    setState(() => _mutating = true);
    var saved = false;
    try {
      await _api!.create(amountMl: 250, consumedAt: now);
      saved = true;
    } catch (error) {
      if (mounted &&
          _authorized &&
          owner == _owner &&
          generation == _generation) {
        setState(() {
          _total = null;
          _error =
              '${error is WaterLogApiException ? error.message : 'Su kaydı doğrulanamadı.'} Yeniden işlem yapmadan önce su bilgilerini yenileyin.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
        if (_authorized && (saved || generation != _generation)) {
          await _load(page: 1);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.limely && !widget.showHistory) {
      return DayWaterCard(
        authorized: _authorized,
        loading: _loading,
        saving: _mutating,
        total: _total,
        target: widget.target,
        error: _error,
        onAdd:
            _authorized &&
                !_loading &&
                !_mutating &&
                _error == null &&
                _total != null
            ? _quickAdd
            : null,
        onHistory: _authorized && !_loading && !_mutating
            ? () => _open(WaterHistoryPage(api: _api, now: widget.now))
            : null,
        onRetry: _load,
      );
    }
    final day = _day?.from ?? widget.now().toLocal();
    final children = <Widget>[
      DashboardSectionHeading(
        title: 'Su tüketimi',
        subtitle: 'Bugün · ${day.day}.${day.month}.${day.year}',
      ),
      const SizedBox(height: 12),
      if (!_authorized)
        const Text('Su tüketiminizi görmek için oturumunuz doğrulanmalıdır.')
      else ...[
        if (_loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Su tüketimi yükleniyor',
          ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_total != null)
          Semantics(
            liveRegion: true,
            child: Text(
              '$_total mL',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        if (_total == 0) const Text('Bugün henüz su kaydınız yok.'),
        if (widget.target != null)
          NutritionTargetProgress(
            target: widget.target!,
            unit: 'mL',
            consumed: _total,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: _loading || _mutating
                  ? null
                  : () => _open(WaterLogFormPage(api: _api, now: widget.now)),
              icon: const Icon(Icons.add),
              label: const Text('Su kaydet'),
            ),
            if (!widget.showHistory)
              OutlinedButton.icon(
                onPressed: _loading || _mutating
                    ? null
                    : () => _open(WaterHistoryPage(api: _api, now: widget.now)),
                icon: const Icon(Icons.history),
                label: const Text('Su geçmişi'),
              ),
            TextButton.icon(
              onPressed: _loading || _mutating ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Su bilgilerini yenile'),
            ),
          ],
        ),
        if (_rows != null) ...[
          Text('${_rows!.totalCount} kayıt · Sayfa $_page'),
          if (_rows!.items.isEmpty)
            Text(
              _rows!.totalCount == 0
                  ? 'Henüz su kaydı yok.'
                  : 'Bu sayfada kayıt yok.',
            ),
          for (final row in _rows!.items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${row.amountMl} mL',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(_localTime(row.consumedAt)),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _mutating || _loading
                              ? null
                              : () => _open(
                                  WaterLogFormPage(
                                    api: _api,
                                    initial: row,
                                    now: widget.now,
                                  ),
                                ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Düzenle'),
                        ),
                        TextButton.icon(
                          onPressed: _mutating || _loading
                              ? null
                              : () => _delete(row),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Kaydı sil'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (_page > 1)
                TextButton(
                  onPressed: _loading || _mutating
                      ? null
                      : () => _load(page: _page - 1),
                  child: const Text('Önceki sayfa'),
                ),
              if (_page * WaterLogApi.pageSize < _rows!.totalCount)
                TextButton(
                  onPressed: _loading || _mutating
                      ? null
                      : () => _load(page: _page + 1),
                  child: const Text('Sonraki sayfa'),
                ),
            ],
          ),
        ],
      ],
    ];
    return widget.showHistory
        ? RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          )
        : DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
  }
}

String _localTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day}.${local.month}.${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
