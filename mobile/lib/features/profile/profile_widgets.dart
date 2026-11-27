import 'package:flutter/material.dart';
import '../onboarding/onboarding_theme.dart';

String profileInitials(String? name) => name == null || name.trim().isEmpty
    ? '?'
    : name
          .trim()
          .split(RegExp(r'\s+'))
          .take(2)
          .map((p) => p.characters.first.replaceAll('i', 'İ').toUpperCase())
          .join();
String profileGivenName(String? name) {
  final parts =
      name?.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList() ??
      [];
  return (parts.length > 1 ? parts.take(parts.length - 1) : parts).join(' ');
}

class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(17),
    this.radius = 21,
    this.borderColor = OnboardingTheme.border,
    this.accentRing,
    super.key,
  });
  final Widget child;
  final Color color;
  final Color borderColor;
  final Color? accentRing;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor),
    ),
    child: Stack(
      children: [
        if (accentRing != null)
          Positioned(
            right: -68,
            top: -59,
            child: IgnorePointer(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentRing!),
                ),
              ),
            ),
          ),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    this.name,
    this.size = 54,
    this.expert = false,
    super.key,
  });
  final String? name;
  final double size;
  final bool expert;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: expert ? Colors.white : OnboardingTheme.lime,
      borderRadius: BorderRadius.circular(expert ? size : size * .33),
    ),
    child: name == null || name!.trim().isEmpty
        ? OnboardingIcon('user-round', size: size * .45)
        : Text(
            profileInitials(name),
            style: TextStyle(
              fontSize: size * .4,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
              color: OnboardingTheme.ink,
            ),
          ),
  );
}

class ProfileMenuRow extends StatelessWidget {
  const ProfileMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.yellow = false,
    this.divider = false,
    super.key,
  });
  final String icon, title, subtitle;
  final VoidCallback? onTap;
  final bool yellow, divider;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (divider) const Divider(height: 1, color: Color(0xFFEDF0E8)),
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 43),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: yellow
                        ? const Color(0xFFFCF7DC)
                        : const Color(0xFFF0F5E8),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: OnboardingIcon(icon, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: OnboardingTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const OnboardingIcon('chevron-right', size: 16),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class ProfileSheetHeader extends StatelessWidget {
  const ProfileSheetHeader({
    required this.title,
    required this.closeLabel,
    this.onClose,
    super.key,
  });
  final String title, closeLabel;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFC9D3C1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: OnboardingTheme.heading(
                24,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onClose,
            tooltip: closeLabel,
            style: IconButton.styleFrom(backgroundColor: OnboardingTheme.soft),
            icon: const OnboardingIcon('x', size: 20),
          ),
        ],
      ),
      const SizedBox(height: 9),
    ],
  );
}

ButtonStyle profilePrimaryStyle() => FilledButton.styleFrom(
  minimumSize: const Size(double.infinity, 51),
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  textStyle: const TextStyle(
    fontFamily: 'Figtree',
    fontSize: 17,
    fontWeight: FontWeight.w700,
  ),
);

class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow(this.label, this.value, {super.key});
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: OnboardingTheme.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: OnboardingTheme.muted,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.topRight,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: OnboardingTheme.ink,
              ),
              textAlign: TextAlign.right,
              child: value,
            ),
          ),
        ),
      ],
    ),
  );
}

class ProfileVerification extends StatelessWidget {
  const ProfileVerification({
    required this.verified,
    this.full = false,
    super.key,
  });
  final bool verified, full;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: OnboardingTheme.soft,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingIcon(verified ? 'check' : 'info', size: 12),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            verified
                ? (full ? 'E-posta doğrulandı' : 'Doğrulandı')
                : 'Doğrulama bekleniyor',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D7756),
            ),
          ),
        ),
      ],
    ),
  );
}
