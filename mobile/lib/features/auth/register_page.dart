import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({this.isLoading = false, this.errorMessage, super.key});

  final bool isLoading;
  final String? errorMessage;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _feedback;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.isLoading) return;
    setState(() => _feedback = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(
      () => _feedback =
          'Hesap oluşturma şu anda kullanıma açık değil. Hesap oluşturulmadı.',
    );
  }

  void _clearFeedback(String value) {
    // Rebuild touched confirmation fields when the original password changes.
    setState(() => _feedback = null);
  }

  void _openEmailVerification() {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    _password.clear();
    _confirmation.clear();
    setState(() => _feedback = null);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EmailVerificationPage(
          email: AuthValidation.email(email) == null ? email : null,
        ),
      ),
    );
  }

  void _showPrivacyNotice() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.spacingLarge),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'KVKK aydınlatma metni',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppTokens.spacingMedium),
              const Text(
                'Aydınlatma metni henüz yayımlanmadı. Yayımlandığında bu alandan erişebilirsiniz.',
              ),
              const SizedBox(height: AppTokens.spacingLarge),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorMessage ?? _feedback;

    return AuthPageLayout(
      title: 'Size özel bir başlangıç',
      description: 'Beslenme ve diyetisyen takibi için hesabınızı oluşturun.',
      icon: Icons.person_add_alt_rounded,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            onPressed: widget.isLoading ? null : _openEmailVerification,
            child: const Text(
              'E-posta doğrulama adımını incele',
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: Navigator.of(context).canPop()
                ? () => Navigator.pop(context)
                : null,
            child: const Text(
              'Zaten hesabınız var mı? Girişe dön',
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
              controller: _displayName,
              enabled: !widget.isLoading,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              autocorrect: false,
              validator: AuthValidation.displayName,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: _clearFeedback,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad',
                border: authInputBorder,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: AppTokens.spacingMedium),
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
              validator: AuthValidation.registrationPassword,
              textInputAction: TextInputAction.next,
              onChanged: _clearFeedback,
            ),
            const SizedBox(height: AppTokens.spacingSmall),
            Text(
              'Şifreniz 8–128 karakter olmalıdır. Boşluk kullanabilirsiniz.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spacingMedium),
            AuthPasswordField(
              controller: _confirmation,
              label: 'Şifre tekrarı',
              enabled: !widget.isLoading,
              validator: (value) =>
                  AuthValidation.confirmation(value, _password.text),
              onChanged: _clearFeedback,
              onFieldSubmitted: (value) => _submit(),
            ),
            const SizedBox(height: AppTokens.spacingSmall),
            TextButton(
              onPressed: widget.isLoading ? null : _showPrivacyNotice,
              child: const Text(
                'KVKK aydınlatma metni',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppTokens.spacingLarge),
            if (error != null && !widget.isLoading) ...[
              AuthErrorNotice(message: error),
              const SizedBox(height: AppTokens.spacingMedium),
            ],
            AuthSubmitButton(
              label: 'Kayıt ol',
              isLoading: widget.isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
