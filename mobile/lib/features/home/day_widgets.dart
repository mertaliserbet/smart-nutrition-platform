import 'package:flutter/material.dart';

import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';
import 'dashboard_data.dart';

String dayNumber(num value) {
  final parts = dashboardNumber(value).split(',');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return parts.join(',');
}

class DaySurface extends StatelessWidget {
  const DaySurface({required this.child, this.onTap, this.label, super.key});
  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .7),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: const BorderSide(color: OnboardingTheme.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      label: label,
      button: onTap == null ? null : true,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

class DayHeader extends StatelessWidget {
  const DayHeader({required this.day, this.name, this.onProfile, super.key});
  final DateTime day;
  final String? name;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    const months = [
      'OCAK',
      'ŞUBAT',
      'MART',
      'NİSAN',
      'MAYIS',
      'HAZİRAN',
      'TEMMUZ',
      'AĞUSTOS',
      'EYLÜL',
      'EKİM',
      'KASIM',
      'ARALIK',
    ];
    const days = [
      'PAZARTESİ',
      'SALI',
      'ÇARŞAMBA',
      'PERŞEMBE',
      'CUMA',
      'CUMARTESİ',
      'PAZAR',
    ];
    final displayName = name?.trim();
    // The account currently stores a full display name in one field. Keep
    // multiple given names, omitting the final (surname) word in this greeting.
    final nameParts = displayName?.split(RegExp(r'\s+')) ?? <String>[];
    final givenName = nameParts.length > 1
        ? nameParts.take(nameParts.length - 1).join(' ')
        : displayName;
    final initials = displayName == null || displayName.isEmpty
        ? '?'
        : displayName
              .split(RegExp(r'\s+'))
              .take(2)
              .map(
                (part) =>
                    part.characters.first.replaceAll('i', 'İ').toUpperCase(),
              )
              .join();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Image.asset(
                'assets/limely/logolar/limely-yazili-logo-renkli.png',
                width: constraints.maxWidth < 280 ? 125 : 155,
                height: 56,
                fit: BoxFit.contain,
                semanticLabel: 'Limely',
                filterQuality: FilterQuality.high,
              ),
              const Spacer(),
              if (constraints.maxWidth >= 280)
                const Tooltip(
                  message: 'Bildirimler henüz kullanıma açık değil',
                  child: SizedBox(
                    width: 42,
                    height: 44,
                    child: Center(child: OnboardingIcon('bell', size: 26)),
                  ),
                ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Hesabım',
                button: true,
                child: Material(
                  color: const Color(0xFFE1EDD3),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onProfile,
                    child: SizedBox.square(
                      dimension: 45,
                      child: Center(
                        child: ExcludeSemantics(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 18,
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
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              '${day.day} ${months[day.month - 1]} · ${days[day.weekday - 1]}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bugün',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                OnboardingIcon('chevron-down', size: 19),
              ],
            ),
          ],
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText =
                MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                constraints.maxWidth < 280;
            final title = Text(
              'Günün, senin\nritminde.',
              style: OnboardingTheme.heading(
                constraints.maxWidth < 360 ? 36 : 40,
              ).copyWith(letterSpacing: -1.5),
            );
            final mascot = LimelyMascot(
              size: constraints.maxWidth < 360 ? 138 : 153,
              animated: true,
            );
            if (largeText) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.centerRight, child: mascot),
                  title,
                ],
              );
            }
            return SizedBox(
              height: 145,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(right: -6, top: -5, child: mascot),
                  title,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 1),
        Text(
          givenName == null || givenName.isEmpty
              ? 'Bugün kendine iyi gelecek bir adım seç.'
              : '$givenName, bugün kendine iyi gelecek bir adım seç.',
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: OnboardingTheme.muted,
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

class DayMealActions extends StatelessWidget {
  const DayMealActions({required this.onAdd, super.key});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: OnboardingTheme.ink,
          foregroundColor: OnboardingTheme.background,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        onPressed: onAdd,
        child: Row(
          children: [
            Image.asset(
              'assets/limely/ikonlar/beyaz/camera.png',
              width: 33,
              height: 33,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Text(
                'Öğün ekle',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            Image.asset(
              'assets/limely/ikonlar/beyaz/chevron-right.png',
              width: 23,
              height: 23,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final largeText =
              MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
              constraints.maxWidth < 280;
          final width = largeText
              ? constraints.maxWidth
              : (constraints.maxWidth - 18) / 3;
          return Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final item in [
                (label: 'Fotoğraf', icon: 'image', available: false),
                (label: 'Barkod', icon: 'barcode', available: false),
                (label: 'Manuel', icon: 'pencil', available: true),
              ])
                SizedBox(
                  width: width,
                  child: Tooltip(
                    message: item.available
                        ? 'Öğünü elle kaydet'
                        : '${item.label} ile öğün ekleme henüz kullanıma açık değil',
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: OnboardingTheme.soft,
                        foregroundColor: OnboardingTheme.ink,
                        disabledForegroundColor: OnboardingTheme.muted,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: item.available ? onAdd : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OnboardingIcon(item.icon, size: 20),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class DayAppointment extends StatelessWidget {
  const DayAppointment({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: const BoxDecoration(
      border: Border.symmetric(
        horizontal: BorderSide(color: Color(0xFFD7E1D0)),
      ),
    ),
    child: Row(
      children: [
        const OnboardingIcon('calendar-days', size: 29),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Görüşmelerim', style: OnboardingTheme.heading(19)),
              const SizedBox(height: 4),
              const Text(
                'Görüşme bilgisi bulunmuyor.',
                style: TextStyle(fontSize: 14, color: OnboardingTheme.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
