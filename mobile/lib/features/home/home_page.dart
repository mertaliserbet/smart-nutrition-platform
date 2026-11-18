import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../nutrition/manual_meal_log_page.dart';
import '../auth/auth_session.dart';
import '../nutrition/meal_log_api.dart';
import '../nutrition/meal_log_history_page.dart';
import '../nutrition/nutrition_plan_api.dart';
import '../water/water_log_api.dart';
import '../water/water_log_form_page.dart';
import '../water/water_summary_card.dart';
import '../personal_nutrition_targets/personal_nutrition_target_api.dart';
import '../personal_nutrition_targets/personal_nutrition_target_page.dart';
import '../personal_nutrition_targets/target_progress.dart';
import 'dashboard_data.dart';
import 'dashboard_live_cards.dart';
import 'dashboard_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.onViewNutrition,
    this.active = true,
    this.waterApi,
    this.mealApi,
    this.planApi,
    this.targetApi,
    this.refreshRevision = 0,
    this.now = DateTime.now,
    super.key,
  });

  final VoidCallback onViewNutrition;
  final bool active;
  final WaterLogApi? waterApi;
  final MealLogApi? mealApi;
  final NutritionPlanApi? planApi;
  final PersonalNutritionTargetApi? targetApi;
  final int refreshRevision;
  final DateTime Function() now;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _waterRevision = 0;
  int _mealRevision = 0, _planRevision = 0, _targetRevision = 0;
  AuthSession? _session;
  MealLogApi? _mealApi;
  NutritionPlanApi? _planApi;
  PersonalNutritionTargetApi? _targetApi;
  String? _owner;
  WaterDayRange? _day;
  Timer? _midnight;
  AsyncSnapshot<DashboardMeals> _meals = const AsyncSnapshot.nothing();
  AsyncSnapshot<NutritionPlanResponse?> _plan = const AsyncSnapshot.nothing();
  AsyncSnapshot<PersonalNutritionTargetResponse> _targets =
      const AsyncSnapshot.nothing();
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canRead =>
      widget.active &&
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    ++_mealRevision;
    ++_planRevision;
    ++_targetRevision;
    _day = null;
    _midnight?.cancel();
    _meals = const AsyncSnapshot.nothing();
    _plan = const AsyncSnapshot.nothing();
    _targets = const AsyncSnapshot.nothing();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session =
        AuthSessionScope.maybeOf(context) ??
        widget.mealApi?.session ??
        widget.planApi?.session ??
        widget.targetApi?.session ??
        widget.waterApi?.session;
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _mealApi =
          widget.mealApi ?? (session == null ? null : MealLogApi(session));
      _planApi =
          widget.planApi ??
          (session == null ? null : NutritionPlanApi(session));
      _targetApi =
          widget.targetApi ??
          (session == null ? null : PersonalNutritionTargetApi(session));
    }
    if (!_canRead) {
      _clear();
    } else {
      if (_meals.connectionState == ConnectionState.none) _loadMeals();
      if (_plan.connectionState == ConnectionState.none) _loadPlan();
      if (_targets.connectionState == ConnectionState.none) _loadTargets();
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.mealApi != widget.mealApi ||
        oldWidget.planApi != widget.planApi ||
        oldWidget.targetApi != widget.targetApi) {
      _clear();
      _mealApi =
          widget.mealApi ?? (_session == null ? null : MealLogApi(_session!));
      _planApi =
          widget.planApi ??
          (_session == null ? null : NutritionPlanApi(_session!));
      _targetApi =
          widget.targetApi ??
          (_session == null ? null : PersonalNutritionTargetApi(_session!));
      if (_canRead) {
        _loadMeals();
        _loadPlan();
        _loadTargets();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_clear);
    if (_canRead) {
      _loadMeals();
      _loadPlan();
      _loadTargets();
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadMeals() async {
    if (!_canRead ||
        _mealApi == null ||
        _meals.connectionState == ConnectionState.waiting) {
      return;
    }
    final revision = ++_mealRevision,
        day = WaterDayRange.forDate(widget.now().toLocal());
    setState(() {
      _day = day;
      _meals = const AsyncSnapshot.waiting();
    });
    _midnight?.cancel();
    final delay =
        day.to.difference(widget.now().toLocal()) +
        const Duration(milliseconds: 50);
    _midnight = Timer(
      delay.isNegative ? const Duration(milliseconds: 50) : delay,
      () {
        if (mounted && _canRead) _refresh();
      },
    );
    try {
      final rows = await _mealApi!.forRange(from: day.from, to: day.to);
      if (!mounted || !_canRead || revision != _mealRevision) return;
      if (WaterDayRange.forDate(widget.now().toLocal()).key != day.key) {
        await _refresh();
        return;
      }
      setState(
        () => _meals = AsyncSnapshot.withData(
          ConnectionState.done,
          DashboardMeals(rows),
        ),
      );
    } catch (error) {
      if (mounted && _canRead && revision == _mealRevision) {
        setState(
          () => _meals = AsyncSnapshot.withError(
            ConnectionState.done,
            error is MealLogApiException
                ? error.message
                : 'Öğün özetleri yüklenemedi. Lütfen yeniden deneyin.',
          ),
        );
      }
    }
  }

  Future<void> _loadPlan() async {
    if (!_canRead ||
        _planApi == null ||
        _plan.connectionState == ConnectionState.waiting) {
      return;
    }
    final revision = ++_planRevision;
    setState(() => _plan = const AsyncSnapshot.waiting());
    try {
      final plan = await _planApi!.active();
      if (mounted && _canRead && revision == _planRevision) {
        setState(
          () => _plan = AsyncSnapshot.withData(ConnectionState.done, plan),
        );
      }
    } catch (error) {
      if (mounted && _canRead && revision == _planRevision) {
        setState(
          () => _plan = AsyncSnapshot.withError(
            ConnectionState.done,
            error is NutritionPlanApiException
                ? error.message
                : 'Program yüklenemedi. Lütfen yeniden deneyin.',
          ),
        );
      }
    }
  }

  Future<void> _loadTargets() async {
    if (!_canRead ||
        _targetApi == null ||
        _targets.connectionState == ConnectionState.waiting) {
      return;
    }
    final revision = ++_targetRevision;
    setState(() => _targets = const AsyncSnapshot.waiting());
    try {
      final response = await _targetApi!.get();
      if (mounted && _canRead && revision == _targetRevision) {
        setState(
          () =>
              _targets = AsyncSnapshot.withData(ConnectionState.done, response),
        );
      }
    } catch (error) {
      if (mounted && _canRead && revision == _targetRevision) {
        setState(
          () => _targets = AsyncSnapshot.withError(
            ConnectionState.done,
            error is PersonalNutritionTargetApiException
                ? error.message
                : 'Kişisel hedefler yüklenemedi.',
          ),
        );
      }
    }
  }

  Future<void> _openTargets() async {
    if (!_canRead) return;
    final owner = _owner;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PersonalNutritionTargetPage(api: _targetApi),
      ),
    );
    if (mounted && _canRead && owner == _owner) await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _clear();
      ++_waterRevision;
    });
    await Future.wait([_loadMeals(), _loadPlan(), _loadTargets()]);
  }

  Future<void> _addMeal() async {
    final owner = _owner;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ManualMealLogPage(api: _mealApi)),
    );
    if (!mounted || !_canRead || owner != _owner) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Öğün kaydedildi.')));
    }
    await _refresh();
  }

  Future<void> _history() async {
    final owner = _owner;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MealLogHistoryPage(api: _mealApi),
      ),
    );
    if (mounted && _canRead && owner == _owner) await _refresh();
  }

  Future<void> _addWater() async {
    final owner = _owner;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WaterLogFormPage(api: widget.waterApi, now: widget.now),
      ),
    );
    if (!mounted || !_canRead || owner != _owner) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Su kaydı tamamlandı.')));
    }
    setState(() => ++_waterRevision);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final energy = DashboardLiveCards.energy(
      context,
      _meals,
      _plan,
      _loadMeals,
      _targets,
      _loadTargets,
      _openTargets,
    );
    final macros = DashboardLiveCards.macros(_meals, _targets);
    final water = WaterSummaryCard(
      api: widget.waterApi,
      now: widget.now,
      active: widget.active,
      refreshRevision: _waterRevision,
      target: EffectiveNutritionTarget.resolve(
        'dailyWaterTargetMl',
        _targets,
        plan: _plan,
      ),
    );
    final plan = DashboardLiveCards.program(
      _plan,
      widget.onViewNutrition,
      _loadPlan,
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        primary: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spacingMedium),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Startup/layout transitions can temporarily have no width.
                  // Wait for usable constraints before laying out the cards.
                  if (constraints.maxWidth <= 0) return const SizedBox.shrink();

                  final wide =
                      constraints.maxWidth >= 840 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Gününüz, bir bakışta.',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      Text(
                        '${(_day?.from ?? widget.now()).day}.${(_day?.from ?? widget.now()).month}.${(_day?.from ?? widget.now()).year}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  energy,
                                  const SizedBox(
                                    height: AppTokens.spacingMedium,
                                  ),
                                  macros,
                                ],
                              ),
                            ),
                            const SizedBox(width: AppTokens.spacingLarge),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  water,
                                  const SizedBox(
                                    height: AppTokens.spacingMedium,
                                  ),
                                  plan,
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        energy,
                        const SizedBox(height: AppTokens.spacingMedium),
                        macros,
                        const SizedBox(height: AppTokens.spacingMedium),
                        water,
                      ],
                      const SizedBox(height: AppTokens.spacingLarge),
                      _QuickActions(onWater: _addWater, onMeal: _addMeal),
                      if (!wide) ...[
                        const SizedBox(height: AppTokens.spacingLarge),
                        plan,
                      ],
                      const SizedBox(height: AppTokens.spacingLarge),
                      DashboardLiveCards.recent(_meals, _history),
                      const SizedBox(height: AppTokens.spacingMedium),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onWater, required this.onMeal});
  final Future<void> Function() onWater;
  final Future<void> Function() onMeal;

  static const _actions = [
    (label: 'Öğün ekle', icon: Icons.restaurant_outlined),
    (label: 'Su ekle', icon: Icons.water_drop_outlined),
    (label: 'Aktivite ekle', icon: Icons.directions_walk_rounded),
    (label: 'Tahlil ekle', icon: Icons.science_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardSectionHeading(
          title: 'Hızlı işlemler',
          subtitle:
              'Öğün ve su kaydedin; aktivite ve tahlil işlemleri önizlemedir.',
        ),
        const SizedBox(height: AppTokens.spacingMedium),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final columns = largeText || constraints.maxWidth < 320
                ? 1
                : (constraints.maxWidth >= 700 ? 4 : 2);
            final width =
                (constraints.maxWidth -
                    (columns - 1) * AppTokens.spacingSmall) /
                columns;
            return Wrap(
              spacing: AppTokens.spacingSmall,
              runSpacing: AppTokens.spacingSmall,
              children: [
                for (final action in _actions)
                  SizedBox(
                    width: width,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(AppTokens.spacingMedium),
                        foregroundColor: colors.onSurface,
                        side: BorderSide(color: colors.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusMedium,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        if (action.label == 'Öğün ekle') {
                          await onMeal();
                        } else if (action.label == 'Su ekle') {
                          await onWater();
                        } else {
                          _showPreview(context, action.label);
                        }
                      },
                      child: Column(
                        children: [
                          Icon(action.icon, color: colors.primary),
                          const SizedBox(height: AppTokens.spacingSmall),
                          Text(action.label, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showPreview(BuildContext context, String label) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.spacingLarge),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$label · Demo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTokens.spacingMedium),
              const Text('Bu demo önizlemesinde yeni kayıt oluşturulmaz.'),
              const SizedBox(height: AppTokens.spacingLarge),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
