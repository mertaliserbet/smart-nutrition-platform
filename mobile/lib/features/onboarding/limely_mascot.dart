import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_theme.dart';

/// Animates the approved image itself, without redrawing the character.
class LimelyMascot extends StatefulWidget {
  const LimelyMascot({
    required this.size,
    this.pose = 'merhaba',
    this.animated = false,
    this.halo = false,
    super.key,
  });
  final double size;
  final String pose;
  final bool animated;
  final bool halo;

  @override
  State<LimelyMascot> createState() => _LimelyMascotState();
}

class _LimelyMascotState extends State<LimelyMascot>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3100),
  );
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion || !widget.animated) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_started) {
      _started = true;
      _motion.forward();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _replay() {
    if (!_reduceMotion && widget.animated) _motion.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final image = Image.asset(
      'assets/limely/maskotlar/limely-maskot-${widget.pose}.png',
      width: size,
      height: size,
      cacheWidth:
          (size * math.max(2, MediaQuery.devicePixelRatioOf(context)) * 1.15)
              .ceil(),
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final mascot = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.halo) ...[
            Image.asset(
              'assets/limely/dekorlar/maskot-halesi.png',
              width: size,
              height: size,
              excludeFromSemantics: true,
            ),
            Positioned(
              left: size * .025,
              top: size * .08,
              child: Image.asset(
                'assets/limely/dekorlar/iki-cekirdek.png',
                width: 27,
                height: 35,
                excludeFromSemantics: true,
              ),
            ),
          ],
          if (!widget.animated)
            image
          else
            AnimatedBuilder(
              animation: _motion,
              builder: (context, child) {
                final seconds = _motion.value * 3.1;
                final active = _motion.isAnimating && !_reduceMotion;
                final bob = active ? math.sin(seconds * math.pi / 1.5) : 0.0;
                final wave = active && seconds < 2.2
                    ? math.sin(seconds * 2 * math.pi / .55) * .105
                    : 0.0;
                final blink = active && seconds > 1.22 && seconds < 1.5
                    ? math.sin((seconds - 1.22) / .28 * math.pi)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(0, -5 * bob.abs()),
                  child: Transform.rotate(
                    angle: -.018 * bob,
                    child: Transform.scale(
                      scale: 1.1,
                      child: Stack(
                        children: [
                          ClipPath(
                            clipper: const _WelcomeArmClipper(inverse: true),
                            child: child!,
                          ),
                          if (wave.abs() > .0005)
                            const Positioned.fill(
                              child: CustomPaint(painter: _ShoulderPainter()),
                            ),
                          Transform.rotate(
                            angle: wave,
                            alignment: const Alignment(.39, .21),
                            child: ClipPath(
                              clipper: const _WelcomeArmClipper(),
                              child: child,
                            ),
                          ),
                          if (blink > .05)
                            Positioned.fill(
                              child: CustomPaint(painter: _WinkPainter(blink)),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: image,
            ),
        ],
      ),
    );
    if (!widget.animated) return ExcludeSemantics(child: mascot);
    return Semantics(
      button: true,
      label: 'Limely yeniden el sallasın',
      onTap: _replay,
      child: Tooltip(
        message: 'Karşılamayı yeniden oynat',
        child: InkResponse(
          onTap: _replay,
          excludeFromSemantics: true,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          radius: size / 2,
          child: mascot,
        ),
      ),
    );
  }
}

/// Normalized to the canonical 1024-square welcome master in the asset package.
class _WelcomeArmClipper extends CustomClipper<Path> {
  const _WelcomeArmClipper({this.inverse = false});
  final bool inverse;

  @override
  Path getClip(Size size) {
    if (inverse) {
      // Leave the shoulder underneath the rotating arm so no seam opens.
      final outerArm = Path()
        ..moveTo(size.width * .715, size.height * .55)
        ..lineTo(size.width * .745, size.height * .49)
        ..lineTo(size.width * .805, size.height * .452)
        ..lineTo(size.width * .875, size.height * .46)
        ..lineTo(size.width * .89, size.height * .535)
        ..lineTo(size.width * .79, size.height * .62)
        ..lineTo(size.width * .745, size.height * .625)
        ..close();
      return Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        outerArm,
      );
    }
    final arm = Path()
      ..moveTo(size.width * .689, size.height * .6)
      ..lineTo(size.width * .745, size.height * .49)
      ..lineTo(size.width * .805, size.height * .452)
      ..lineTo(size.width * .86, size.height * .46)
      ..lineTo(size.width * .875, size.height * .535)
      ..lineTo(size.width * .79, size.height * .615)
      ..lineTo(size.width * .724, size.height * .635)
      ..close();
    return arm;
  }

  @override
  bool shouldReclip(_WelcomeArmClipper oldClipper) =>
      oldClipper.inverse != inverse;
}

class _ShoulderPainter extends CustomPainter {
  const _ShoulderPainter();

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    Offset(size.width * .727, size.height * .535),
    size.width * .037,
    Paint()..color = const Color(0xFF88B975),
  );

  @override
  bool shouldRepaint(_ShoulderPainter oldDelegate) => false;
}

class _WinkPainter extends CustomPainter {
  const _WinkPainter(this.amount);
  final double amount;

  @override
  void paint(Canvas canvas, Size size) {
    final eye = Offset(size.width * .561, size.height * .5285);
    canvas.drawOval(
      Rect.fromCenter(
        center: eye,
        width: size.width * .046,
        height: size.height * .058,
      ),
      Paint()..color = const Color(0xFF88B975),
    );
    final halfWidth = size.width * .01;
    final lift = size.height * .008 * amount;
    canvas.drawPath(
      Path()
        ..moveTo(eye.dx - halfWidth, eye.dy + lift / 2)
        ..quadraticBezierTo(
          eye.dx,
          eye.dy - lift,
          eye.dx + halfWidth,
          eye.dy + lift / 2,
        ),
      Paint()
        ..color = OnboardingTheme.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .008
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WinkPainter oldDelegate) => oldDelegate.amount != amount;
}
