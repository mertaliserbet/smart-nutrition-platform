import 'package:flutter/material.dart';

import '../onboarding/onboarding_theme.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_page.dart';
import 'limely_auth_widgets.dart';
import 'registration_api.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    this.isLoading = false,
    this.errorMessage,
    this.registrationApi,
    this.onBack,
    this.onLogin,
    super.key,
  });

  final bool isLoading;
  final String? errorMessage;
  final RegistrationApi? registrationApi;
  final VoidCallback? onBack;
  final VoidCallback? onLogin;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _feedback;
  bool _isSubmitting = false;

  bool get _isLoading => widget.isLoading || _isSubmitting;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() => _feedback = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    setState(() => _isSubmitting = true);
    try {
      await (widget.registrationApi ?? RegistrationApi()).register(
        displayName: _displayName.text,
        email: email,
        password: _password.text,
      );
      if (!mounted) return;
      _password.clear();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) =>
              EmailVerificationPage(email: email, registrationCompleted: true),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _feedback = error is RegistrationApiException
            ? error.message
            : 'Kayıt işlemi tamamlanamadı. Lütfen daha sonra tekrar deneyin.';
      });
    }
  }

  void _clearFeedback(String value) {
    if (_feedback != null) setState(() => _feedback = null);
  }

  void _back() {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _login() {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    if (widget.onLogin != null) {
      widget.onLogin!();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil<void>('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorMessage ?? _feedback;
    return PopScope(
      canPop: !_isLoading && widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isLoading && widget.onBack != null) _back();
      },
      child: LimelyAuthLayout(
        onBack:
            !_isLoading &&
                (widget.onBack != null || Navigator.of(context).canPop())
            ? _back
            : null,
        backKey: const ValueKey('register-back'),
        progress: 4,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/limely/maskotlar/limely-maskot-merhaba.png',
                width: 101,
                height: 101,
                cacheWidth: 404,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 19),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Birlikte\nbaşlayalım.',
                    style: OnboardingTheme.heading(31),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hesabını oluştur, yolculuğun başlasın.',
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: OnboardingTheme.muted,
            ),
          ),
          const SizedBox(height: 24),
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LimelyAuthField(
                    label: 'Adın soyadın',
                    hint: 'Adını ve soyadını gir',
                    controller: _displayName,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.text,
                    autofillHints: const [AutofillHints.name],
                    validator: AuthValidation.displayName,
                    onChanged: _clearFeedback,
                    icon: const OnboardingIcon('user-round', size: 22),
                  ),
                  const SizedBox(height: 5),
                  LimelyAuthField(
                    label: 'E-posta',
                    hint: 'ornek@eposta.com',
                    controller: _email,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: AuthValidation.email,
                    onChanged: _clearFeedback,
                    icon: const LimelyLineIcon(LimelySymbol.mail),
                  ),
                  const SizedBox(height: 5),
                  LimelyAuthField(
                    label: 'Şifre',
                    hint: 'Şifreni oluştur',
                    controller: _password,
                    password: true,
                    newPassword: true,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.done,
                    validator: AuthValidation.registrationPassword,
                    onChanged: _clearFeedback,
                    onFieldSubmitted: (value) => _submit(),
                    icon: const LimelyLineIcon(LimelySymbol.lock),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardingIcon('info', size: 17),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '8–128 karakter kullanabilirsin.',
                          style: OnboardingTheme.hint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (error != null && !_isLoading) ...[
                    AuthErrorNotice(message: error),
                    const SizedBox(height: 16),
                  ],
                  AuthSubmitButton(
                    label: 'Hesabımı oluştur',
                    isLoading: _isLoading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Spacer(),
          const Text(
            'Zaten bir hesabın var mı?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: OnboardingTheme.muted,
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : _login,
            child: const Text(
              'Giriş yap',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
