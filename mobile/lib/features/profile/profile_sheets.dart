import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../auth/login_api.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/onboarding_theme.dart';
import 'profile_widgets.dart';

enum ProfileSheetKind { details, security, professional, about, logout }

enum ProfileAction { resetPassword, applyExpert, expertWeb, signOut, refresh }

/// Private snapshots and legacy forms cannot survive an owner/lifecycle change.
class ProfileRouteGuard extends StatefulWidget {
  const ProfileRouteGuard({
    required this.session,
    required this.owner,
    required this.child,
    this.sheet = false,
    super.key,
  });
  final AuthSession session;
  final String owner;
  final Widget child;
  final bool sheet;
  @override
  State<ProfileRouteGuard> createState() => _ProfileRouteGuardState();
}

class _ProfileRouteGuardState extends State<ProfileRouteGuard>
    with WidgetsBindingObserver {
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AuthSessionScope.maybeOf(context);
    if (!identical(s, widget.session) ||
        s?.isAuthenticated != true ||
        s?.user?.id != widget.owner) {
      _expired = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(() => _expired = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expired) return widget.child;
    final content = Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Bilgileri görüntülemek için Hesabım ekranını yeniden aç.',
            style: OnboardingTheme.hint,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: profilePrimaryStyle(),
            child: const Text('Hesabıma dön'),
          ),
        ],
      ),
    );
    return Theme(
      data: OnboardingTheme.data,
      child: widget.sheet
          ? SafeArea(top: false, child: content)
          : Scaffold(
              body: SafeArea(
                child: Center(child: SingleChildScrollView(child: content)),
              ),
            ),
    );
  }
}

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({
    required this.kind,
    required this.session,
    required this.owner,
    required this.user,
    required this.professionalKnown,
    this.professional,
    super.key,
  });
  final ProfileSheetKind kind;
  final AuthSession session;
  final String owner;
  final CurrentUserResponse user;
  final DietitianStatusResponse? professional;
  final bool professionalKnown;
  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  bool _closed = false;
  void _finish([ProfileAction? action]) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) => ProfileRouteGuard(
    session: widget.session,
    owner: widget.owner,
    sheet: true,
    child: Theme(
      data: OnboardingTheme.data,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(21, 11, 21, 23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileSheetHeader(
                  title: switch (widget.kind) {
                    ProfileSheetKind.details => 'Kişisel bilgilerim',
                    ProfileSheetKind.security => 'Hesap güvenliği',
                    ProfileSheetKind.professional =>
                      widget.professional?.isVerified == true
                          ? 'Diyetisyen profilin'
                          : 'Diyetisyen misin?',
                    ProfileSheetKind.about => 'Limely hakkında',
                    ProfileSheetKind.logout => 'Çıkış yapmak\nistiyor musun?',
                  },
                  closeLabel: switch (widget.kind) {
                    ProfileSheetKind.details => 'Kişisel bilgileri kapat',
                    ProfileSheetKind.security => 'Hesap güvenliğini kapat',
                    ProfileSheetKind.professional =>
                      'Diyetisyen başvuru bilgisini kapat',
                    ProfileSheetKind.about => 'Limely bilgisini kapat',
                    ProfileSheetKind.logout => 'Çıkış onayını kapat',
                  },
                  onClose: _finish,
                ),
                ...switch (widget.kind) {
                  ProfileSheetKind.details => _details(),
                  ProfileSheetKind.security => _security(),
                  ProfileSheetKind.professional => _professional(),
                  ProfileSheetKind.about => _about(),
                  ProfileSheetKind.logout => _logout(),
                },
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _back() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: FilledButton(
      onPressed: _finish,
      style: profilePrimaryStyle(),
      child: const Text('Hesabıma dön'),
    ),
  );
  List<Widget> _details() => [
    const Text(
      'Hesabına ait bilgileri bir arada gör.',
      style: OnboardingTheme.hint,
    ),
    const SizedBox(height: 18),
    ProfileSurface(
      color: OnboardingTheme.soft,
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Row(
        children: [
          ProfileAvatar(name: widget.user.displayName, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.displayName ?? 'Hesabım',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Danışan hesabı',
                  style: TextStyle(fontSize: 11, color: OnboardingTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 18),
    ProfileInfoRow(
      'Adın soyadın',
      Text(widget.user.displayName ?? 'Belirtilmemiş'),
    ),
    ProfileInfoRow('E-posta', Text(widget.user.email)),
    const ProfileInfoRow('Hesap türü', Text('Danışan')),
    ProfileInfoRow(
      'E-posta durumu',
      ProfileVerification(verified: widget.user.isEmailVerified),
    ),
    _back(),
  ];
  List<Widget> _security() => [
    const Text(
      'Hesabının giriş bilgilerini ve doğrulama durumunu incele.',
      style: OnboardingTheme.hint,
    ),
    const SizedBox(height: 18),
    ProfileSurface(
      radius: 16,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.user.email,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hesabına bu e-posta ile giriş yapıyorsun.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: OnboardingTheme.muted,
            ),
          ),
          const SizedBox(height: 11),
          ProfileVerification(
            verified: widget.user.isEmailVerified,
            full: true,
          ),
        ],
      ),
    ),
    const SizedBox(height: 18),
    ProfileSurface(
      radius: 16,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: const OnboardingIcon('rotate-ccw', size: 22),
        title: const Text(
          'Şifremi yenile',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        trailing: const OnboardingIcon('chevron-right', size: 16),
        onTap: () => _finish(ProfileAction.resetPassword),
      ),
    ),
    const SizedBox(height: 17),
    const Text(
      'Şifren görüntülenmez. Yenilemek istediğinde e-posta ile doğrulama adımından devam edebilirsin.',
      style: OnboardingTheme.hint,
    ),
    _back(),
  ];
  List<Widget> _professional() {
    final profile = widget.professional;
    if (profile != null) {
      return [
        Text(profile.displayName, style: OnboardingTheme.heading(20)),
        const SizedBox(height: 12),
        Text(
          profile.isVerified
              ? 'Diyetisyen profilin onaylandı. Mesleki işlemlerini web panelinden yapabilirsin.'
              : 'Başvurun yönetici onayı bekliyor. Onaylandıktan sonra web panelini kullanabilirsin.',
          style: OnboardingTheme.hint,
        ),
        const SizedBox(height: 18),
        const Text(
          'Danışan profilin ve kişisel kayıtların aynı hesapta korunur.',
          style: OnboardingTheme.hint,
        ),
        const SizedBox(height: 16),
        if (profile.isVerified)
          FilledButton(
            onPressed: () => _finish(ProfileAction.expertWeb),
            style: profilePrimaryStyle(),
            child: const Text('Diyetisyen Paneline Git'),
          )
        else
          OutlinedButton(
            onPressed: () => _finish(ProfileAction.refresh),
            child: const Text('Durumu yenile'),
          ),
        _back(),
      ];
    }
    return [
      const Text(
        'Aynı hesabınla diyetisyen başvurusu yapabilir, onaylandıktan sonra web panelini kullanabilirsin.',
        style: OnboardingTheme.hint,
      ),
      const SizedBox(height: 20),
      for (final (i, title, copy) in const [
        (
          1,
          'Mesleki bilgilerini paylaş',
          'Diyetisyen başvurunu mevcut hesabınla yap.',
        ),
        (
          2,
          'Başvuru durumunu takip et',
          'Onay sürecinin durumunu hesabından gör.',
        ),
        (
          3,
          'Web paneline geç',
          'Onaylandığında danışanlarını diyetisyen panelinden yönet.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OnboardingTheme.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$i',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D7756),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      const Text(
        'Danışan profilin ve kişisel kayıtların aynı hesapta korunur.',
        style: OnboardingTheme.hint,
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: widget.professionalKnown
            ? () => _finish(ProfileAction.applyExpert)
            : null,
        style: profilePrimaryStyle(),
        child: const Text('Başvuruya geç'),
      ),
      _back(),
    ];
  }

  List<Widget> _about() => [
    Align(
      alignment: Alignment.centerLeft,
      child: Image.asset(
        'assets/limely/logolar/limely-yazili-logo-renkli.png',
        width: 151,
        height: 54,
        fit: BoxFit.contain,
        semanticLabel: 'Limely',
      ),
    ),
    const SizedBox(height: 20),
    const Text(
      'Kendine iyi gelen küçük adımlar.',
      style: TextStyle(fontSize: 14, height: 1.7),
    ),
    const SizedBox(height: 15),
    const Text(
      'Günlük beslenme takibini, planını ve diyetisyeninle olan yolculuğunu bir araya getiren kişisel alanın.',
      style: OnboardingTheme.hint,
    ),
    const SizedBox(height: 15),
    const ProfileSurface(
      color: OnboardingTheme.soft,
      padding: EdgeInsets.all(14),
      radius: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingIcon('sprout', size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Her gün aynı olmak zorunda değil. Küçük adımların da yolculuğunun bir parçası.',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: OnboardingTheme.muted,
              ),
            ),
          ),
        ],
      ),
    ),
    _back(),
  ];
  List<Widget> _logout() => [
    const Text(
      'Yeniden giriş yaparak kaldığın yerden devam edebilirsin.',
      style: OnboardingTheme.hint,
    ),
    const SizedBox(height: 20),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton(
          autofocus: true,
          onPressed: _finish,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(125, 51),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => _finish(ProfileAction.signOut),
          style: profilePrimaryStyle().copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(125, 51)),
          ),
          child: const Text('Çıkış yap'),
        ),
      ],
    ),
  ];
}
