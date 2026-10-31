import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

const authInputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMedium)),
);

class AuthPageLayout extends StatelessWidget {
  const AuthPageLayout({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
    this.footer,
    this.notice = 'Bu ekranda giriş veya e-posta gönderimi yapılmaz.',
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;
  final Widget? footer;
  final String notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart Nutrition',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppTokens.spacingLarge),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - AppTokens.spacingLarge * 2)
                    .clamp(0.0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTokens.contentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusMedium,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppTokens.spacingMedium,
                              ),
                              child: Icon(
                                icon,
                                size: AppTokens.brandIconSize,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      Text(
                        description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      Text(
                        notice,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingMedium),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusMedium,
                          ),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.spacingLarge),
                          child: child,
                        ),
                      ),
                      if (footer != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppTokens.spacingMedium,
                          ),
                          child: footer,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    required this.controller,
    required this.validator,
    this.label = 'Şifre',
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final String label;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      enabled: widget.enabled,
      obscureText: _obscure,
      keyboardType: TextInputType.visiblePassword,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        border: authInputBorder,
        errorMaxLines: 4,
        suffixIcon: IconButton(
          tooltip: '${_obscure ? 'Göster' : 'Gizle'}: ${widget.label}',
          onPressed: widget.enabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading || !enabled ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.all(AppTokens.spacingMedium),
      ),
      child: isLoading
          ? const Wrap(
              spacing: AppTokens.spacingMedium,
              runSpacing: AppTokens.spacingSmall,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: 'Yükleniyor',
                  ),
                ),
                Text('Yükleniyor'),
              ],
            )
          : Text(label, textAlign: TextAlign.center),
    );
  }
}

class AuthErrorNotice extends StatelessWidget {
  const AuthErrorNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spacingMedium),
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer),
          ),
        ),
      ),
    );
  }
}
