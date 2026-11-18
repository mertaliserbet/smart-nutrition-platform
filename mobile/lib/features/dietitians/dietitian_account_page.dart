import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import 'dietitian_api.dart';
import 'dietitian_workspace_page.dart';

class DietitianAccountPage extends StatefulWidget {
  const DietitianAccountPage({this.showSignOut = false, super.key});

  final bool showSignOut;

  @override
  State<DietitianAccountPage> createState() => _DietitianAccountPageState();
}

class _DietitianAccountPageState extends State<DietitianAccountPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _license = TextEditingController();
  DietitianApi? _api;
  Future<DietitianStatusResponse?>? _profile;
  bool _sending = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (_api == null && session?.user != null) {
      _api = DietitianApi(session!);
      _name.text = session.user?.displayName ?? '';
      _profile = _api!.profile();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _license.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _error = null;
      _profile = _api?.profile();
    });
  }

  Future<void> _apply() async {
    if (_sending || _api == null || !_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final profile = await _api!.applyExisting(
        _name.text.trim(),
        _license.text.trim(),
      );
      if (!mounted) return;
      _license.clear();
      setState(() => _profile = Future.value(profile));
    } on DietitianApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        if (error.statusCode == 409) _profile = _api!.profile();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _validate(String? value, int limit, String label) {
    final length = value?.trim().runes.length ?? 0;
    return length < 1 || length > limit
        ? '$label 1–$limit karakter olmalı.'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthSessionScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diyetisyen profili'),
        actions: [
          if (widget.showSignOut)
            IconButton(
              onPressed: session?.signOut,
              tooltip: 'Çıkış yap',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<DietitianStatusResponse?>(
          future: _profile,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState == ConnectionState.waiting;
            final profile = snapshot.data;
            final error = snapshot.error;
            return ListView(
              padding: const EdgeInsets.all(AppTokens.spacingLarge),
              children: [
                if (waiting)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Profil kontrol ediliyor',
                  ),
                if (error is DietitianApiException) Text(error.message),
                if (_error != null) Text(_error!),
                if (!waiting && error == null && profile != null) ...[
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.isVerified
                        ? 'Diyetisyen profiliniz onaylandı.'
                        : 'Başvurunuz yönetici onayı bekliyor.',
                  ),
                  if (profile.isVerified) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (context) => DietitianWorkspacePage(
                            api: _api!,
                            dietitianId: profile.id,
                          ),
                        ),
                      ),
                      child: const Text('Danışanlar ve bağlantılar'),
                    ),
                  ],
                ],
                if (!waiting &&
                    error == null &&
                    profile == null &&
                    session?.user?.role == 'client')
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Mevcut hesabınızla diyetisyen başvurusu yapabilirsiniz.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _name,
                          enabled: !_sending,
                          decoration: const InputDecoration(
                            labelText: 'Ad ve soyad',
                          ),
                          validator: (value) =>
                              _validate(value, 120, 'Ad ve soyad'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _license,
                          enabled: !_sending,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Mesleki kayıt açıklaması',
                          ),
                          validator: (value) => _validate(
                            value,
                            2000,
                            'Mesleki kayıt açıklaması',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _sending ? null : _apply,
                          child: const Text('Başvuruyu gönder'),
                        ),
                      ],
                    ),
                  ),
                if (!waiting &&
                    error == null &&
                    profile == null &&
                    session?.user?.role == 'dietitian')
                  const Text('Bu hesaba bağlı diyetisyen profili bulunamadı.'),
                TextButton(
                  onPressed: waiting || _sending ? null : _refresh,
                  child: const Text('Durumu yenile'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
