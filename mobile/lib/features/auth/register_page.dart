import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_page.dart';
import 'registration_api.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    this.isLoading = false,
    this.errorMessage,
    this.registrationApi,
    super.key,
  });

  final bool isLoading;
  final String? errorMessage;
  final RegistrationApi? registrationApi;

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
  bool _isSubmitting = false;

  bool get _isLoading => widget.isLoading || _isSubmitting;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
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
      _confirmation.clear();
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
    // Rebuild touched confirmation fields when the original password changes.
    setState(() => _feedback = null);
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

    return PopScope(
      canPop: !_isLoading,
      child: AuthPageLayout(
        title: 'Size özel bir başlangıç',
        description: 'Beslenme ve diyetisyen takibi için hesabınızı oluşturun.',
        icon: Icons.person_add_alt_rounded,
        notice: 'Hesap oluşturduktan sonra e-posta adresinizi doğrulayın.',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed: !_isLoading && Navigator.of(context).canPop()
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
                enabled: !_isLoading,
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
                enabled: !_isLoading,
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
                enabled: !_isLoading,
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
                enabled: !_isLoading,
                validator: (value) =>
                    AuthValidation.confirmation(value, _password.text),
                onChanged: _clearFeedback,
                onFieldSubmitted: (value) => _submit(),
              ),
              const SizedBox(height: AppTokens.spacingSmall),
              TextButton(
                onPressed: _isLoading ? null : _showPrivacyNotice,
                child: const Text(
                  'KVKK aydınlatma metni',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppTokens.spacingLarge),
              if (error != null && !_isLoading) ...[
                AuthErrorNotice(message: error),
                const SizedBox(height: AppTokens.spacingMedium),
              ],
              AuthSubmitButton(
                label: 'Kayıt ol',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
