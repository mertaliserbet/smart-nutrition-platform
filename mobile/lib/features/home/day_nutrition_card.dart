import 'package:flutter/material.dart';
import '../nutrition/nutrition_plan_api.dart';
import '../onboarding/onboarding_theme.dart';
import '../personal_nutrition_targets/personal_nutrition_target_api.dart';
import '../personal_nutrition_targets/target_progress.dart';
import 'dashboard_data.dart';
import 'day_widgets.dart';

class DayProgress extends StatelessWidget {
  const DayProgress({
    required this.total,
    required this.target,
    required this.label,
    this.height = 7,
    super.key,
  });
  final NutrientTotal? total;
  final EffectiveNutritionTarget target;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final valid =
        total != null &&
        total!.missing == 0 &&
        target.value != null &&
        !target.loading &&
        !target.failed;
    final ratio = valid
        ? (total!.value / target.value!).clamp(0, 1).toDouble()
        : 0.0;
    return Semantics(
      label: label,
      value: valid
          ? '${dayNumber(total!.value)} / ${dayNumber(target.value!)}'
          : 'İlerleme hesaplanamıyor',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: OnboardingTheme.border),
              ),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF83B977), OnboardingTheme.lime],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DayEnergyCard extends StatelessWidget {
  const DayEnergyCard({
    required this.meals,
    required this.plan,
    required this.targets,
    required this.onRetryMeals,
    required this.onRetryTargets,
    required this.onTargets,
    super.key,
  });
  final AsyncSnapshot<DashboardMeals> meals;
  final AsyncSnapshot<NutritionPlanResponse?> plan;
  final AsyncSnapshot<PersonalNutritionTargetResponse> targets;
  final VoidCallback onRetryMeals, onRetryTargets, onTargets;

  String _amount(
    NutrientTotal total,
    EffectiveNutritionTarget target,
    String unit,
  ) {
    if (total.missing > 0) {
      return total.known == 0
          ? 'Belirtilmemiş'
          : '${dayNumber(total.value)} $unit · Bilinen toplam';
    }
    final consumed = dayNumber(total.value);
    if (target.value == null || target.loading || target.failed) {
      return '$consumed $unit';
    }
    return '$consumed / ${dayNumber(target.value!)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final energyTarget = EffectiveNutritionTarget.resolve(
      'dailyCaloriesTargetKcal',
      targets,
      plan: plan,
    );
    final macroTargets = [
      for (final key in [
        'dailyProteinTargetGrams',
        'dailyCarbsTargetGrams',
        'dailyFatTargetGrams',
      ])
        EffectiveNutritionTarget.resolve(key, targets),
    ];
    final data = meals.data;
    return DaySurface(
      label: 'Günlük hedeflerim',
      onTap: onTargets,
      key: const ValueKey('day-targets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Text(
                'Günlük enerji',
                style: OnboardingTheme.heading(18),
              );
              final amount = data == null
                  ? null
                  : Text(
                      _amount(data.calories, energyTarget, 'kcal'),
                      key: const ValueKey('day-calories'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    );
              if (amount == null) return heading;
              if (constraints.maxWidth < 310 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                  data!.calories.missing > 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 8), amount],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  heading,
                  const SizedBox(width: 8),
                  Flexible(child: amount),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (meals.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(semanticsLabel: 'Öğünler yükleniyor')
          else if (meals.hasError) ...[
            Text(meals.error.toString()),
            TextButton(
              onPressed: onRetryMeals,
              child: const Text('Öğünleri yenile'),
            ),
          ] else if (data == null)
            const Text('Verilerini görmek için oturumun doğrulanmalıdır.')
          else ...[
            DayProgress(
              total: data.calories,
              target: energyTarget,
              label: 'Günlük enerji ilerlemesi',
              height: 12,
            ),
            const SizedBox(height: 17),
            for (final (index, entry) in [
              (name: 'Protein', value: data.protein),
              (name: 'Karbonhidrat', value: data.carbs),
              (name: 'Yağ', value: data.fat),
            ].indexed) ...[
              _MacroRow(
                name: entry.name,
                amount: _amount(entry.value, macroTargets[index], 'g'),
                total: entry.value,
                target: macroTargets[index],
              ),
              if (index < 2) const SizedBox(height: 12),
            ],
            if ([
              data.calories,
              data.protein,
              data.carbs,
              data.fat,
            ].any((value) => value.missing > 0))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Eksik besin değerleri var; tam tüketim toplamı bilinmiyor. Eksik değerler sıfır kabul edilmez.',
                  style: TextStyle(fontSize: 13, color: OnboardingTheme.muted),
                ),
              ),
            if (data.records.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Bugün henüz öğün kaydın yok.',
                  style: TextStyle(fontSize: 13, color: OnboardingTheme.muted),
                ),
              ),
          ],
          if (energyTarget.loading ||
              macroTargets.any((value) => value.loading))
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Hedef bilgisi yükleniyor…',
                style: TextStyle(fontSize: 13, color: OnboardingTheme.muted),
              ),
            )
          else if (energyTarget.failed ||
              macroTargets.any((value) => value.failed)) ...[
            const Text('Hedef bilgisi alınamadı.'),
            if (targets.hasError)
              TextButton(
                onPressed: onRetryTargets,
                child: const Text('Hedefleri yenile'),
              ),
          ] else if (energyTarget.value == null &&
              macroTargets.every((value) => value.value == null))
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Henüz hedef belirlenmedi',
                style: TextStyle(fontSize: 13, color: OnboardingTheme.muted),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                energyTarget.source == 'Diyetisyen programı'
                    ? 'Enerji: Diyetisyen programı${macroTargets.any((target) => target.value != null) ? ' · Makrolar: Kişisel hedefler' : ' · Makro hedefi belirlenmedi'}'
                    : 'Kişisel hedefler',
                style: const TextStyle(
                  fontSize: 12,
                  color: OnboardingTheme.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.name,
    required this.amount,
    required this.total,
    required this.target,
  });
  final String name, amount;
  final NutrientTotal total;
  final EffectiveNutritionTarget target;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final progress = DayProgress(
        total: total,
        target: target,
        label: '$name ilerlemesi',
      );
      if (constraints.maxWidth < 270 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
          total.missing > 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 13,
                    color: OnboardingTheme.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            progress,
          ],
        );
      }
      return Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: progress),
          const SizedBox(width: 10),
          SizedBox(
            width: 87,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                color: OnboardingTheme.muted,
              ),
            ),
          ),
        ],
      );
    },
  );
}
