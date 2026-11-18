import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../body_measurements/body_measurement_api.dart';
import '../body_measurements/measurement_chart.dart';
import '../body_measurements/body_measurement_detail_page.dart';
import '../body_measurements/body_measurement_form_page.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({this.api, this.active = true, super.key});
  final bool active;
  final BodyMeasurementApi? api;
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  BodyMeasurementApi? _api;
  String? _owner, _error;
  List<BodyMeasurement>? _data;
  int _page = 1, _generation = 0;
  bool _loading = false, _foreground = true;
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
      _api = widget.api != null && identical(widget.api!.session, session)
          ? widget.api
          : (session == null ? null : BodyMeasurementApi(session));
    }
    if (!_authorized) {
      _clear();
    } else if (_data == null && !_loading && _error == null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant ProgressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _clear();
      if (_authorized) _load();
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
      final data = await _api!.history();
      if (mounted && _authorized && generation == _generation) {
        setState(() => _data = data);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is BodyMeasurementApiException
              ? error.message
              : 'Ölçümler yüklenemedi.',
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
      ).showSnackBar(const SnackBar(content: Text('Ölçüm işlemi tamamlandı.')));
    }
    await _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final history = _data?.toList();
    history?.sort((a, b) {
      final at = b.measuredAt.compareTo(a.measuredAt);
      return at == 0 ? a.id.compareTo(b.id) : at;
    });
    final visible =
        history?.skip((_page - 1) * 10).take(10).toList() ??
        <BodyMeasurement>[];
    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Gelişiminizi takip edin',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (!_authorized)
            const Text(
              'Ölçümleri görüntülemek için oturumunuz doğrulanmalıdır.',
            )
          else ...[
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : () => _open(BodyMeasurementFormPage(api: _api)),
              icon: const Icon(Icons.add),
              label: const Text('Ölçüm ekle'),
            ),
            if (_loading)
              const LinearProgressIndicator(
                semanticsLabel: 'Ölçümler yükleniyor',
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_data != null) ...[
              if (_data!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.',
                  ),
                )
              else ...[
                for (final field in ['weightKg', 'waistCm', 'hipCm', 'chestCm'])
                  MeasurementChart(rows: _data!, field: field),
                Text(
                  'Ölçüm geçmişi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${_data!.length} ölçüm · Sayfa $_page'),
                for (final row in visible)
                  Card(
                    child: ListTile(
                      title: Text(formatMeasurementTime(row.measuredAt)),
                      subtitle: Text(
                        row.values.entries
                            .where((e) => e.value != null)
                            .map(
                              (e) =>
                                  '${measurementLabels[e.key]}: ${e.value} ${measurementUnit(e.key)}',
                            )
                            .join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(
                        BodyMeasurementDetailPage(id: row.id, api: _api),
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _page <= 1
                          ? null
                          : () => setState(() => _page--),
                      child: const Text('Önceki sayfa'),
                    ),
                    TextButton(
                      onPressed: _page * 10 >= history!.length
                          ? null
                          : () => setState(() => _page++),
                      child: const Text('Sonraki sayfa'),
                    ),
                  ],
                ),
              ],
            ],
            TextButton.icon(
              onPressed: _loading ? null : () => _load(page: 1),
              icon: const Icon(Icons.refresh),
              label: const Text('Ölçümleri yenile'),
            ),
          ],
        ],
      ),
    );
  }
}
