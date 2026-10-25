import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'dashboard_demo_data.dart';
import 'dashboard_widgets.dart';

class NutritionPlanSummaryCard extends StatelessWidget {
  const NutritionPlanSummaryCard({
    required this.data,
    required this.onViewNutrition,
    super.key,
  });

  final DashboardDemoData data;
  final VoidCallback onViewNutrition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dietitian = data.dietitianDisplayName;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeading(
            title: 'Beslenme programı',
            subtitle: 'Örnek program özeti',
          ),
          const SizedBox(height: AppTokens.spacingLarge),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTokens.spacingSmall,
            runSpacing: AppTokens.spacingSmall,
            children: [
              Icon(
                dietitian == null
                    ? Icons.menu_book_outlined
                    : Icons.lock_outline_rounded,
                color: colors.primary,
              ),
              Text(
                dietitian == null
                    ? 'Kişisel program · Örnek'
                    : 'Diyetisyen programı · Örnek',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spacingMedium),
          Text(
            data.nutritionPlanTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.spacingSmall),
          Text(
            data.nutritionPlanDescription,
            style: theme.textTheme.bodyMedium,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTokens.spacingMedium),
            child: Divider(height: 1),
          ),
          Text(
            dietitian ?? 'Diyetisyensiz kullanım',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppTokens.spacingSmall),
          Text(
            dietitian == null
                ? 'Bu örnekte diyetisyen bağlantısı yok. Kişisel hedef ve program takibiyle devam edebilirsiniz.'
                : 'Atanmış program ve hedefler salt okunurdur. Gerçek tüketim ayrı kaydedilir.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spacingLarge),
          FilledButton.tonalIcon(
            onPressed: onViewNutrition,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Beslenmeye göz at', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class RecentMealLogsCard extends StatelessWidget {
  const RecentMealLogsCard({required this.mealLogs, super.key});

  final List<DashboardDemoMealLogPreview> mealLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeading(
            title: 'Son öğünler',
            subtitle: 'Örnek kayıtlar · Kalori değerleri tahminidir',
          ),
          for (final (index, mealLog) in mealLogs.indexed) ...[
            const SizedBox(height: AppTokens.spacingLarge),
            if (index != 0) ...[
              const Divider(height: 1),
              const SizedBox(height: AppTokens.spacingLarge),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: const Icon(Icons.restaurant_menu_rounded),
                  ),
                ),
                const SizedBox(width: AppTokens.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mealLog.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      Wrap(
                        spacing: AppTokens.spacingMedium,
                        runSpacing: AppTokens.spacingSmall,
                        children: [
                          Text(
                            '${mealLog.mealLabel} · ${mealLog.timeLabel}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${mealLog.caloriesKcal} kcal',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
