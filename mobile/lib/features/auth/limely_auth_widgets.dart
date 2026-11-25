import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../onboarding/onboarding_theme.dart';

/// Shared presentation for the approved login, summary and account screens only.
class LimelyAuthLayout extends StatefulWidget {
  const LimelyAuthLayout({
    required this.children,
    required this.onBack,
    this.backKey,
    this.progress = 0,
    super.key,
  });

  final List<Widget> children;
  final VoidCallback? onBack;
  final Key? backKey;
  final int progress;

  @override
  State<LimelyAuthLayout> createState() => _LimelyAuthLayoutState();
}

class _LimelyAuthLayoutState extends State<LimelyAuthLayout> {
  final _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: OnboardingTheme.data.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: OnboardingTheme.data.filledButtonTheme.style!.copyWith(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Figtree',
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: OnboardingTheme.ink,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: OnboardingTheme.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 48 || constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }
              return SingleChildScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Center(
                  child: SizedBox(
                    width: math.min(440, constraints.maxWidth - 48),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 28),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 64,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Semantics(
                                    label: 'Limely',
                                    image: true,
                                    child: Image.asset(
                                      'assets/limely/logolar/limely-yazili-logo-renkli.png',
                                      width: 158,
                                      cacheWidth: 632,
                                      filterQuality: FilterQuality.high,
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: IconButton(
                                      key: widget.backKey,
                                      tooltip: 'Önceki ekrana dön',
                                      onPressed: widget.onBack,
                                      icon: const OnboardingIcon('arrow-left'),
                                      padding: EdgeInsets.zero,
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.progress > 0)
                              Semantics(
                                label: 'Tanışma adımı ${widget.progress} / 4',
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 20,
                                    bottom: 28,
                                  ),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < 4; i++) ...[
                                        if (i > 0) const SizedBox(width: 6),
                                        Expanded(
                                          child: Container(
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: i < widget.progress
                                                  ? OnboardingTheme.lime
                                                  : OnboardingTheme.soft,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ...widget.children,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class LimelyAuthField extends StatefulWidget {
  const LimelyAuthField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    required this.icon,
    this.password = false,
    this.newPassword = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onFieldSubmitted,
    this.autofillHints,
    super.key,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final Widget icon;
  final bool password;
  final bool newPassword;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<LimelyAuthField> createState() => _LimelyAuthFieldState();
}

class _LimelyAuthFieldState extends State<LimelyAuthField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDFE7DA)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: OnboardingTheme.ink,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: widget.label,
          child: TextFormField(
            controller: widget.controller,
            validator: widget.validator,
            enabled: widget.enabled,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            obscureText: widget.password && _obscure,
            keyboardType: widget.password
                ? TextInputType.visiblePassword
                : widget.keyboardType,
            // Let the active keyboard handle its language, casing and composing
            // characters instead of forcing a name layout or word capitalization.
            textCapitalization: TextCapitalization.none,
            textInputAction: widget.textInputAction,
            autofillHints: widget.password
                ? [
                    widget.newPassword
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ]
                : widget.autofillHints,
            autocorrect: false,
            enableSuggestions: !widget.password,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onFieldSubmitted,
            style: const TextStyle(
              fontSize: 16,
              height: 1.3,
              color: OnboardingTheme.ink,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: OnboardingTheme.muted),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 17,
              ),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(
                  color: OnboardingTheme.ink,
                  width: 1.5,
                ),
              ),
              errorMaxLines: 4,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 54,
                minHeight: 54,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: widget.icon,
                ),
              ),
              suffixIcon: widget.password
                  ? IconButton(
                      tooltip: '${_obscure ? 'Göster' : 'Gizle'}: Şifre',
                      onPressed: widget.enabled
                          ? () => setState(() => _obscure = !_obscure)
                          : null,
                      icon: LimelyLineIcon(
                        _obscure ? LimelySymbol.eye : LimelySymbol.eyeOff,
                        size: 22,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

enum LimelySymbol { mail, lock, eye, eyeOff, external }

/// Rounded 1.8 px paths matching the icons in the approved SVG concept.
class LimelyLineIcon extends StatelessWidget {
  const LimelyLineIcon(this.symbol, {this.size = 22, super.key});
  final LimelySymbol symbol;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LinePainter(symbol)),
    ),
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.symbol);
  final LimelySymbol symbol;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = OnboardingTheme.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (symbol) {
      case LimelySymbol.mail:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 5, 18, 14),
            const Radius.circular(3),
          ),
          paint,
        );
        path.moveTo(4, 7);
        path.lineTo(12, 13);
        path.lineTo(20, 7);
      case LimelySymbol.lock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 10, 14, 11),
            const Radius.circular(3),
          ),
          paint,
        );
        path.moveTo(8, 10);
        path.lineTo(8, 7);
        path.cubicTo(8, 1.67, 16, 1.67, 16, 7);
        path.lineTo(16, 10);
        path.moveTo(12, 14);
        path.lineTo(12, 17);
      case LimelySymbol.eye || LimelySymbol.eyeOff:
        path.moveTo(2, 12);
        path.cubicTo(7, 4, 17, 4, 22, 12);
        path.cubicTo(17, 20, 7, 20, 2, 12);
        canvas.drawCircle(const Offset(12, 12), 2.5, paint);
        if (symbol == LimelySymbol.eyeOff) {
          path.moveTo(3, 3);
          path.lineTo(21, 21);
        }
      case LimelySymbol.external:
        path.moveTo(14, 4);
        path.lineTo(20, 4);
        path.lineTo(20, 10);
        path.moveTo(20, 4);
        path.lineTo(11, 13);
        path.moveTo(10, 5);
        path.lineTo(6, 5);
        path.quadraticBezierTo(4, 5, 4, 7);
        path.lineTo(4, 18);
        path.quadraticBezierTo(4, 20, 6, 20);
        path.lineTo(17, 20);
        path.quadraticBezierTo(19, 20, 19, 18);
        path.lineTo(19, 14);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => symbol != oldDelegate.symbol;
}
