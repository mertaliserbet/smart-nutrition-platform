import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/limely_auth_widgets.dart';
import '../auth/register_page.dart';

import 'limely_mascot.dart';
import 'onboarding_theme.dart';
import 'onboarding_controls.dart';

enum _Step { welcome, goal, details, summary, account }

enum _Goal {
  lose('Kilo vermek', 'body-scale'),
  gain('Kilo almak', 'dumbbell'),
  maintain('Kilomu korumak', 'shield-check'),
  balanced('Daha dengeli beslenmek', 'salad');

  const _Goal(this.label, this.icon);
  final String label;
  final String icon;
}

enum _Activity {
  sitting('Çoğunlukla oturarak', 'armchair'),
  moderate('Biraz hareketli', 'walk'),
  active('Çok hareketli', 'run');

  const _Activity(this.label, this.icon);
  final String label;
  final String icon;
}

/// A local introduction draft. These answers do not create health records.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.onLogin, super.key});
  final VoidCallback onLogin;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _ageFocus = FocusNode();
  final _heightFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _scroll = ScrollController();
  late final _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  _Step _step = _Step.welcome;
  _Goal _goal = _Goal.balanced;
  _Activity _activity = _Activity.moderate;

  @override
  void dispose() {
    for (final controller in [_age, _height, _weight]) {
      controller.dispose();
    }
    for (final focus in [_ageFocus, _heightFocus, _weightFocus]) {
      focus.dispose();
    }
    _scroll.dispose();
    _transition.dispose();
    super.dispose();
  }

  void _go(_Step step) {
    FocusScope.of(context).unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _step = step);
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
  }

  void _back() => _go(_Step.values[_step.index - 1]);

  void _review() {
    if (_form.currentState!.validate()) {
      _go(_Step.summary);
    } else if (_validateInteger(_age.text, 18, 120, 'Yaş') != null) {
      _ageFocus.requestFocus();
    } else if (_validateInteger(_height.text, 100, 250, 'Boy') != null) {
      _heightFocus.requestFocus();
    } else {
      _weightFocus.requestFocus();
    }
  }

  // Input limits reproduce the supplied HTML, not a medical recommendation.
  static String? _validateInteger(
    String? value,
    int minimum,
    int maximum,
    String label,
  ) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label bilgisini gir.';
    final number = RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
    if (number == null || number < minimum || number > maximum) {
      return '$minimum–$maximum arasında bir tam sayı gir.';
    }
    return null;
  }

  static String? _validateWeight(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Kilo bilgisini gir.';
    final number = RegExp(r'^\d+(?:[.,]\d)?$').hasMatch(text)
        ? double.tryParse(text.replaceAll(',', '.'))
        : null;
    if (number == null || !number.isFinite || number < 25 || number > 400) {
      return '25–400 kg arasında, en fazla bir ondalıklı değer gir.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _Step.account) {
      return RegisterPage(onBack: _back, onLogin: widget.onLogin);
    }
    if (_step == _Step.summary) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: LimelyAuthLayout(
          onBack: _back,
          backKey: const ValueKey('onboarding-back'),
          progress: 3,
          children: _summary(),
        ),
      );
    }
    return _introduction(context);
  }

  Widget _introduction(BuildContext context) => Theme(
    data: OnboardingTheme.data,
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: OnboardingTheme.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: _step == _Step.welcome,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _step != _Step.welcome) _back();
        },
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Android can deliver a zero-sized viewport before its first metrics.
                if (constraints.maxWidth <= 40 || constraints.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                final width = math.min(440.0, constraints.maxWidth - 40);
                final heroSize = math.min(290.0, width * .81);
                return SingleChildScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(0, constraints.maxHeight - 36),
                        ),
                        child: IntrinsicHeight(
                          child: FadeTransition(
                            opacity: _transition,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _header(),
                                if (_step != _Step.welcome) _progress(),
                                ...switch (_step) {
                                  _Step.welcome => _welcome(heroSize),
                                  _Step.goal => _goals(),
                                  _Step.details => _details(),
                                  _Step.summary || _Step.account => const [],
                                },
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
          ),
        ),
      ),
    ),
  );

  Widget _header() => SizedBox(
    height: _step == _Step.welcome ? 64 : 52,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Semantics(
          label: 'Limely',
          image: true,
          child: Image.asset(
            'assets/limely/logolar/limely-yazili-logo-renkli.png',
            width: _step == _Step.welcome ? 190 : 152,
            cacheWidth: 600,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
        if (_step != _Step.welcome)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: const ValueKey('onboarding-back'),
              onPressed: _back,
              tooltip: 'Önceki ekrana dön',
              icon: const OnboardingIcon('arrow-left', size: 28),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
      ],
    ),
  );

  Widget _progress() => Semantics(
    label: 'Tanışma adımı ${_step.index} / 4',
    child: Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 26),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i < _step.index
                      ? OnboardingTheme.lime
                      : const Color(0xFFE3ECD9),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  List<Widget> _welcome(double heroSize) => [
    const SizedBox(height: 14),
    Center(
      child: LimelyMascot(
        key: const ValueKey('onboarding-welcome-mascot'),
        size: heroSize,
        animated: true,
        halo: true,
      ),
    ),
    const SizedBox(height: 15),
    Semantics(
      header: true,
      child: Text(
        'Merhaba, ben\nLimely!',
        textAlign: TextAlign.center,
        style: OnboardingTheme.heading(40),
      ),
    ),
    const SizedBox(height: 16),
    const Text(
      'Kendine iyi gelen küçük\nadımları birlikte atalım.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 21, height: 1.4, color: OnboardingTheme.muted),
    ),
    const SizedBox(height: 22),
    Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
        decoration: BoxDecoration(
          color: OnboardingTheme.soft,
          borderRadius: BorderRadius.circular(40),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OnboardingIcon('sprout', size: 23),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Önce seni biraz tanıyalım.',
                style: TextStyle(fontSize: 16, color: OnboardingTheme.ink),
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 28),
    const Spacer(),
    FilledButton(
      key: const ValueKey('onboarding-start'),
      onPressed: () => _go(_Step.goal),
      child: const Text('Hadi başlayalım', textAlign: TextAlign.center),
    ),
    const SizedBox(height: 4),
    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Zaten hesabın var mı?',
          style: TextStyle(fontSize: 15, color: OnboardingTheme.ink),
        ),
        TextButton(
          key: const ValueKey('onboarding-login'),
          onPressed: widget.onLogin,
          style: TextButton.styleFrom(
            foregroundColor: OnboardingTheme.ink,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            minimumSize: const Size(48, 48),
          ),
          child: const Text(
            'Giriş yap',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    ),
  ];

  Widget _intro(String title, String subtitle, {bool measurement = false}) =>
      Row(
        children: [
          LimelyMascot(size: 116, pose: measurement ? 'olcum' : 'merhaba'),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: OnboardingTheme.heading(30)),
                ),
                const SizedBox(height: 10),
                Text(subtitle, style: OnboardingTheme.body),
              ],
            ),
          ),
        ],
      );

  List<Widget> _goals() => [
    _intro('Sana nasıl\neşlik edelim?', 'Hedefini birlikte belirleyelim.'),
    const SizedBox(height: 22),
    for (final goal in _Goal.values) ...[
      OnboardingChoiceCard(
        key: ValueKey('onboarding-goal-${goal.name}'),
        label: goal.label,
        icon: goal.icon,
        selected: _goal == goal,
        onTap: () => setState(() => _goal = goal),
      ),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 6),
    const OnboardingHint('Hedefin zamanla değişebilir.'),
    const SizedBox(height: 24),
    const Spacer(),
    FilledButton(
      key: const ValueKey('onboarding-goal-next'),
      onPressed: () => _go(_Step.details),
      child: const Text('Devam et'),
    ),
    const SizedBox(height: 12),
  ];

  List<Widget> _details() => [
    _intro(
      'Seni biraz\ntanıyalım.',
      'Başlangıcını sana göre hazırlayalım.',
      measurement: true,
    ),
    const SizedBox(height: 22),
    Form(
      key: _form,
      child: Column(
        children: [
          OnboardingNumberField(
            name: 'age',
            label: 'Yaşın',
            icon: 'calendar-days',
            hint: '28',
            controller: _age,
            focusNode: _ageFocus,
            onSubmitted: () => _heightFocus.requestFocus(),
            validator: (value) => _validateInteger(value, 18, 120, 'Yaş'),
          ),
          const SizedBox(height: 10),
          OnboardingNumberField(
            name: 'height',
            label: 'Boyun',
            icon: 'height',
            hint: '170',
            unit: 'cm',
            controller: _height,
            focusNode: _heightFocus,
            onSubmitted: () => _weightFocus.requestFocus(),
            validator: (value) => _validateInteger(value, 100, 250, 'Boy'),
          ),
          const SizedBox(height: 10),
          OnboardingNumberField(
            name: 'weight',
            label: 'Kilon',
            icon: 'body-scale',
            hint: '72',
            unit: 'kg',
            decimal: true,
            controller: _weight,
            focusNode: _weightFocus,
            onSubmitted: _review,
            validator: _validateWeight,
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    Semantics(
      header: true,
      child: Text('Günün nasıl geçiyor?', style: OnboardingTheme.heading(23)),
    ),
    const SizedBox(height: 14),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, activity) in _Activity.values.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: OnboardingChoiceCard(
              key: ValueKey('onboarding-activity-${activity.name}'),
              label: activity.label,
              icon: activity.icon,
              selected: _activity == activity,
              compact: true,
              onTap: () => setState(() => _activity = activity),
            ),
          ),
        ],
      ],
    ),
    const SizedBox(height: 20),
    const OnboardingHint('Bu bilgileri daha sonra değiştirebilirsin.'),
    const SizedBox(height: 24),
    const Spacer(),
    FilledButton(
      key: const ValueKey('onboarding-review'),
      onPressed: _review,
      child: const Text('Devam et'),
    ),
    const SizedBox(height: 12),
  ];

  List<Widget> _summary() => [
    Container(
      decoration: BoxDecoration(
        color: OnboardingTheme.soft,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Güzel bir\nbaşlangıç!',
                style: OnboardingTheme.heading(29),
              ),
            ),
          ),
          Image.asset(
            'assets/limely/maskotlar/limely-maskot-kutlama.png',
            width: 128,
            height: 128,
            cacheWidth: 512,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    const Text(
      'Hedefin ve günlük ritmin bir arada.',
      style: TextStyle(
        fontSize: 16,
        height: 1.45,
        color: OnboardingTheme.muted,
      ),
    ),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDFE7DA)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: OnboardingTheme.shadow,
      ),
      child: Column(
        children: [
          for (final (index, row) in [
            ('sprout', 'Hedefin', _goal.label),
            ('calendar-days', 'Yaşın', '${int.parse(_age.text.trim())} yaş'),
            ('height', 'Boyun', '${int.parse(_height.text.trim())} cm'),
            (
              'body-scale',
              'Kilon',
              '${_weight.text.trim().replaceAll('.', ',')} kg',
            ),
            ('walk', 'Günlük ritmin', _activity.label),
          ].indexed) ...[
            if (index > 0) const Divider(height: 1, color: Color(0xFFE9EDE4)),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    OnboardingIcon(row.$1, size: 22),
                    const SizedBox(width: 14),
                    Expanded(child: Text(row.$2, style: OnboardingTheme.hint)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.$3,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: OnboardingTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 24),
    const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OnboardingIcon('leaf', size: 18),
        SizedBox(width: 10),
        Flexible(
          child: Text('Küçük adımlar. Sana göre.', style: OnboardingTheme.hint),
        ),
      ],
    ),
    const SizedBox(height: 28),
    const Spacer(),
    FilledButton(
      key: const ValueKey('onboarding-account'),
      onPressed: () => _go(_Step.account),
      child: const Text('Devam et'),
    ),
    const SizedBox(height: 16),
    const Text(
      'Şimdi hesabını oluşturalım.',
      textAlign: TextAlign.center,
      style: OnboardingTheme.hint,
    ),
  ];
}
