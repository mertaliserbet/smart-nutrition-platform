import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppTokens.spacingLarge),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            primary: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTokens.contentMaxWidth,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(
                        AppTokens.radiusMedium,
                      ),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.spacingLarge),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusMedium,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  AppTokens.spacingLarge,
                                ),
                                child: Icon(
                                  icon,
                                  size: AppTokens.brandIconSize,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTokens.spacingExtraLarge),
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spacingSmall),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (action != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppTokens.spacingLarge,
                              ),
                              child: action,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
