import 'package:flutter/material.dart';

import 'onboarding_theme.dart';

class OnboardingHint extends StatelessWidget {
  const OnboardingHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: OnboardingIcon('info', size: 18),
      ),
      const SizedBox(width: 7),
      Flexible(child: Text(text, style: OnboardingTheme.hint)),
    ],
  );
}

class OnboardingChoiceCard extends StatelessWidget {
  const OnboardingChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
    super.key,
  });
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    checked: selected,
    inMutuallyExclusiveGroup: true,
    button: true,
    onTap: onTap,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 22 : 24),
          boxShadow: selected ? null : OnboardingTheme.shadow,
        ),
        child: Material(
          color: selected ? OnboardingTheme.soft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 22 : 24),
            side: BorderSide(
              color: selected
                  ? OnboardingTheme.selectedBorder
                  : OnboardingTheme.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 7, vertical: 15)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
              child: compact
                  ? Column(
                      children: [
                        OnboardingIcon(icon, size: 29),
                        const SizedBox(height: 10),
                        Text(
                          label.replaceFirst(' ', '\n'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: OnboardingTheme.ink,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        OnboardingIcon(icon, size: 31),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: OnboardingTheme.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? OnboardingTheme.ink : null,
                            border: Border.all(
                              color: selected
                                  ? OnboardingTheme.ink
                                  : const Color(0xFF9AA791),
                              width: 1.8,
                            ),
                          ),
                          child: selected
                              ? Image.asset(
                                  'assets/limely/ikonlar/beyaz/check.png',
                                  width: 17,
                                  height: 17,
                                  excludeFromSemantics: true,
                                )
                              : null,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

class OnboardingNumberField extends StatelessWidget {
  const OnboardingNumberField({
    required this.name,
    required this.label,
    required this.icon,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.validator,
    this.unit,
    this.decimal = false,
    super.key,
  });
  final String name;
  final String label;
  final String icon;
  final String hint;
  final String? unit;
  final bool decimal;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: controller.text,
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    builder: (field) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: field.hasError
              ? OnboardingTheme.error
              : OnboardingTheme.border,
        ),
        boxShadow: OnboardingTheme.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OnboardingIcon(icon, size: 26),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  color: OnboardingTheme.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  label: unit == null ? label : '$label, $unit',
                  child: TextField(
                    key: ValueKey('onboarding-$name'),
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: decimal,
                    ),
                    textInputAction: decimal
                        ? TextInputAction.done
                        : TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: OnboardingTheme.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF8C9A84),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onChanged: field.didChange,
                    onSubmitted: (_) => onSubmitted(),
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 6),
                Text(
                  unit!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OnboardingTheme.ink,
                  ),
                ),
              ],
            ],
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 2),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  field.errorText!,
                  style: const TextStyle(
                    color: OnboardingTheme.error,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
