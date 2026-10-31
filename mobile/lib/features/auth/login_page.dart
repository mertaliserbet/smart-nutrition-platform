import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_page.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';
import 'auth_session.dart';
import 'login_api.dart';

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

  @override
  Widget build(BuildContext context) {
    final error =
        widget.errorMessage ??
        _feedback ??
        AuthSessionScope.maybeOf(context)?.notice;

    return PopScope(
      canPop: !_busy,
      child: AuthPageLayout(
        title: 'Tekrar hoş geldiniz',
        description: 'Beslenme yolculuğunuza kaldığınız yerden devam edin.',
        icon: Icons.login_rounded,
        notice: 'Giriş için e-posta adresinizin doğrulanmış olması gerekir.',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _openPage(const RegisterPage()),
              child: const Text(
                'Hesabınız yok mu? Kayıt ol',
                textAlign: TextAlign.center,
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _openPage(const EmailVerificationPage()),
              child: const Text(
                'E-posta doğrulama hakkında',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                validator: AuthValidation.email,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: _clearFeedback,
                decoration: const InputDecoration(
                  labelText: 'E-posta',
                  border: authInputBorder,
                  errorMaxLines: 4,
                ),
              ),
              const SizedBox(height: AppTokens.spacingMedium),
              AuthPasswordField(
                controller: _password,
                enabled: !_busy,
                validator: (value) =>
                    _busy ? null : AuthValidation.password(value),
                onChanged: _clearFeedback,
                onFieldSubmitted: (value) => _submit(),
              ),
              const SizedBox(height: AppTokens.spacingSmall),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _openPage(const ForgotPasswordPage()),
                  child: const Text(
                    'Şifremi unuttum',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (error != null && !_busy) ...[
                AuthErrorNotice(message: error),
                const SizedBox(height: AppTokens.spacingMedium),
              ],
              AuthSubmitButton(
                label: 'Giriş yap',
                isLoading: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
