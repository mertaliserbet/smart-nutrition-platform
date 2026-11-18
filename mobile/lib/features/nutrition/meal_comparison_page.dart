import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import '../auth/login_page.dart';
import '../water/water_log_api.dart';
import 'meal_comparison_api.dart';
import 'nutrition_plan_api.dart';

class MealComparisonPage extends StatefulWidget {
  const MealComparisonPage({
    this.planApi,
    this.api,
    this.initialDate,
    super.key,
  });
  final NutritionPlanApi? planApi;
  final MealComparisonApi? api;
  final DateTime? initialDate;
  @override
  State<MealComparisonPage> createState() => _MealComparisonPageState();
}

class _MealComparisonPageState extends State<MealComparisonPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  NutritionPlanApi? _plans;
  MealComparisonApi? _api;
  String? _owner, _error, _empty;
  NutritionPlanMealComparisonResponse? _data;
  late DateTime _date;
  bool _loading = false, _loaded = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  int _revision = 0;
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    ++_revision;
    _data = null;
    _error = null;
    _empty = null;
    _loading = false;
    _loaded = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _plans = session == null
          ? null
          : identical(widget.planApi?.session, session)
          ? widget.planApi
          : NutritionPlanApi(session);
      _api = session == null
          ? null
          : identical(widget.api?.session, session)
          ? widget.api
          : MealComparisonApi(session);
    }
    if (!_authorized) {
      _clear();
    } else if (!_loaded && !_loading) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _clear();
    });
    if (_authorized) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!_authorized || _plans == null || _api == null) {
      return;
    }
    final day = WaterDayRange.forDate(_date), revision = ++_revision;
    setState(() {
      _data = null;
      _error = null;
      _empty = null;
      _loading = true;
      _loaded = false;
    });
    bool current() => mounted && _authorized && revision == _revision;
    try {
      final plan = await _plans!.active();
      if (!current()) {
        return;
      }
      if (plan == null || plan.dietitianId == null) {
        setState(
          () => _empty = 'Henüz aktif atanmış bir beslenme programınız yok.',
        );
      } else {
        final date = day.from.toIso8601String().substring(0, 10);
        if (date.compareTo(plan.startDate) < 0 ||
            (plan.endDate != null && date.compareTo(plan.endDate!) > 0)) {
          setState(
            () => _empty =
                'Seçilen gün aktif programın tarih aralığı dışında. Başka bir gün seçin.',
          );
        } else {
          final result = await _api!.get(plan, day);
          if (!current()) {
            return;
          }
          setState(() => _data = result);
        }
      }
    } catch (error) {
      if (current()) {
        setState(
          () => _error = switch (error) {
            MealComparisonApiException e => e.message,
            NutritionPlanApiException e => e.message,
            _ => 'Karşılaştırma yüklenemedi. Lütfen yeniden deneyin.',
          },
        );
      }
    } finally {
      if (current()) {
        setState(() {
          _loading = false;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _chooseDate() async {
    final owner = _owner, revision = _revision;
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 30),
    );
    if (!mounted ||
        !_authorized ||
        owner != _owner ||
        revision != _revision ||
        selected == null) {
      return;
    }
    setState(() => _date = selected);
    await _load();
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _number(num value) => value.toString().replaceAll('.', ',');
  String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  String _offset(DateTime date) => date.isUtc
      ? 'UTC+00:00'
      : 'UTC${waterOffsetIso(date).substring(waterOffsetIso(date).length - 6)}';
  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  List<Widget> _actual(MealLogNutritionSummary actual) => [
    if (actual.itemCount == 0)
      const Text('Öğün kaydı yok')
    else ...[
      Text('${actual.mealLogCount} öğün · ${actual.itemCount} besin kalemi'),
      for (final field in comparisonNutrients.entries)
        Text(
          '${field.value.$1}: ${_nutrient(actual.nutrients[field.key]!, actual.itemCount, field.value.$2)}',
        ),
      if (actual.estimatedItemCount > 0)
        Text(
          '${actual.estimatedItemCount} kalem tahmini besin değeri içeriyor.',
        ),
    ],
  ];
  String _nutrient(NutritionValueSummary value, int count, String unit) {
    if (value.missingItemCount == count) {
      return 'Belirtilmemiş (${value.missingItemCount} kalemde eksik)';
    }
    final known = '${_number(value.knownTotal)} $unit';
    return value.missingItemCount == 0
        ? known
        : '$known bilinen toplam · ${value.missingItemCount} kalemde eksik';
  }

  List<Widget> _content(NutritionPlanMealComparisonResponse data) {
    final theme = Theme.of(context);
    return [
      _card([
        Text(data.plan.title, style: theme.textTheme.titleLarge),
        Text('Aktif atanmış program · Sürüm ${data.plan.versionNumber}'),
        Text(
          'Sürüm kayıt zamanı: ${_dateLabel(data.versionCreatedAt.toLocal())} ${TimeOfDay.fromDateTime(data.versionCreatedAt.toLocal()).format(context)}',
        ),
        const Text(
          'Seçilen gün, bu içerik sürümüyle karşılaştırılır. Geçmişte o gün aynı sürümün aktif olduğu anlamına gelmez.',
        ),
        Text(
          'Yerel gün: 00:00 → ertesi gün 00:00 · ${_offset(data.day.from)} → ${_offset(data.day.to)}. Başlangıç dahil, bitiş hariç.',
        ),
        const SizedBox(height: 12),
        Text('Günlük gerçek tüketim', style: theme.textTheme.titleMedium),
        ..._actual(data.actual),
        Text(
          data.plan.dailyCaloriesTargetKcal == null
              ? 'Programda kalori hedefi belirlenmedi.'
              : 'Program hedefi: ${_number(data.plan.dailyCaloriesTargetKcal!)} kcal',
        ),
        Text(
          data.caloriesDifferenceKcal == null
              ? 'Kalori farkı hesaplanamıyor: kayıt, kalori bilgisi veya program hedefi eksik.'
              : 'Kaydedilen kalori − program hedefi: ${_number(data.caloriesDifferenceKcal!)} kcal',
        ),
        const Text(
          'Program öğünlerinde sayısal makro hedefi tanımlı değil. Kalori farkı, öğünlerin programa uyduğu anlamına gelmez.',
        ),
      ]),
      for (final meal in data.meals)
        _card([
          Text(
            nutritionMealLabels[meal.mealType]!,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Planlanan', style: theme.textTheme.titleMedium),
                    if (meal.plannedItems.isEmpty)
                      const Text('Bu öğün için öneri yok.'),
                    for (final item in meal.plannedItems)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.description),
                            Text(
                              'Miktar: ${item.recommendedQuantity ?? 'Belirtilmemiş'}',
                            ),
                            if (item.alternativeGroupId != null)
                              Text(
                                'Alternatif ${meal.plannedItems.map((i) => i.alternativeGroupId).whereType<String>().toSet().toList().indexOf(item.alternativeGroupId!) + 1}',
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gerçekleşen', style: theme.textTheme.titleMedium),
                    ..._actual(meal.actual),
                  ],
                ),
              ),
            ],
          ),
          if (meal.plannedItems.any((item) => item.alternativeGroupId != null))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Aynı alternatif grubundaki öneriler birbirinin yerine geçer; birlikte tüketilmeleri gerekmez.',
              ),
            ),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_session?.isAuthenticated != true) {
      return const LoginPage();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Program ve tüketim')),
      body: RefreshIndicator(
        onRefresh: _load,
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
                    OutlinedButton.icon(
                      onPressed: _authorized ? _chooseDate : null,
                      icon: const Icon(Icons.calendar_today),
                      label: Text('Gün seç: ${_dateLabel(_date)}'),
                    ),
                    if (_loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Karşılaştırma yükleniyor',
                      ),
                    if (_authorized && _error != null)
                      _card([
                        Semantics(liveRegion: true, child: Text(_error!)),
                      ]),
                    if (_authorized && _empty != null) _card([Text(_empty!)]),
                    if (_authorized && _data != null) ..._content(_data!),
                    TextButton.icon(
                      onPressed: _authorized && !_loading ? _load : null,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _error == null
                            ? 'Karşılaştırmayı yenile'
                            : 'Yeniden dene',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
