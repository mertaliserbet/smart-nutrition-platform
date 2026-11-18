import 'package:flutter/material.dart';
import '../nutrition/nutrition_plan_api.dart';
import 'dashboard_data.dart';
import 'dashboard_widgets.dart';

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
        if (plan.connectionState == ConnectionState.done && !plan.hasError)
          Text(
            plan.data?.dailyCaloriesTargetKcal == null
                ? 'Henüz hedef belirlenmedi'
                : 'Program hedefi: ${dashboardNumber(plan.data!.dailyCaloriesTargetKcal!)} kcal',
          )
        else if (plan.connectionState == ConnectionState.waiting)
          const Text('Hedef bilgisi yükleniyor…')
        else if (plan.hasError)
          const Text('Hedef bilgisi alınamadı.'),
        if (meals.hasError)
          TextButton(
            onPressed: retry,
            child: const Text('Öğünleri yenile'),
          ),
      ],
    ),
  );
  static Widget macros(AsyncSnapshot<DashboardMeals> meals) => DashboardCard(
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
          Text('Karbonhidrat: ${meals.data!.carbs.label('g')}'),
          Text('Yağ: ${meals.data!.fat.label('g')}'),
          if ([
            meals.data!.protein,
            meals.data!.carbs,
            meals.data!.fat,
          ].any((item) => item.missing > 0))
            const Text('Eksik makro değerleri sıfır kabul edilmez.'),
        ] else
          ..._state(meals, 'Öğünler'),
        const SizedBox(height: 8),
        const Text('Makro hedefleri: Henüz hedef belirlenmedi'),
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
          TextButton(
            onPressed: retry,
            child: const Text('Programı yenile'),
          ),
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
        TextButton(
          onPressed: open,
          child: const Text('Öğün geçmişi'),
        ),
      ],
    ),
  );
}
