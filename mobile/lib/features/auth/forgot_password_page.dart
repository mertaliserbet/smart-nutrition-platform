import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import 'auth_session.dart';
import 'auth_validation.dart';
import 'auth_widgets.dart';
import 'login_page.dart';
import 'password_reset_api.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    this.api,
    this.isLoading = false,
    this.errorMessage,
    super.key,
  });
  final PasswordResetApi? api;
  final bool isLoading;
  final String? errorMessage;
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final _api = widget.api ?? PasswordResetApi();
  bool _sending = false,
      _codeMode = false,
      _requested = false,
      _completed = false;
  bool _tracking = false, _blocked = false;
  AuthSession? _session;
  String? _owner, _error;
  int _revision = 0;
  bool get _busy => widget.isLoading || _sending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (_tracking &&
        (!identical(session, _session) || session?.user?.id != _owner)) {
      ++_revision;
      _clearSecrets();
      _email.clear();
      _error = null;
      _requested = false;
      _completed = false;
      _sending = false;
      _blocked = true;
    }
    _tracking = true;
    _session = session;
    _owner = session?.user?.id;
  }

  void _clearSecrets() {
    _token.clear();
    _password.clear();
    _confirmation.clear();
  }

  @override
  void dispose() {
    ++_revision;
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _blocked || _completed) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final revision = _revision, reset = _codeMode;
    final email = _email.text.trim(),
        token = _token.text.trim(),
        password = _password.text;
    setState(() => _sending = true);
    if (reset) {
      _password.clear();
      _confirmation.clear();
    }
    try {
      if (reset) {
        await _api.reset(token, password);
      } else {
        await _api.request(email);
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        if (reset) {
          _clearSecrets();
          _email.clear();
          _completed = true;
        } else {
          _requested = true;
          _codeMode = true;
        }
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = error is PasswordResetApiException
              ? error.message
              : 'İşlem sonucu doğrulanamadı. Lütfen yeniden kontrol edin.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _sending = false);
    }
  }

  void _mode(bool codeMode) {
    if (_busy || _blocked) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _clearSecrets();
      _error = null;
      _requested = false;
      _codeMode = codeMode;
    });
  }

  void _login() {
    if (_busy) return;
    _clearSecrets();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthPageLayout(
      title: _completed
          ? 'Şifreniz yenilendi'
          : _codeMode
          ? 'Yeni şifre belirleyin'
          : 'Şifrenizi mi unuttunuz?',
      description: _completed
          ? 'Yeni şifrenizle yeniden giriş yapabilirsiniz. Otomatik giriş yapılmadı.'
          : _codeMode
          ? 'E-postadaki tek kullanımlık kodu yapıştırıp yeni şifrenizi belirleyin.'
          : 'Hesabınızın e-posta adresiyle sıfırlama kodu isteyin.',
      icon: Icons.lock_reset_rounded,
      notice:
          'Sıfırlama kodu 30 dakika geçerlidir. Bağlantı veya e-posta doğrulama kodu yerine en son parola sıfırlama kodunu kullanın.',
      footer: TextButton(
        onPressed: _busy ? null : _login,
        child: const Text('Giriş ekranına dön'),
      ),
      child: _blocked
          ? const Text(
              'Oturum değişti. Giriş ekranına dönüp işlemi yeniden başlatın.',
            )
          : _completed
          ? const Text(
              'Şifreniz başarıyla değiştirildi. Önceki oturumlarınız sonlandırıldı.',
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_requested) ...[
                    const Text(
                      'Bu adres uygun bir hesaba aitse sıfırlama kodu e-postayla gönderilir. Gelen kutunuzu ve istenmeyen postaları kontrol edin.',
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                  ],
                  if (!_codeMode)
                    TextFormField(
                      key: const ValueKey('reset-email'),
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: AuthValidation.email,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'E-posta',
                        border: authInputBorder,
                        errorMaxLines: 4,
                      ),
                    )
                  else ...[
                    TextFormField(
                      key: const ValueKey('reset-token'),
                      controller: _token,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      validator: (value) =>
                          RegExp(
                            r'^[A-Za-z0-9_-]{43}$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'E-postadaki 43 karakterlik parola sıfırlama kodunu girin.',
                      decoration: const InputDecoration(
                        labelText: 'Sıfırlama kodu',
                        border: authInputBorder,
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                    AuthPasswordField(
                      key: const ValueKey('reset-password'),
                      controller: _password,
                      label: 'Yeni şifre',
                      enabled: !_busy,
                      validator: AuthValidation.registrationPassword,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                    AuthPasswordField(
                      key: const ValueKey('reset-confirmation'),
                      controller: _confirmation,
                      label: 'Yeni şifre (tekrar)',
                      enabled: !_busy,
                      validator: (value) =>
                          AuthValidation.confirmation(value, _password.text),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: AppTokens.spacingLarge),
                  if (widget.errorMessage ?? _error case final error?) ...[
                    AuthErrorNotice(message: error),
                    const SizedBox(height: AppTokens.spacingMedium),
                  ],
                  AuthSubmitButton(
                    label: _codeMode ? 'Şifreyi yenile' : 'Sıfırlama kodu iste',
                    isLoading: _busy,
                    onPressed: _submit,
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _mode(!_codeMode),
                    child: Text(
                      _codeMode ? 'Yeni kod iste' : 'Sıfırlama kodum var',
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}
