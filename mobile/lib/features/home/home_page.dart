import 'dart:async';
import 'package:flutter/material.dart';

import '../nutrition/manual_meal_log_page.dart';
import '../auth/auth_session.dart';
import '../nutrition/meal_log_api.dart';
import '../nutrition/nutrition_plan_api.dart';
import '../water/water_log_api.dart';
import '../water/water_summary_card.dart';
import '../personal_nutrition_targets/personal_nutrition_target_api.dart';
import '../personal_nutrition_targets/personal_nutrition_target_page.dart';
import '../personal_nutrition_targets/target_progress.dart';
import 'dashboard_data.dart';
import '../onboarding/onboarding_theme.dart';
import 'day_widgets.dart';
import 'day_nutrition_card.dart';
import 'day_plan_cards.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.onViewNutrition,
    this.onViewProfile,
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
  final VoidCallback? onViewProfile;
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

  @override
  Widget build(BuildContext context) {
    final day = _day?.from ?? widget.now().toLocal();
    final plannedMeals = dayPlanMeals(_plan.data, day);
    final assigned = _plan.data?.dietitianId != null;
    // A recording opportunity, not a claim that earlier recommendations were eaten.
    final unrecorded = _meals.hasData
        ? plannedMeals
              .where(
                (items) => !_meals.data!.records.any(
                  (meal) => meal.mealType == items.first.mealType,
                ),
              )
              .toList()
        : <List<NutritionPlanItem>>[];
    return Theme(
      data: OnboardingTheme.data,
      child: ColoredBox(
        color: OnboardingTheme.background,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            primary: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 240) {
                      return const SizedBox.shrink();
                    }
                    final inset = constraints.maxWidth <= 410 ? 17.0 : 20.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(inset, 26, inset, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DayHeader(
                            day: day,
                            name: _session?.user?.displayName,
                            onProfile: widget.onViewProfile,
                          ),
                          DayMealActions(onAdd: _addMeal),
                          const SizedBox(height: 16),
                          DayEnergyCard(
                            meals: _meals,
                            plan: _plan,
                            targets: _targets,
                            onRetryMeals: _loadMeals,
                            onRetryTargets: _loadTargets,
                            onTargets: _openTargets,
                          ),
                          const SizedBox(height: 17),
                          WaterSummaryCard(
                            api: widget.waterApi,
                            now: widget.now,
                            active: widget.active,
                            refreshRevision: _waterRevision,
                            limely: true,
                            target: EffectiveNutritionTarget.resolve(
                              'dailyWaterTargetMl',
                              _targets,
                              plan: _plan,
                            ),
                          ),
                          if (assigned && unrecorded.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            DayPlannedMeal(
                              items: unrecorded.first,
                              onSave: _addMeal,
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.only(top: 24, bottom: 21),
                            child: DayAppointment(),
                          ),
                          DayPlanCard(
                            plan: _plan,
                            meals: _meals,
                            day: day,
                            onOpen: widget.onViewNutrition,
                            onRetry: _loadPlan,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
