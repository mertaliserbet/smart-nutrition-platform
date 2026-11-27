import 'package:flutter/material.dart';
import '../nutrition/nutrition_plan_api.dart';
import '../onboarding/onboarding_theme.dart';
import 'dashboard_data.dart';
import 'day_widgets.dart';

/// Groups recommendations without turning alternatives into extra required meals.
List<List<NutritionPlanItem>> dayPlanMeals(
  NutritionPlanResponse? plan,
  DateTime day,
) {
  if (plan == null) return [];
  final date =
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  if (date.compareTo(plan.startDate) < 0 ||
      (plan.endDate != null && date.compareTo(plan.endDate!) > 0)) {
    return [];
  }
  final items =
      plan.items
          .where(
            (item) => item.dayOfWeek == null || item.dayOfWeek == day.weekday,
          )
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final groups = <String, List<NutritionPlanItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.mealType, () => []).add(item);
  }
  return groups.values.toList();
}

String dayMealDescription(List<NutritionPlanItem> items) {
  final groups = <String, List<String>>{};
  for (final item in items) {
    final text =
        '${item.description}${item.recommendedQuantity == null ? '' : ' · ${item.recommendedQuantity}'}';
    groups.putIfAbsent(item.alternativeGroupId ?? item.id, () => []).add(text);
  }
  return groups.values.map((values) => values.join(' veya ')).join(' · ');
}

class DayPlanCard extends StatelessWidget {
  const DayPlanCard({
    required this.plan,
    required this.meals,
    required this.day,
    required this.onOpen,
    required this.onRetry,
    super.key,
  });
  final AsyncSnapshot<NutritionPlanResponse?> plan;
  final AsyncSnapshot<DashboardMeals> meals;
  final DateTime day;
  final VoidCallback onOpen, onRetry;

  DateTime? _recordedAt(String mealType) {
    final records = meals.data?.records
        .where((row) => row.mealType == mealType)
        .toList();
    if (records == null || records.isEmpty) return null;
    records.sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
    return records.first.consumedAt.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final groups = dayPlanMeals(plan.data, day);
    return DaySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bugünkü planım',
                  style: OnboardingTheme.heading(20),
                ),
              ),
              IconButton(
                onPressed: onOpen,
                tooltip: 'Planımı aç',
                icon: const OnboardingIcon('chevron-right', size: 22),
              ),
            ],
          ),
          if (plan.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(semanticsLabel: 'Program yükleniyor')
          else if (plan.hasError) ...[
            Text(plan.error.toString()),
            TextButton(
              onPressed: onRetry,
              child: const Text('Programı yenile'),
            ),
          ] else if (plan.connectionState != ConnectionState.done)
            const Text('Programını görmek için oturumun doğrulanmalıdır.')
          else if (plan.data == null)
            const Text('Henüz aktif bir beslenme programın bulunmuyor.')
          else ...[
            Text(
              plan.data!.title,
              style: const TextStyle(
                fontSize: 14,
                color: OnboardingTheme.muted,
              ),
            ),
            Text(
              plan.data!.dietitianId == null
                  ? 'Kişisel programın · Salt okunur'
                  : 'Diyetisyeninin atadığı program · Salt okunur',
              style: const TextStyle(
                fontSize: 12,
                color: OnboardingTheme.muted,
              ),
            ),
            const SizedBox(height: 16),
            if (groups.isEmpty)
              const Text('Bugün için planlanmış öğün bulunmuyor.'),
            for (final (index, group) in groups.indexed)
              _PlanRow(
                items: group,
                recordedAt: _recordedAt(group.first.mealType),
                last: index == groups.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.items,
    required this.recordedAt,
    required this.last,
  });
  final List<NutritionPlanItem> items;
  final DateTime? recordedAt;
  final bool last;
  bool get recorded => recordedAt != null;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recorded ? OnboardingTheme.lime : null,
                  border: Border.all(color: const Color(0xFFB2D66A), width: 2),
                ),
                child: recorded
                    ? const Center(child: OnboardingIcon('check', size: 13))
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFC9DDAD),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) ...[
          SizedBox(
            width: 48,
            child: Tooltip(
              message: recorded
                  ? 'Kaydedilen öğün saati; planlanan saat değildir'
                  : 'Planlanan saat belirtilmedi',
              child: Text(
                recorded
                    ? '${recordedAt!.hour.toString().padLeft(2, '0')}:${recordedAt!.minute.toString().padLeft(2, '0')}'
                    : '—',
                style: const TextStyle(
                  fontSize: 14,
                  color: OnboardingTheme.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      nutritionMealLabels[items.first.mealType] ??
                          items.first.mealType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (recorded)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: OnboardingTheme.soft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Kayıt var',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (recorded && MediaQuery.textScalerOf(context).scale(1) > 1.3)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Kayıt: ${recordedAt!.hour.toString().padLeft(2, '0')}:${recordedAt!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  dayMealDescription(items),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: OnboardingTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class DayPlannedMeal extends StatelessWidget {
  const DayPlannedMeal({required this.items, required this.onSave, super.key});
  final List<NutritionPlanItem> items;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: ColoredBox(
      color: OnboardingTheme.ink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return Stack(
            children: [
              if (!largeText)
                Positioned(
                  right: 0,
                  top: 0,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/limely/gorseller/limely-ogun-tabagi.png',
                      width: constraints.maxWidth * .59,
                      height: 190,
                      fit: BoxFit.cover,
                      alignment: Alignment.topRight,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'SIRADAKİ ÖĞÜN',
                      style: TextStyle(
                        color: OnboardingTheme.lime,
                        fontSize: 13,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      items.first.mealType == 'lunch'
                          ? 'Öğle vakti'
                          : nutritionMealLabels[items.first.mealType] ??
                                items.first.mealType,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w700,
                        color: OnboardingTheme.background,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Saat belirtilmedi',
                      style: TextStyle(
                        fontSize: 13,
                        color: OnboardingTheme.soft,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: largeText ? null : constraints.maxWidth * .52,
                        child: Text(
                          dayMealDescription(items),
                          maxLines: largeText ? null : 4,
                          overflow: largeText ? null : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: OnboardingTheme.background,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!largeText)
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Temsili görsel',
                          style: TextStyle(
                            fontSize: 11,
                            color: OnboardingTheme.soft,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OnboardingIcon('plus', size: 27),
                          SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              'Öğünümü kaydet',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
