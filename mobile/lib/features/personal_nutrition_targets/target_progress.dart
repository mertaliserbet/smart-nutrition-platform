import 'package:flutter/material.dart';
import '../home/dashboard_data.dart';
import '../nutrition/nutrition_plan_api.dart';
import 'personal_nutrition_target_api.dart';

class EffectiveNutritionTarget {
  const EffectiveNutritionTarget({
    this.value,
    this.source,
    this.loading = false,
    this.failed = false,
  });
  final num? value;
  final String? source;
  final bool loading, failed;
  static EffectiveNutritionTarget resolve(
    String key,
    AsyncSnapshot<PersonalNutritionTargetResponse> personal, {
    AsyncSnapshot<NutritionPlanResponse?>? plan,
  }) {
    if (plan != null) {
      if (plan.hasError) return const EffectiveNutritionTarget(failed: true);
      if (plan.connectionState != ConnectionState.done) {
        return const EffectiveNutritionTarget(loading: true);
      }
      final assigned = plan.data?.dietitianId != null;
      final value = key == 'dailyCaloriesTargetKcal'
          ? plan.data?.dailyCaloriesTargetKcal
          : plan.data?.dailyWaterTargetMl;
      if (assigned && value != null) {
        return EffectiveNutritionTarget(
          value: value,
          source: 'Diyetisyen programı',
        );
      }
    }
    if (personal.hasError) return const EffectiveNutritionTarget(failed: true);
    if (!personal.hasData || personal.connectionState != ConnectionState.done) {
      return const EffectiveNutritionTarget(loading: true);
    }
    final value = personal.data!.values[key];
    return EffectiveNutritionTarget(
      value: value,
      source: value == null ? null : 'Kişisel hedef',
    );
  }
}

class NutritionTargetProgress extends StatelessWidget {
  const NutritionTargetProgress({
    required this.target,
    required this.unit,
    this.consumed,
    this.complete = true,
    super.key,
  });
  final EffectiveNutritionTarget target;
  final String unit;
  final num? consumed;
  final bool complete;
  @override
  Widget build(BuildContext context) {
    if (target.loading) return const Text('Hedef bilgisi yükleniyor…');
    if (target.failed) return const Text('Hedef bilgisi alınamadı.');
    final goal = target.value;
    if (goal == null) return const Text('Henüz hedef belirlenmedi');
    final ratio = consumed == null ? null : consumed! / goal;
    final percent = ratio == null ? null : ratio * 100;
    final label = percent?.isFinite == true
        ? percent!
              .toStringAsFixed(1)
              .replaceFirst(RegExp(r'\.0$'), '')
              .replaceAll('.', ',')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hedef: ${dashboardNumber(goal)} $unit · Kaynak: ${target.source}',
        ),
        if (!complete)
          const Text(
            'Eksik besin değerleri nedeniyle ilerleme hesaplanamıyor.',
          ),
        if (ratio != null && label != null && complete) ...[
          Text(
            '${dashboardNumber(consumed!)} / ${dashboardNumber(goal)} $unit · %$label',
          ),
          LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            semanticsLabel: '$unit hedef ilerlemesi; gerçekleşen yüzde $label',
          ),
        ],
      ],
    );
  }
}
