import 'package:flutter/material.dart';
import '../onboarding/onboarding_theme.dart';
import 'nutrition_plan_api.dart';

const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const _weekdays = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
String planDate(DateTime date, {bool year = true, bool weekday = false}) =>
    '${date.day} ${_months[date.month - 1]}${year ? ' ${date.year}' : ''}${weekday ? ' · ${_weekdays[date.weekday - 1]}' : ''}';
String planPeriod(NutritionPlanResponse plan) => plan.endDate == null
    ? '${planDate(DateTime.parse(plan.startDate))} itibarıyla'
    : planRange(DateTime.parse(plan.startDate), DateTime.parse(plan.endDate!));
String planRange(DateTime from, DateTime to) =>
    from.month == to.month && from.year == to.year
    ? '${from.day}–${planDate(to)}'
    : '${planDate(from)} – ${planDate(to)}';
bool planContains(NutritionPlanResponse plan, DateTime date) {
  final key =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return key.compareTo(plan.startDate) >= 0 &&
      (plan.endDate == null || key.compareTo(plan.endDate!) <= 0);
}

String planInitials(String? name) => name == null || name.trim().isEmpty
    ? '?'
    : name
          .trim()
          .split(RegExp(r'\s+'))
          .take(2)
          .map((p) => p.characters.first.replaceAll('i', 'İ').toUpperCase())
          .join();
String planGivenName(String? name) {
  final parts =
      name?.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList() ??
      [];
  return (parts.length > 1 ? parts.take(parts.length - 1) : parts).join(' ');
}

class PlanSurface extends StatelessWidget {
  const PlanSurface({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(17),
    super.key,
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(21),
      side: const BorderSide(color: OnboardingTheme.border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class PlanTintedIcon extends StatelessWidget {
  const PlanTintedIcon(
    this.name, {
    required this.color,
    this.size = 24,
    super.key,
  });
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/limely/ikonlar/koyu/$name.png',
    color: color,
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

class PlanSheetHeader extends StatelessWidget {
  const PlanSheetHeader(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
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
                25,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Kapat',
            style: IconButton.styleFrom(backgroundColor: OnboardingTheme.soft),
            icon: const OnboardingIcon('x', size: 19),
          ),
        ],
      ),
    ],
  );
}
