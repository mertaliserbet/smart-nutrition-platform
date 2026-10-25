import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'dashboard_demo_data.dart';
import 'dashboard_widgets.dart';

class EnergySummaryCard extends StatelessWidget {
  const EnergySummaryCard({required this.metric, super.key});

  final DashboardDemoMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onPrimary;

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Günlük enerji',
          style: theme.textTheme.titleMedium?.copyWith(color: foreground),
        ),
        const SizedBox(height: AppTokens.spacingLarge),
        Text(
          '${metric.value}',
          style: theme.textTheme.displaySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${metric.unit} · örnek tüketim',
          style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
        ),
        const SizedBox(height: AppTokens.spacingMedium),
        Text(
          'Örnek hedef: ${metric.target} ${metric.unit}',
          style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
        ),
      ],
    );

    final ring = SizedBox.square(
      dimension: 144,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: metric.progress,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            color: foreground,
            backgroundColor: foreground.withValues(alpha: 0.2),
            semanticsLabel:
                'Örnek kalori hedefi, ${metric.value} / ${metric.target} ${metric.unit}',
          ),
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spacingLarge),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '%${metric.percentage}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'örnek ilerleme',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return DashboardCard(
      color: colors.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide =
              constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3;
          if (sideBySide) {
            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: AppTokens.spacingLarge),
                ring,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summary,
              const SizedBox(height: AppTokens.spacingExtraLarge),
              Center(child: ring),
            ],
          );
        },
      ),
    );
  }
}

class MacroSummaryCard extends StatelessWidget {
  const MacroSummaryCard({required this.metrics, super.key});

  final List<DashboardDemoMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accents = [colors.primary, colors.secondary, colors.tertiary];

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeading(
            title: 'Makro dengesi',
            subtitle: 'Örnek tüketim / örnek hedef',
          ),
          for (final (index, metric) in metrics.indexed) ...[
            const SizedBox(height: AppTokens.spacingLarge),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppTokens.spacingSmall,
              runSpacing: AppTokens.spacingSmall,
              children: [
                Text(metric.label, style: theme.textTheme.titleSmall),
                Text(
                  '${metric.value} / ${metric.target} ${metric.unit}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spacingSmall),
            LinearProgressIndicator(
              value: metric.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
              color: accents[index % accents.length],
              backgroundColor: colors.surfaceContainerHighest,
              semanticsLabel:
                  'Örnek ${metric.label} hedefi, ${metric.value} / ${metric.target} ${metric.unit}',
            ),
          ],
        ],
      ),
    );
  }
}

class WaterSummaryCard extends StatelessWidget {
  const WaterSummaryCard({required this.metric, super.key});

  final DashboardDemoMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeading(
            title: 'Su tüketimi',
            subtitle: 'Günlük örnek görünüm',
          ),
          const SizedBox(height: AppTokens.spacingLarge),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTokens.spacingSmall,
            runSpacing: AppTokens.spacingSmall,
            children: [
              Icon(Icons.water_drop_outlined, color: colors.primary),
              Text(
                '${metric.value} ${metric.unit}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spacingMedium),
          LinearProgressIndicator(
            value: metric.progress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
            color: colors.primary,
            backgroundColor: colors.surfaceContainerHighest,
            semanticsLabel:
                'Örnek su hedefi, ${metric.value} / ${metric.target} ${metric.unit}',
          ),
          const SizedBox(height: AppTokens.spacingMedium),
          Text(
            'Örnek hedef: ${metric.target} ${metric.unit} · %${metric.percentage}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
