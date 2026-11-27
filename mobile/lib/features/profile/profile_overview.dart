import 'package:flutter/material.dart';
import '../auth/login_api.dart';
import '../dietitians/dietitian_api.dart';
import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';
import 'profile_widgets.dart';
import 'profile_sheets.dart' show ProfileSheetKind;

class ProfileOverview extends StatelessWidget {
  const ProfileOverview({
    required this.user,
    required this.authorized,
    required this.connected,
    required this.loadingConnection,
    required this.connectionLoaded,
    required this.loadingProfessional,
    required this.professionalKnown,
    required this.loggingOut,
    required this.onRetry,
    required this.onFind,
    required this.onConnections,
    required this.onSharing,
    required this.onSheet,
    required this.onRoute,
    this.expert,
    this.connectionError,
    this.professional,
    this.professionalError,
    super.key,
  });
  final CurrentUserResponse? user;
  final bool authorized,
      connected,
      loadingConnection,
      connectionLoaded,
      loadingProfessional,
      professionalKnown,
      loggingOut;
  final String? expert, connectionError, professionalError;
  final DietitianStatusResponse? professional;
  final VoidCallback onRetry, onFind, onConnections, onSharing;
  final ValueChanged<ProfileSheetKind> onSheet;
  final ValueChanged<String> onRoute;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 22),
            _hero(context),
            const SizedBox(height: 20),
            if (!authorized)
              const Text('Hesabını görüntülemek için oturumun doğrulanmalıdır.')
            else ...[
              _identity(),
              const SizedBox(height: 13),
              _connection(),
              const SizedBox(height: 24),
              _title('Takibim'),
              const SizedBox(height: 12),
              ProfileSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ProfileMenuRow(
                      icon: 'sprout',
                      title: 'Günlük hedeflerim',
                      subtitle: 'Kendi belirlediğin günlük hedefler.',
                      onTap: () => onRoute('/personal-nutrition-targets'),
                    ),
                    ProfileMenuRow(
                      icon: 'clipboard-check',
                      title: 'Görevlerim',
                      subtitle: 'Diyetisyeninin sana atadığı küçük adımlar.',
                      yellow: true,
                      divider: true,
                      onTap: () => onRoute('/client-tasks'),
                    ),
                    ProfileMenuRow(
                      icon: 'smartphone',
                      title: 'Cihaz sağlık verileri',
                      subtitle: 'Bağlantılarını ve aktarımı yönet.',
                      divider: true,
                      onTap: () => onRoute('/device-health'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _title('Hesap ve gizlilik'),
              const SizedBox(height: 12),
              ProfileSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ProfileMenuRow(
                      icon: 'eye',
                      title: 'Veri paylaşımım',
                      subtitle: 'Hangi bilgileri paylaşacağını seç.',
                      onTap: onSharing,
                    ),
                    ProfileMenuRow(
                      icon: 'shield-check',
                      title: 'Hesap güvenliği',
                      subtitle: 'E-posta doğrulaması ve şifren.',
                      divider: true,
                      onTap: () => onSheet(ProfileSheetKind.security),
                    ),
                    ProfileMenuRow(
                      icon: 'info',
                      title: 'Limely hakkında',
                      subtitle: 'Küçük adımlar, iyi alışkanlıklar.',
                      divider: true,
                      onTap: () => onSheet(ProfileSheetKind.about),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _professional(),
              const SizedBox(height: 17),
              OutlinedButton(
                onPressed: loggingOut
                    ? null
                    : () => onSheet(ProfileSheetKind.logout),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  side: const BorderSide(color: Color(0xFFD8E1D0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const OnboardingIcon('arrow-left', size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        loggingOut ? 'Çıkış yapılıyor…' : 'Çıkış yap',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OnboardingIcon('sprout', size: 16),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Kendine iyi gelen küçük adımlar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.5,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _title(String text) => Text(
    text,
    style: OnboardingTheme.heading(20).copyWith(fontWeight: FontWeight.w700),
  );
  Widget _header() => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            'assets/limely/logolar/limely-yazili-logo-renkli.png',
            width: 151,
            height: 54,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Limely',
          ),
        ),
      ),
      const Tooltip(
        message: 'Bildirimler henüz kullanıma açık değil',
        child: SizedBox.square(
          dimension: 44,
          child: Center(child: OnboardingIcon('bell', size: 25)),
        ),
      ),
      const SizedBox(width: 12),
      Semantics(
        label: 'Kişisel bilgilerim',
        button: authorized,
        child: Material(
          color: const Color(0xFFE1EDD3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: authorized ? () => onSheet(ProfileSheetKind.details) : null,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 43,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    profileInitials(user?.displayName),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _hero(BuildContext context) {
    final name = profileGivenName(user?.displayName),
        large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HESABIM',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Kendine iyi\ngelen alanın.',
          style: OnboardingTheme.heading(
            MediaQuery.sizeOf(context).width < 355 ? 28 : 32,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          '${name.isEmpty ? '' : '$name, '}yolculuğun burada.',
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: OnboardingTheme.muted,
          ),
        ),
      ],
    );
    final mascot = TweenAnimationBuilder<double>(
      tween: Tween(
        begin: MediaQuery.disableAnimationsOf(context) ? 0 : -.04,
        end: .03,
      ),
      duration: const Duration(milliseconds: 900),
      builder: (context, value, child) => Transform.rotate(
        angle: MediaQuery.disableAnimationsOf(context) ? .03 : value,
        child: child,
      ),
      child: const LimelyMascot(size: 111, pose: 'goz-kirpma'),
    );
    return large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              Align(alignment: Alignment.centerRight, child: mascot),
            ],
          )
        : Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 3),
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 355 ? 94 : 111,
                child: mascot,
              ),
            ],
          );
  }

  Widget _identity() => ProfileSurface(
    radius: 22,
    padding: const EdgeInsets.fromLTRB(17, 17, 17, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProfileAvatar(name: user?.displayName),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Hesabım',
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.2,
                      letterSpacing: -.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        const Divider(height: 1, color: Color(0xFFEDF0E8)),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: OnboardingTheme.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OnboardingIcon('leaf', size: 12),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Danışan hesabı',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3D7756),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => onSheet(ProfileSheetKind.details),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Bilgilerimi gör',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3D7756),
                      ),
                    ),
                  ),
                  SizedBox(width: 5),
                  OnboardingIcon('chevron-right', size: 14),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _connection() {
    if (loadingConnection) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Diyetisyen bağlantın yükleniyor',
      );
    }
    if (connectionError != null) {
      return ProfileSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(connectionError!, style: OnboardingTheme.hint),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Bağlantıyı yeniden yükle'),
            ),
            TextButton(
              onPressed: onConnections,
              child: const Text('Bağlantılarımı gör'),
            ),
            TextButton(onPressed: onFind, child: const Text('Diyetisyen Bul')),
          ],
        ),
      );
    }
    if (!connectionLoaded) return const SizedBox.shrink();
    if (!connected) {
      return ProfileSurface(
        color: OnboardingTheme.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Diyetisyeninle bağlantı kur'),
            const SizedBox(height: 8),
            const Text(
              'Mevcut bağlantılarını incele veya diyetisyenini bul.',
              style: OnboardingTheme.hint,
            ),
            Wrap(
              spacing: 10,
              children: [
                TextButton(
                  onPressed: onFind,
                  child: const Text('Diyetisyen Bul'),
                ),
                TextButton(
                  onPressed: onConnections,
                  child: const Text('Bağlantılarımı gör'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ProfileSurface(
      color: OnboardingTheme.soft,
      accentRing: const Color(0xFFDCE8CE),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'DİYETİSYENİM',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF53764D),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ProfileAvatar(name: expert, size: 35, expert: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expert ?? 'Diyetisyenin',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Yolculuğunda sana eşlik ediyor.',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFB9D2A7)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Bağlantı aktif',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.3,
                      color: Color(0xFF3D7756),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFDCE8CE)),
          TextButton(
            onPressed: onSharing,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Bağlantı ve paylaşımı yönet',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3D7756),
                    ),
                  ),
                ),
                OnboardingIcon('chevron-right', size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _professional() {
    final verified = professional?.isVerified == true,
        pending = professional != null && !verified;
    return ProfileSurface(
      color: OnboardingTheme.ink,
      borderColor: OnboardingTheme.ink,
      accentRing: const Color(0x14F8FAF2),
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 37,
                height: 39,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x11F8FAF2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1CF8FAF2)),
                ),
                child: Image.asset(
                  'assets/limely/ikonlar/beyaz/globe.png',
                  width: 21,
                  height: 21,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verified
                          ? 'Diyetisyen profilin onaylı'
                          : pending
                          ? 'Başvurun değerlendirmede'
                          : 'Diyetisyen misin?',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.3,
                        color: OnboardingTheme.background,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      verified
                          ? 'Mesleki alanını web panelinden kullan.'
                          : pending
                          ? 'Başvuru durumunu buradan takip et.'
                          : 'Mesleki yolculuğun da aynı hesapta.',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: Color(0xFFD2DECA),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Divider(height: 1, color: Color(0x1FF8FAF2)),
          if (loadingProfessional)
            const LinearProgressIndicator(
              semanticsLabel: 'Başvuru durumun yükleniyor',
            )
          else if (professionalError != null) ...[
            const SizedBox(height: 8),
            Text(
              professionalError!,
              style: const TextStyle(
                fontSize: 12,
                color: OnboardingTheme.background,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Başvuru durumunu yenile',
                style: TextStyle(color: OnboardingTheme.lime),
              ),
            ),
          ] else
            TextButton(
              onPressed: professionalKnown
                  ? () => onSheet(ProfileSheetKind.professional)
                  : null,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      verified
                          ? 'Diyetisyen Paneline Git'
                          : pending
                          ? 'Başvuru durumunu gör'
                          : 'Diyetisyen başvurusu hakkında',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: OnboardingTheme.lime,
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/limely/ikonlar/beyaz/chevron-right.png',
                    width: 14,
                    height: 14,
                    excludeFromSemantics: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
