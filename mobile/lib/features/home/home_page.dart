import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../nutrition/manual_meal_log_page.dart';
import 'dashboard_demo_data.dart';
import 'dashboard_details.dart';
import 'dashboard_summary.dart';
import 'dashboard_widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.onViewNutrition,
    this.demoData = DashboardDemo.personal,
    super.key,
  });

  final VoidCallback onViewNutrition;
  final DashboardDemoData demoData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final energy = EnergySummaryCard(metric: demoData.calories);
    final macros = MacroSummaryCard(metrics: demoData.macros);
    final water = WaterSummaryCard(metric: demoData.water);
    final plan = NutritionPlanSummaryCard(
      data: demoData,
      onViewNutrition: onViewNutrition,
    );

    return SingleChildScrollView(
      primary: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingMedium),
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                      DashboardDemo.dateLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingLarge),
                    DashboardCard(
                      color: colors.secondaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Örnek veriler · Demo',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spacingSmall),
                          Text(
                            DashboardDemo.disclaimer,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                        ],
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
                                const SizedBox(height: AppTokens.spacingMedium),
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
                                const SizedBox(height: AppTokens.spacingMedium),
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
                    const _QuickActions(),
                    if (!wide) ...[
                      const SizedBox(height: AppTokens.spacingLarge),
                      plan,
                    ],
                    const SizedBox(height: AppTokens.spacingLarge),
                    RecentMealLogsCard(mealLogs: demoData.mealLogs),
                    const SizedBox(height: AppTokens.spacingMedium),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

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
          subtitle: 'Demo önizlemeleri · Kayıt oluşturulmaz',
        ),
        const SizedBox(height: AppTokens.spacingMedium),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final columns = largeText
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
                      onPressed: () {
                        if (action.label == 'Öğün ekle') {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => const ManualMealLogPage(),
                            ),
                          );
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
