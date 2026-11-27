import 'package:flutter/material.dart';
import '../home/day_widgets.dart' show dayNumber;
import '../onboarding/onboarding_theme.dart';
import 'meal_comparison_api.dart';
import 'meal_log_api.dart';
import 'nutrition_plan_api.dart';
import 'nutrition_plan_widgets.dart';

/// The same comparison response as the full page, presented in the approved sheet.
/// Missing nutrient values remain unknown; a meal record is not adherence.
class PlanReviewView extends StatelessWidget {
  const PlanReviewView({
    required this.data,
    required this.date,
    required this.loading,
    required this.authorized,
    required this.showLogs,
    required this.records,
    required this.recordsLoading,
    required this.onRetry,
    required this.onRecordsRetry,
    required this.onTab,
    this.error,
    this.empty,
    this.recordsError,
    super.key,
  });
  final NutritionPlanMealComparisonResponse? data;
  final DateTime date;
  final bool loading, authorized, showLogs, recordsLoading;
  final List<MealLog>? records;
  final String? error, empty, recordsError;
  final VoidCallback onRetry, onRecordsRetry;
  final ValueChanged<bool> onTab;
  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PlanSheetHeader('Planın ve kayıtların'),
            const SizedBox(height: 8),
            const Text(
              'Planındaki hedef ile kaydettiğin tüketimi\naynı gün için incele.',
              style: OnboardingTheme.hint,
            ),
            const SizedBox(height: 20),
            if (!authorized)
              const Text('Bilgileri görüntülemek için planını yeniden aç.')
            else ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: OnboardingTheme.soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _tab('Karşılaştırma', false),
                    _tab('Kaydettiğin öğünler', true),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                planDate(date, weekday: true),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 13),
              if (showLogs)
                ..._logs(context)
              else ...[
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Karşılaştırma yükleniyor',
                  )
                else if (error != null)
                  Semantics(liveRegion: true, child: Text(error!))
                else if (empty != null)
                  Text(empty!)
                else if (data != null)
                  ..._comparison(data!),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: loading ? null : onRetry,
                    child: Text(
                      error == null ? 'Karşılaştırmayı yenile' : 'Yeniden dene',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 17),
              const Text(
                'Kayıt olması, öğün önerisinin aynen tüketildiği anlamına gelmez. Planındaki porsiyonlar ile kaydındaki tüketim ayrı gösterilir.',
                style: OnboardingTheme.hint,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Planıma dön'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tab(String label, bool logs) => Expanded(
    child: Semantics(
      selected: showLogs == logs,
      button: true,
      child: TextButton(
        onPressed: () => onTab(logs),
        style: TextButton.styleFrom(
          backgroundColor: showLogs == logs ? Colors.white : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: OnboardingTheme.ink,
            fontWeight: showLogs == logs ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  String _nutrient(NutritionValueSummary value, int count, String unit) {
    if (count == 0) return 'Henüz kayıt yok';
    if (value.missingItemCount == count) return 'Belirtilmemiş';
    return '${dayNumber(value.knownTotal)} $unit${value.missingItemCount == 0 ? '' : ' bilinen toplam · ${value.missingItemCount} kalemde eksik'}';
  }

  List<Widget> _comparison(NutritionPlanMealComparisonResponse result) {
    final target = result.plan.dailyCaloriesTargetKcal;
    final cards = [
      _total(
        'Planındaki hedef',
        target == null ? 'Belirlenmedi' : '${dayNumber(target)} kcal',
        dark: true,
      ),
      _total(
        'Kaydettiğin enerji',
        _nutrient(
          result.actual.nutrients['caloriesKcal']!,
          result.actual.itemCount,
          'kcal',
        ),
      ),
    ];
    return [
      LayoutBuilder(
        builder: (context, c) => MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [cards[0], const SizedBox(height: 10), cards[1]],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 10),
                    Expanded(child: cards[1]),
                  ],
                ),
              ),
      ),
      const SizedBox(height: 12),
      if (result.actual.itemCount > 0)
        PlanSurface(
          child: Column(
            children: [
              for (final field in comparisonNutrients.entries.where(
                (e) => e.key != 'caloriesKcal',
              ))
                _line(
                  field.value.$1,
                  _nutrient(
                    result.actual.nutrients[field.key]!,
                    result.actual.itemCount,
                    field.value.$2,
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      PlanSurface(
        child: Column(
          children: [
            for (final meal in result.meals)
              _line(
                nutritionMealLabels[meal.mealType]!,
                meal.actual.mealLogCount == 0
                    ? 'Henüz kayıt yok'
                    : '${meal.actual.mealLogCount} öğün kaydı',
              ),
          ],
        ),
      ),
      if (result.actual.estimatedItemCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '${result.actual.estimatedItemCount} kalem tahmini besin değeri içeriyor.',
            style: OnboardingTheme.hint,
          ),
        ),
      const SizedBox(height: 12),
      Text(
        '${result.plan.title} · Sürüm ${result.plan.versionNumber}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      const Text(
        'Seçtiğin gün, planının güncel sürümüyle karşılaştırılır. Geçmişte aynı sürümün aktif olduğu anlamına gelmez.',
        style: OnboardingTheme.hint,
      ),
    ];
  }

  Widget _total(String title, String value, {bool dark = false}) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: dark ? OnboardingTheme.ink : Colors.white,
      border: Border.all(
        color: dark ? OnboardingTheme.ink : OnboardingTheme.border,
      ),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: dark ? const Color(0xFFD2DECA) : OnboardingTheme.muted,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: value.length > 18 ? 14 : 22,
            fontWeight: FontWeight.w700,
            color: dark ? OnboardingTheme.background : OnboardingTheme.ink,
          ),
        ),
      ],
    ),
  );
  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: OnboardingTheme.muted),
          ),
        ),
      ],
    ),
  );
  List<Widget> _logs(BuildContext context) => [
    if (recordsLoading)
      const LinearProgressIndicator(semanticsLabel: 'Öğün kayıtları yükleniyor')
    else if (recordsError != null)
      Semantics(liveRegion: true, child: Text(recordsError!))
    else if (records?.isEmpty == true)
      const PlanSurface(child: Text('Bu gün için henüz öğün kaydın yok.'))
    else
      for (final meal in records ?? <MealLog>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PlanSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mealTypeLabels[meal.mealType]!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      TimeOfDay.fromDateTime(
                        meal.consumedAt.toLocal(),
                      ).format(context),
                      style: const TextStyle(
                        fontSize: 12,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                for (final item in meal.items)
                  _line(
                    item.displayName,
                    '${item.quantityGrams == null ? '' : '${dayNumber(item.quantityGrams!)} g · '}${item.caloriesKcal == null ? 'Enerji belirtilmemiş' : '${dayNumber(item.caloriesKcal!)} kcal'}${item.isEstimated ? ' · Tahmini' : ''}',
                  ),
                if (meal.note != null)
                  Text(meal.note!, style: OnboardingTheme.hint),
              ],
            ),
          ),
        ),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: recordsLoading ? null : onRecordsRetry,
        child: Text(
          recordsError == null ? 'Kayıtları yenile' : 'Kayıtları tekrar yükle',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ),
  ];
}
