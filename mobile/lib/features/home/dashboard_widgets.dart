import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({required this.child, this.color, super.key});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        border: Border.all(color: color ?? colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingLarge),
        child: child,
      ),
    );
  }
}

class DashboardSectionHeading extends StatelessWidget {
  const DashboardSectionHeading({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spacingSmall),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
