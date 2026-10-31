import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'email_verification_api.dart';
import 'login_page.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    this.email,
    this.registrationCompleted = false,
    this.verificationApi,
    this.now = DateTime.now,
    super.key,
  });

  final String? email;
  // Presentation context from a valid registration 201, never a login/session.
  final bool registrationCompleted;
  final EmailVerificationApi? verificationApi;
  final DateTime Function() now;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _verifyForm = GlobalKey<FormState>();
  final _resendForm = GlobalKey<FormState>();
  final _token = TextEditingController();
  late final _email = TextEditingController(text: widget.email ?? '');
  Timer? _cooldownTimer;
  DateTime? _resendAvailableAt;
  String? _pending;
  String? _feedback;
  bool _feedbackIsError = false;
  bool _verified = false;

  bool get _busy => _pending != null;
  int get _remainingSeconds {
    final remaining =
        _resendAvailableAt?.difference(widget.now()).inMilliseconds ?? 0;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    if (widget.registrationCompleted) {
      _beginCooldown(const Duration(seconds: 60));
    }
  }

  void _beginCooldown(Duration duration) {
    _cooldownTimer?.cancel();
    _resendAvailableAt = widget.now().add(duration);
    if (_remainingSeconds == 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds == 0) timer.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _token.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || _verified || !_verifyForm.currentState!.validate()) return;
    final submittedToken = _token.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _pending = 'verify';
      _feedback = null;
    });
    // The token remains only in the in-flight request, never navigation/storage.
    _token.clear();
    try {
      await (widget.verificationApi ?? EmailVerificationApi()).verifyEmail(
        submittedToken,
      );
      if (!mounted) return;
      _cooldownTimer?.cancel();
      setState(() {
        _verified = true;
        _pending = null;
      });
    } catch (error) {
      _showFailure(error);
    }
  }

  Future<void> _resend() async {
    if (_busy ||
        _verified ||
        _remainingSeconds > 0 ||
        !_resendForm.currentState!.validate()) {
      return;
    }
    final email = _email.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _pending = 'resend';
      _feedback = null;
    });
    try {
      await (widget.verificationApi ?? EmailVerificationApi())
          .resendVerification(email);
      if (!mounted) return;
      _beginCooldown(const Duration(seconds: 60));
      setState(() {
        _pending = null;
        _feedbackIsError = false;
        _feedback =
            'Hesap doğrulamaya uygunsa gönderim isteği işleme alınır. Gelen kutunuzu ve spam klasörünü kontrol edin. Yeni kod gelirse en son e-postadaki kodu kullanın.';
      });
    } catch (error) {
      _showFailure(error);
    }
  }

  void _showFailure(Object error) {
    if (!mounted) return;
    if (error is EmailVerificationApiException && error.retryAfter != null) {
      _beginCooldown(error.retryAfter!);
    }
    setState(() {
      _pending = null;
      _feedbackIsError = true;
      _feedback = error is EmailVerificationApiException
          ? error.message
          : 'İşlem tamamlanamadı. Lütfen daha sonra tekrar deneyin.';
    });
  }

  void _clearFeedback(String value) {
    if (_feedback != null) setState(() => _feedback = null);
  }

  void _returnToLogin() {
    _token.clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/login'),
        builder: (context) => const LoginPage(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AuthPageLayout(
        title: 'E-posta adresinizi doğrulayın',
        description:
            'E-postadaki tek kullanımlık kodu girin. Kod 30 dakika geçerlidir.',
        icon: Icons.mark_email_unread_outlined,
        notice: _verified
            ? 'E-posta doğrulaması tamamlandı.'
            : widget.registrationCompleted
            ? 'Hesabınız oluşturuldu. Giriş için e-posta doğrulaması gerekir.'
            : 'E-posta doğrulaması oturum açmaz.',
        footer: TextButton(
          onPressed: _busy
              ? null
              : (_verified || widget.registrationCompleted)
              ? _returnToLogin
              : Navigator.of(context).canPop()
              ? () => Navigator.pop(context)
              : _returnToLogin,
          child: Text(
            (_verified || widget.registrationCompleted)
                ? 'Giriş ekranına dön'
                : 'Önceki ekrana dön',
            textAlign: TextAlign.center,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_verified)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Kodun bağlı olduğu e-posta adresi doğrulandı. Oturum açılmadı. Giriş ekranına dönebilirsiniz.',
                  style: theme.textTheme.bodyLarge,
                ),
              )
            else ...[
              Form(
                key: _verifyForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _token,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      validator: (value) => _busy
                          ? null
                          : AuthValidation.verificationToken(value),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _clearFeedback,
                      onFieldSubmitted: (_) => _verify(),
                      decoration: const InputDecoration(
                        labelText: 'Doğrulama kodu',
                        border: authInputBorder,
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                    AuthSubmitButton(
                      label: 'E-postamı doğrula',
                      isLoading: _pending == 'verify',
                      enabled: !_busy,
                      onPressed: _verify,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spacingLarge),
              Text('Kod ulaşmadı mı?', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppTokens.spacingMedium),
              Form(
                key: _resendForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      readOnly:
                          widget.registrationCompleted && widget.email != null,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      validator: AuthValidation.email,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _clearFeedback,
                      onFieldSubmitted: (_) => _resend(),
                      decoration: const InputDecoration(
                        labelText: 'E-posta adresi',
                        border: authInputBorder,
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                    OutlinedButton(
                      onPressed: _busy || _remainingSeconds > 0
                          ? null
                          : _resend,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(AppTokens.spacingMedium),
                      ),
                      child: Text(
                        _pending == 'resend'
                            ? 'İstek gönderiliyor…'
                            : 'Doğrulama E-postasını Tekrar Gönder',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_remainingSeconds > 0) ...[
                      const SizedBox(height: AppTokens.spacingSmall),
                      Text(
                        'Tekrar istemek için $_remainingSeconds sn bekleyin.',
                      ),
                    ],
                  ],
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: AppTokens.spacingMedium),
                if (_feedbackIsError)
                  AuthErrorNotice(message: _feedback!)
                else
                  Semantics(liveRegion: true, child: Text(_feedback!)),
              ],
              const SizedBox(height: AppTokens.spacingLarge),
              const Text('E-posta adresinizi doğrulamadan oturum açılmaz.'),
              const SizedBox(height: AppTokens.spacingSmall),
              const Text(
                'Kodu webde doğruladıysanız giriş ekranına dönebilirsiniz.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
