import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_page.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({this.isLoading = false, this.errorMessage, super.key});

  // Presentation inputs only; there is no authentication operation or session.
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.isLoading) return;
    setState(() => _feedback = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(
      () => _feedback = 'Giriş şu anda kullanıma açık değil. Oturum açılmadı.',
    );
  }

  void _clearFeedback(String value) {
    if (_feedback != null) setState(() => _feedback = null);
  }

  void _openPage(Widget page) {
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() => _feedback = null);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorMessage ?? _feedback;

    return AuthPageLayout(
      title: 'Tekrar hoş geldiniz',
      description: 'Beslenme yolculuğunuza kaldığınız yerden devam edin.',
      icon: Icons.login_rounded,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            onPressed: widget.isLoading
                ? null
                : () => _openPage(const RegisterPage()),
            child: const Text(
              'Hesabınız yok mu? Kayıt ol',
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: widget.isLoading
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
              enabled: !widget.isLoading,
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
              enabled: !widget.isLoading,
              validator: AuthValidation.password,
              onChanged: _clearFeedback,
              onFieldSubmitted: (value) => _submit(),
            ),
            const SizedBox(height: AppTokens.spacingSmall),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: widget.isLoading
                    ? null
                    : () => _openPage(const ForgotPasswordPage()),
                child: const Text(
                  'Şifremi unuttum',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (error != null && !widget.isLoading) ...[
              AuthErrorNotice(message: error),
              const SizedBox(height: AppTokens.spacingMedium),
            ],
            AuthSubmitButton(
              label: 'Giriş yap',
              isLoading: widget.isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
