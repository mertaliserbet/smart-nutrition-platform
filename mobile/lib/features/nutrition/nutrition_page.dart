import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/onboarding_theme.dart';
import '../water/water_log_api.dart';
import 'manual_meal_log_page.dart';
import 'meal_comparison_page.dart';
import 'meal_log_api.dart';
import 'meal_log_history_page.dart';
import 'nutrition_plan_api.dart';
import 'nutrition_plan_view.dart';
import 'nutrition_plan_info.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({
    this.active = true,
    this.refreshRevision = 0,
    this.api,
    this.mealApi,
    this.dietitianApi,
    this.initialDate,
    this.onViewProfile,
    super.key,
  });
  final bool active;
  final int refreshRevision;
  final NutritionPlanApi? api;
  final MealLogApi? mealApi;
  final DietitianApi? dietitianApi;
  final DateTime? initialDate;
  final VoidCallback? onViewProfile;
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  NutritionPlanApi? _api;
  MealLogApi? _meals;
  DietitianApi? _experts;
  NutritionPlanResponse? _plan;
  String? _owner, _error, _expert, _mealError;
  List<MealLog>? _records;
  int _revision = 0, _dayRevision = 0;
  bool _loading = false, _loaded = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  late DateTime _date = widget.initialDate ?? DateTime.now();
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

  void _bindApis() {
    final session = _session;
    _api = session == null
        ? null
        : identical(widget.api?.session, session)
        ? widget.api
        : NutritionPlanApi(session);
    _meals = session == null
        ? null
        : identical(widget.mealApi?.session, session)
        ? widget.mealApi
        : MealLogApi(session);
    _experts = session == null
        ? null
        : identical(widget.dietitianApi?.session, session)
        ? widget.dietitianApi
        : DietitianApi(session);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || session?.user?.id != _owner) {
      _clear();
      _date = widget.initialDate ?? DateTime.now();
      _session = session;
      _owner = session?.user?.id;
      _bindApis();
    }
    if (!_canRead) _clear();
    if (_canRead && !_loaded && !_loading && _error == null) _load();
  }

  @override
  void didUpdateWidget(covariant NutritionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.api != widget.api ||
        oldWidget.mealApi != widget.mealApi ||
        oldWidget.dietitianApi != widget.dietitianApi) {
      _clear();
      _bindApis();
      if (_canRead) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _clear();
    });
    if (_canRead) _load();
  }

  void _clear() {
    ++_revision;
    ++_dayRevision;
    _plan = null;
    _expert = null;
    _error = null;
    _records = null;
    _mealError = null;
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
      _error = null;
    });
    bool current() => mounted && revision == _revision && _canRead;
    try {
      final plan = await _api!.active();
      if (!current()) return;
      setState(() {
        _plan = plan;
        _loaded = true;
      });
      if (plan != null) {
        _loadRecords();
        _loadExpert(plan, revision);
      }
    } catch (error) {
      if (current()) {
        setState(
          () => _error = error is NutritionPlanApiException
              ? error.message
              : 'Program yüklenemedi. Lütfen yeniden deneyin.',
        );
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  // Only credit the expert who assigned this plan. Directory errors do not hide it.
  Future<void> _loadExpert(NutritionPlanResponse plan, int revision) async {
    if (plan.dietitianId == null || _experts == null) return;
    bool current() => mounted && _canRead && revision == _revision;
    final experts = _experts!;
    try {
      var page = 1, seen = 0;
      while (current()) {
        final result = await experts.search(page: page);
        if (!current()) return;
        for (final expert in result.items) {
          if (expert.id == plan.dietitianId) {
            setState(() => _expert = expert.displayName);
            return;
          }
        }
        seen += result.items.length;
        if (result.items.isEmpty || seen >= result.totalCount) return;
        page++;
      }
    } catch (_) {
      /* Keep the generic credit when the directory is unavailable. */
    }
  }

  Future<void> _loadRecords() async {
    if (!_canRead || _meals == null || _plan == null) return;
    final revision = ++_dayRevision, planRevision = _revision;
    final day = WaterDayRange.forDate(_date);
    setState(() {
      _records = null;
      _mealError = null;
    });
    bool current() =>
        mounted &&
        _canRead &&
        revision == _dayRevision &&
        planRevision == _revision;
    try {
      final records = await _meals!.forRange(from: day.from, to: day.to);
      if (current()) setState(() => _records = records);
    } catch (_) {
      if (current()) setState(() => _mealError = 'Öğün kayıtları yüklenemedi.');
    }
  }

  void _selectDate(DateTime date) {
    setState(() => _date = date);
    _loadRecords();
  }

  Future<void> _review() async {
    if (!_canRead || _plan?.dietitianId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OnboardingTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: MealComparisonPage(
          planApi: _api,
          initialDate: _date,
          mealApi: _meals,
          sheet: true,
        ),
      ),
    );
    if (mounted && _canRead) _loadRecords();
  }

  Future<void> _info() async {
    final owner = _owner, plan = _plan, expert = _expert;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OnboardingTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => NutritionPlanInfo(
        plan: plan,
        expert: expert,
        owner: owner,
        onAction: (action) async {
          Navigator.of(context).pop();
          if (!mounted || !_canRead || owner != _owner) return;
          switch (action) {
            case 'add':
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const ManualMealLogPage()),
              );
            case 'history':
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const MealLogHistoryPage()),
              );
            case 'targets':
              await Navigator.of(
                context,
              ).pushNamed('/personal-nutrition-targets');
            case 'expert':
              await Navigator.of(context).pushNamed('/dietitians');
          }
          if (mounted && _canRead && owner == _owner) await _reload();
        },
      ),
    );
  }

  @override
  void dispose() {
    ++_revision;
    ++_dayRevision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: RefreshIndicator(
      onRefresh: _reload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: NutritionPlanView(
          plan: _plan,
          date: _date,
          name: _canRead ? _session?.user?.displayName : null,
          expert: _expert,
          authorized: _canRead,
          loading: _loading,
          loaded: _loaded,
          error: _error,
          records: _records,
          mealError: _mealError,
          onDate: _selectDate,
          onRetry: _reload,
          onRecordsRetry: _loadRecords,
          onInfo: _info,
          onReview: _review,
          onProfile: widget.onViewProfile,
        ),
      ),
    ),
  );
}
