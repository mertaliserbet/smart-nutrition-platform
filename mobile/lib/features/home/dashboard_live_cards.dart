import 'package:flutter/material.dart';
import '../nutrition/nutrition_plan_api.dart';
import 'dashboard_data.dart';
import 'dashboard_widgets.dart';
import '../personal_nutrition_targets/personal_nutrition_target_api.dart';
import '../personal_nutrition_targets/target_progress.dart';

class DashboardLiveCards {
  static List<Widget> _state<T>(AsyncSnapshot<T> snapshot, String subject) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return [
        LinearProgressIndicator(semanticsLabel: '$subject yükleniyor'),
        Text('$subject yükleniyor…'),
      ];
    }
    if (snapshot.hasError) {
      return [
        Semantics(liveRegion: true, child: Text(snapshot.error.toString())),
      ];
    }
    return [const Text('Verilerinizi görmek için oturumunuz doğrulanmalıdır.')];
  }

  static Widget energy(
    BuildContext context,
    AsyncSnapshot<DashboardMeals> meals,
    AsyncSnapshot<NutritionPlanResponse?> plan,
    VoidCallback retry,
    AsyncSnapshot<PersonalNutritionTargetResponse> targets,
    VoidCallback retryTargets,
    VoidCallback editTargets,
  ) => DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardSectionHeading(
          title: 'Günlük enerji',
          subtitle: 'Bugün kaydettiğiniz öğünler',
        ),
        const SizedBox(height: 12),
        if (meals.hasData) ...[
          Text(
            meals.data!.calories.label('kcal'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (meals.data!.calories.missing > 0)
            const Text(
              'Eksik kalori değerleri var; tam tüketim toplamı bilinmiyor.',
            ),
        ] else
          ..._state(meals, 'Öğünler'),
        const SizedBox(height: 8),
        NutritionTargetProgress(
          target: EffectiveNutritionTarget.resolve(
            'dailyCaloriesTargetKcal',
            targets,
            plan: plan,
          ),
          unit: 'kcal',
          consumed: meals.data?.calories.value,
          complete: meals.data?.calories.missing == 0,
        ),
        TextButton(
          onPressed: editTargets,
          child: const Text('Günlük hedeflerim'),
        ),
        if (targets.hasError)
          TextButton(
            onPressed: retryTargets,
            child: const Text('Hedefleri yenile'),
          ),
        if (meals.hasError)
          TextButton(onPressed: retry, child: const Text('Öğünleri yenile')),
      ],
    ),
  );
  static Widget macros(
    AsyncSnapshot<DashboardMeals> meals,
    AsyncSnapshot<PersonalNutritionTargetResponse> targets,
  ) => DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardSectionHeading(
          title: 'Makro dengesi',
          subtitle: 'Kaydedilen besin değerleri',
        ),
        const SizedBox(height: 12),
        if (meals.hasData) ...[
          Text('Protein: ${meals.data!.protein.label('g')}'),
          NutritionTargetProgress(
            target: EffectiveNutritionTarget.resolve(
              'dailyProteinTargetGrams',
              targets,
            ),
            unit: 'g',
            consumed: meals.data!.protein.value,
            complete: meals.data!.protein.missing == 0,
          ),
          Text('Karbonhidrat: ${meals.data!.carbs.label('g')}'),
          NutritionTargetProgress(
            target: EffectiveNutritionTarget.resolve(
              'dailyCarbsTargetGrams',
              targets,
            ),
            unit: 'g',
            consumed: meals.data!.carbs.value,
            complete: meals.data!.carbs.missing == 0,
          ),
          Text('Yağ: ${meals.data!.fat.label('g')}'),
          NutritionTargetProgress(
            target: EffectiveNutritionTarget.resolve(
              'dailyFatTargetGrams',
              targets,
            ),
            unit: 'g',
            consumed: meals.data!.fat.value,
            complete: meals.data!.fat.missing == 0,
          ),
          if ([
            meals.data!.protein,
            meals.data!.carbs,
            meals.data!.fat,
          ].any((item) => item.missing > 0))
            const Text('Eksik makro değerleri sıfır kabul edilmez.'),
        ] else
          ..._state(meals, 'Öğünler'),
        const SizedBox(height: 8),
      ],
    ),
  );
  static Widget program(
    AsyncSnapshot<NutritionPlanResponse?> snapshot,
    VoidCallback open,
    VoidCallback retry,
  ) => DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardSectionHeading(
          title: 'Beslenme programı',
          subtitle: 'Aktif programınız',
        ),
        const SizedBox(height: 12),
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) ...[
          if (snapshot.data case final plan?) ...[
            Text(plan.title),
            Text(
              plan.dietitianId == null
                  ? 'Kişisel programınız · Salt okunur'
                  : 'Diyetisyeniniz tarafından atanmış program · Salt okunur',
            ),
            Text('Sürüm ${plan.versionNumber}'),
            Text(
              plan.dailyWaterTargetMl == null
                  ? 'Su hedefi: Henüz hedef belirlenmedi'
                  : 'Programdaki su hedefi: ${dashboardNumber(plan.dailyWaterTargetMl!)} mL',
            ),
          ] else ...[
            const Text('Henüz aktif bir beslenme programınız bulunmuyor.'),
            const Text('Henüz hedef belirlenmedi'),
          ],
        ] else
          ..._state(snapshot, 'Program'),
        if (snapshot.hasError)
          TextButton(onPressed: retry, child: const Text('Programı yenile')),
        FilledButton.tonal(
          onPressed: open,
          child: const Text('Beslenmeye göz at', textAlign: TextAlign.center),
        ),
      ],
    ),
  );
  static Widget recent(
    AsyncSnapshot<DashboardMeals> meals,
    VoidCallback open,
  ) => DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardSectionHeading(
          title: 'Son öğünler',
          subtitle: 'Bugünkü kayıtlarınız',
        ),
        const SizedBox(height: 12),
        if (meals.hasData) ...[
          if (meals.data!.records.isEmpty)
            const Text('Henüz öğün kaydı yok. İlk öğününüzü ekleyebilirsiniz.'),
          for (final meal in meals.data!.records.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(meal.items.map((item) => item.displayName).join(', ')),
                  Text(
                    '${meal.consumedAt.toLocal().hour.toString().padLeft(2, '0')}:${meal.consumedAt.toLocal().minute.toString().padLeft(2, '0')}',
                  ),
                ],
              ),
            ),
        ] else
          ..._state(meals, 'Öğünler'),
        TextButton(onPressed: open, child: const Text('Öğün geçmişi')),
      ],
    ),
  );
}
