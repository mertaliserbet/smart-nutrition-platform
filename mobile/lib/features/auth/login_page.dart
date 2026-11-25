import 'package:flutter/material.dart';

import '../onboarding/onboarding_theme.dart';
import 'limely_auth_widgets.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'forgot_password_page.dart';
import 'auth_session.dart';
import 'login_api.dart';
import 'web_panel_link.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({this.isLoading = false, this.errorMessage, super.key});

  // Optional presentation overrides; real pending state is always respected.
  final bool isLoading;
  final String? errorMessage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _feedback;
  final _standaloneSession = AuthSession();
  bool _submitting = false;
  bool get _busy => widget.isLoading || _submitting;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _standaloneSession.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _feedback = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final session = AuthSessionScope.maybeOf(context) ?? _standaloneSession;
    final email = _email.text.trim();
    final password = _password.text;
    setState(() => _submitting = true);
    _password.clear();
    try {
      await session.signIn(email: email, password: password);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _feedback = error is LoginApiException
            ? error.message
            : 'Giriş tamamlanamadı. Lütfen daha sonra tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _clearFeedback(String value) {
    if (_feedback != null) setState(() => _feedback = null);
  }

  void _openPage(Widget page) {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() => _feedback = null);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  void _startOnboarding() {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil<void>('/welcome', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final error =
        widget.errorMessage ??
        _feedback ??
        AuthSessionScope.maybeOf(context)?.notice;

    return PopScope(
      canPop: !_busy,
      child: LimelyAuthLayout(
        onBack: _busy ? null : _startOnboarding,
        backKey: const ValueKey('login-back'),
        children: [
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 162,
              height: 152,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    width: 162,
                    height: 162,
                    child: Image.asset(
                      'assets/limely/dekorlar/maskot-halesi.png',
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 8,
                    width: 146,
                    height: 146,
                    child: Image.asset(
                      'assets/limely/maskotlar/limely-maskot-goz-kirpma.png',
                      cacheWidth: 584,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            header: true,
            child: Text(
              'Yeniden merhaba!',
              textAlign: TextAlign.center,
              style: OnboardingTheme.heading(32),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Küçük adımlarına\nkaldığın yerden devam et.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16.5,
              height: 1.4,
              color: OnboardingTheme.muted,
            ),
          ),
          const SizedBox(height: 12),
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LimelyAuthField(
                    label: 'E-posta',
                    hint: 'ornek@eposta.com',
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: AuthValidation.email,
                    onChanged: _clearFeedback,
                    icon: const LimelyLineIcon(LimelySymbol.mail),
                  ),
                  const SizedBox(height: 15),
                  LimelyAuthField(
                    label: 'Şifre',
                    hint: 'Şifreni gir',
                    controller: _password,
                    password: true,
                    enabled: !_busy,
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        _busy ? null : AuthValidation.password(value),
                    onChanged: _clearFeedback,
                    onFieldSubmitted: (value) => _submit(),
                    icon: const LimelyLineIcon(LimelySymbol.lock),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _openPage(const ForgotPasswordPage()),
                      child: const Text('Şifremi unuttum'),
                    ),
                  ),
                  if (error != null && !_busy) ...[
                    AuthErrorNotice(message: error),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 8),
                  AuthSubmitButton(
                    label: 'Giriş yap',
                    isLoading: _busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Spacer(),
          TextButton(
            key: const ValueKey('login-register'),
            onPressed: _busy ? null : _startOnboarding,
            child: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Hesabın yok mu? ',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                  TextSpan(
                    text: 'Kayıt ol',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 44),
            child: Divider(height: 1, color: Color(0xFFDFE7DA)),
          ),
          const SizedBox(height: 12),
          WebPanelLink(
            enabled: !_busy,
            limely: true,
            onOpening: () {
              FocusScope.of(context).unfocus();
              _password.clear();
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
