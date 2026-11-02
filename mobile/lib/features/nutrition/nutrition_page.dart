import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import 'manual_meal_log_page.dart';
import 'nutrition_plan_api.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({
    this.active = true,
    this.refreshRevision = 0,
    this.api,
    super.key,
  });
  final bool active;
  final int refreshRevision;
  final NutritionPlanApi? api;
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  NutritionPlanApi? _api;
  NutritionPlanResponse? _plan;
  String? _owner, _error;
  int _revision = 0;
  bool _loading = false, _loaded = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canRead =>
      widget.active && _foreground && _session?.isAuthenticated == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    final owner = session?.user?.id;
    if (!identical(session, _session) || owner != _owner) {
      _clear();
      _session = session;
      _owner = owner;
      _api = widget.api ?? (session == null ? null : NutritionPlanApi(session));
    }
    if (session?.isAuthenticated != true) _clear();
    if (_canRead && !_loaded && !_loading) _load();
  }

  @override
  void didUpdateWidget(covariant NutritionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.api != widget.api) {
      _clear();
      _api =
          widget.api ?? (_session == null ? null : NutritionPlanApi(_session!));
      if (_canRead) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_clear);
    if (_canRead) _load();
  }

  void _clear() {
    ++_revision;
    _plan = null;
    _error = null;
    _loading = false;
    _loaded = false;
  }

  Future<void> _reload() async {
    setState(_clear);
    await _load();
  }

  Future<void> _load() async {
    if (!_canRead || _api == null || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _loaded = false;
      _plan = null;
      _error = null;
    });
    try {
      final plan = await _api!.active();
      if (!mounted || revision != _revision || !_canRead) return;
      setState(() {
        _plan = plan;
        _loaded = true;
      });
    } catch (error) {
      if (mounted && revision == _revision && _canRead) {
        setState(
          () => _error = error is NutritionPlanApiException
              ? error.message
              : 'Program yüklenemedi. Lütfen yeniden deneyin.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  static const _days = [
    'Her gün',
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  String _date(String value) =>
      '${value.substring(8, 10)}.${value.substring(5, 7)}.${value.substring(0, 4)}';
  List<Widget> _content(NutritionPlanResponse plan) {
    final theme = Theme.of(context);
    final groups = plan.items
        .map((item) => item.alternativeGroupId)
        .whereType<String>()
        .toSet()
        .toList();
    return [
      Text(plan.title, style: theme.textTheme.titleLarge),
      Text(
        plan.dietitianId == null
            ? 'Kişisel programınız · Salt okunur görünüm'
            : 'Diyetisyeniniz tarafından atanmış program · Salt okunur',
      ),
      Text('Aktif program · Sürüm ${plan.versionNumber}'),
      Text(
        'Başlangıç: ${_date(plan.startDate)}${plan.endDate == null ? '' : ' · Bitiş: ${_date(plan.endDate!)}'}',
      ),
      if (plan.dailyCaloriesTargetKcal != null)
        Text(
          'Programdaki günlük enerji hedefi: ${plan.dailyCaloriesTargetKcal.toString().replaceAll('.', ',')} kcal',
        ),
      if (plan.dailyWaterTargetMl != null)
        Text(
          'Programdaki günlük su hedefi: ${plan.dailyWaterTargetMl.toString().replaceAll('.', ',')} mL',
        ),
      for (final day in <int?>[null, 1, 2, 3, 4, 5, 6, 7])
        if (plan.items.any((item) => item.dayOfWeek == day)) ...[
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(_days[day ?? 0], style: theme.textTheme.titleLarge),
          ),
          for (final meal in nutritionMealLabels.entries)
            if (plan.items.any(
              (item) => item.dayOfWeek == day && item.mealType == meal.key,
            )) ...[
              const SizedBox(height: 8),
              Text(meal.value, style: theme.textTheme.titleMedium),
              for (final item in plan.items.where(
                (item) => item.dayOfWeek == day && item.mealType == meal.key,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.description),
                      Text(
                        'Miktar önerisi: ${item.recommendedQuantity ?? 'Belirtilmemiş'}',
                      ),
                      if (item.alternativeGroupId != null)
                        Text(
                          'Alternatif ${groups.indexOf(item.alternativeGroupId!) + 1}',
                        ),
                    ],
                  ),
                ),
            ],
        ],
      if (groups.isNotEmpty)
        const Text(
          'Aynı alternatif grubundaki öneriler birbirinin yerine geçer; birlikte tüketim zorunluluğu değildir.',
        ),
      const SizedBox(height: 8),
      const Text(
        'Bu program önerileri, kaydettiğiniz gerçek tüketimden ayrıdır.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final readable = _canRead;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.spacingMedium),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card([
                    Text(
                      'Beslenme alanınız',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      'Öğünlerinizi kaydedin ve aktif beslenme programınızı görüntüleyin.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Öğün listesi henüz kullanıma açık değil. Manuel giriş ekranını inceleyebilirsiniz.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (context) => const ManualMealLogPage(),
                          ),
                        );
                        if (mounted) await _reload();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Öğün ekle'),
                    ),
                  ]),
                  _card([
                    Semantics(
                      header: true,
                      child: Text(
                        'Beslenme Programım',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (!readable)
                      const Text(
                        'Programı görüntülemek için oturumunuz doğrulanmalıdır.',
                      )
                    else ...[
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: LinearProgressIndicator(
                            semanticsLabel: 'Aktif program yükleniyor',
                          ),
                        ),
                      if (_error != null)
                        Semantics(liveRegion: true, child: Text(_error!)),
                      if (_loaded && _plan == null)
                        const Text(
                          'Henüz aktif bir beslenme programınız bulunmuyor. Diyetisyeniniz programı etkinleştirdiğinde burada görebilirsiniz.',
                        ),
                      if (_plan != null) ..._content(_plan!),
                      TextButton.icon(
                        onPressed: _loading ? null : _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          _error == null ? 'Programı yenile' : 'Yeniden dene',
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
