import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    this.isLoading = false,
    this.errorMessage,
    super.key,
  });

  final bool isLoading;
  final String? errorMessage;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _feedback;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.isLoading) return;
    setState(() => _feedback = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(
      () => _feedback =
          'E-posta gönderimi şu anda kullanıma açık değil. Sıfırlama bağlantısı gönderilmedi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorMessage ?? _feedback;

    return AuthPageLayout(
      title: 'Şifrenizi mi unuttunuz?',
      description:
          'Şifrenizi yenilemek için hesabınıza ait e-posta adresini kullanın.',
      icon: Icons.lock_reset_rounded,
      footer: TextButton(
        onPressed: Navigator.of(context).canPop()
            ? () => Navigator.pop(context)
            : null,
        child: const Text('Giriş ekranına dön', textAlign: TextAlign.center),
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
              textInputAction: TextInputAction.done,
              autocorrect: false,
              validator: AuthValidation.email,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onFieldSubmitted: (value) => _submit(),
              onChanged: (value) {
                if (_feedback != null) setState(() => _feedback = null);
              },
              decoration: const InputDecoration(
                labelText: 'E-posta',
                border: authInputBorder,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: AppTokens.spacingLarge),
            if (error != null && !widget.isLoading) ...[
              AuthErrorNotice(message: error),
              const SizedBox(height: AppTokens.spacingMedium),
            ],
            AuthSubmitButton(
              label: 'Sıfırlama bağlantısı iste',
              isLoading: widget.isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
