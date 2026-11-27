import 'package:flutter/material.dart';
import '../home/day_plan_cards.dart' show dayPlanMeals;
import '../home/day_widgets.dart' show dayNumber;
import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';
import 'meal_log_api.dart';
import 'nutrition_plan_api.dart';
import 'nutrition_plan_widgets.dart';
import 'plan_meal_card.dart';

class NutritionPlanView extends StatelessWidget {
  const NutritionPlanView({
    required this.plan,
    required this.date,
    required this.authorized,
    required this.loading,
    required this.loaded,
    required this.onDate,
    required this.onRetry,
    required this.onRecordsRetry,
    required this.onInfo,
    required this.onReview,
    this.name,
    this.expert,
    this.error,
    this.records,
    this.mealError,
    this.onProfile,
    super.key,
  });
  final NutritionPlanResponse? plan;
  final DateTime date;
  final bool authorized, loading, loaded;
  final String? name, expert, error, mealError;
  final List<MealLog>? records;
  final ValueChanged<DateTime> onDate;
  final VoidCallback onRetry, onRecordsRetry, onInfo, onReview;
  final VoidCallback? onProfile;
  @override
  Widget build(BuildContext context) {
    final meals = dayPlanMeals(plan, date), p = plan;
    final today = DateTime.now();
    final isToday = DateUtils.isSameDay(date, today);
    final inPeriod = p != null && planContains(p, date);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 24),
              _hero(context),
              const SizedBox(height: 20),
              if (!authorized)
                const Text(
                  'Planını görüntülemek için oturumun doğrulanmalıdır.',
                )
              else if (loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Aktif program yükleniyor',
                )
              else if (error != null)
                PlanSurface(
                  child: Semantics(liveRegion: true, child: Text(error!)),
                )
              else if (p != null) ...[
                _summary(context, p),
                const SizedBox(height: 24),
                _week(context),
                const SizedBox(height: 23),
                Text(
                  planDate(date, year: false, weekday: true),
                  style: const TextStyle(
                    fontSize: 12,
                    color: OnboardingTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isToday ? 'Bugünkü öğünlerin' : 'Günün öğünleri',
                        style: OnboardingTheme.heading(
                          22,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: OnboardingTheme.soft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${meals.length} öğün',
                        style: const TextStyle(
                          color: Color(0xFF3D7756),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (!inPeriod)
                  PlanSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bu gün planının dışında.',
                          style: OnboardingTheme.heading(18),
                        ),
                        const SizedBox(height: 8),
                        Text(planPeriod(p), style: OnboardingTheme.hint),
                        TextButton(
                          onPressed: () => onDate(today),
                          child: const Text('Bugüne dön'),
                        ),
                      ],
                    ),
                  )
                else if (meals.isEmpty)
                  const PlanSurface(
                    child: Text('Bu gün için öğün önerisi bulunmuyor.'),
                  ),
                for (var i = 0; i < meals.length; i++) ...[
                  PlanMealCard(
                    key: ValueKey(
                      '${date.year}-${date.month}-${date.day}-${meals[i].first.mealType}',
                    ),
                    items: meals[i],
                    order: i + 1,
                    initiallyExpanded: meals[i].first.mealType == 'lunch',
                    recorded:
                        records?.any(
                          (r) => r.mealType == meals[i].first.mealType,
                        ) ==
                        true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (inPeriod && records == null && mealError == null)
                  const Text(
                    'Öğün kayıtların kontrol ediliyor…',
                    style: OnboardingTheme.hint,
                  ),
                if (mealError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(mealError!, style: OnboardingTheme.hint),
                      ),
                      TextButton(
                        onPressed: onRecordsRetry,
                        child: const Text('Tekrar yükle'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                if (p.dietitianId != null && inPeriod) _review(),
                const SizedBox(height: 18),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OnboardingIcon('sprout', size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Planın sana rehber olsun.\nTükettiğin öğünleri Günüm'den ayrıca kaydedebilirsin.",
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: OnboardingTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (loaded)
                const PlanSurface(
                  child: Text(
                    'Henüz aktif bir beslenme programınız bulunmuyor. Diyetisyeniniz programı etkinleştirdiğinde burada görebilirsiniz.',
                  ),
                ),
              if (authorized) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: loading ? null : onInfo,
                      child: const Text(
                        'Plan bilgisi ve işlemler',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: loading ? null : onRetry,
                      child: Text(
                        error == null ? 'Programı yenile' : 'Yeniden dene',
                        style: const TextStyle(fontSize: 12),
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
  }

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
        label: 'Hesabım',
        button: onProfile != null,
        child: Material(
          color: const Color(0xFFE1EDD3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onProfile,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 43,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    planInitials(name),
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
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PLANIM',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          plan == null ? 'Her adım,\nsana göre.' : 'Planın hazır,\nadım adım.',
          style: OnboardingTheme.heading(
            MediaQuery.sizeOf(context).width < 355 ? 29 : 33,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${planGivenName(name).isEmpty ? 'Bugün' : '${planGivenName(name)}, bugün'} de birlikte.',
          style: const TextStyle(fontSize: 14, color: OnboardingTheme.muted),
        ),
      ],
    );
    final mascot = TweenAnimationBuilder<double>(
      tween: Tween(
        begin: authorized && !MediaQuery.disableAnimationsOf(context)
            ? -.04
            : 0,
        end: 0,
      ),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, angle, child) =>
          Transform.rotate(angle: angle, child: child),
      child: LimelyMascot(
        size: large
            ? 95
            : MediaQuery.sizeOf(context).width < 355
            ? 111
            : 132,
        pose: 'goz-kirpma',
      ),
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
              SizedBox(
                width: 111,
                height: 141,
                child: OverflowBox(maxWidth: 132, child: mascot),
              ),
            ],
          );
  }

  Widget _summary(BuildContext context, NutritionPlanResponse p) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final targets = [
      _target(
        'utensils',
        'Günlük enerji hedefi',
        p.dailyCaloriesTargetKcal,
        'kcal',
      ),
      _target('glass-water', 'Günlük su hedefi', p.dailyWaterTargetMl, 'ml'),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OnboardingTheme.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -105,
            top: 50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x18C9E879)),
              ),
            ),
          ),
          Positioned(
            right: -65,
            top: 85,
            child: Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1483B977),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 19, 21, 18),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Figtree',
                color: OnboardingTheme.background,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.dietitianId == null
                              ? 'KİŞİSEL PLANIN'
                              : 'DİYETİSYEN PLANI',
                          style: const TextStyle(
                            fontSize: 10,
                            color: OnboardingTheme.lime,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x38C9E879)),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: OnboardingTheme.lime,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Aktif',
                              style: TextStyle(
                                fontSize: 10,
                                color: OnboardingTheme.lime,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16.5,
                        backgroundColor: OnboardingTheme.lime,
                        child: expert == null
                            ? OnboardingIcon(
                                p.dietitianId == null ? 'user-round' : 'leaf',
                                size: 18,
                              )
                            : Text(
                                planInitials(expert),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: OnboardingTheme.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.dietitianId == null
                                  ? 'Kendi oluşturduğun plan'
                                  : expert == null
                                  ? 'Diyetisyeninin hazırladığı plan'
                                  : '$expert hazırladı',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${planPeriod(p)} · Sürüm ${p.versionNumber}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFD2DECA),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onInfo,
                        tooltip: 'Planın hakkında',
                        style: IconButton.styleFrom(
                          side: const BorderSide(color: Color(0x2CF8FAF2)),
                        ),
                        icon: const PlanTintedIcon(
                          'chevron-right',
                          color: OnboardingTheme.background,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 14),
                    child: Divider(height: 1, color: Color(0x25F8FAF2)),
                  ),
                  if (large) ...[
                    targets[0],
                    const SizedBox(height: 14),
                    targets[1],
                  ] else
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: targets[0]),
                          const VerticalDivider(
                            width: 30,
                            color: Color(0x25F8FAF2),
                          ),
                          Expanded(child: targets[1]),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _target(String icon, String label, num? value, String unit) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          PlanTintedIcon(icon, color: OnboardingTheme.background, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFFD2DECA)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text.rich(
        TextSpan(
          text: value == null ? 'Belirlenmedi' : dayNumber(value),
          style: TextStyle(
            fontSize: value == null ? 14 : 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
          ),
          children: [
            if (value != null)
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFD2DECA),
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _week(BuildContext context) {
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Haftalık planın',
                    style: OnboardingTheme.heading(
                      20,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    planRange(
                      monday,
                      DateTime(monday.year, monday.month, monday.day + 6),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () =>
                  onDate(DateTime(date.year, date.month, date.day - 7)),
              tooltip: 'Önceki hafta',
              icon: const OnboardingIcon('chevron-left', size: 16),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: OnboardingTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  onDate(DateTime(date.year, date.month, date.day + 7)),
              tooltip: 'Sonraki hafta',
              icon: const OnboardingIcon('chevron-right', size: 16),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: OnboardingTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 7; i++)
                SizedBox(
                  width: large
                      ? (constraints.maxWidth - 18) / 4
                      : (constraints.maxWidth - 36) / 7,
                  child: _day(
                    DateTime(monday.year, monday.month, monday.day + i),
                    i,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _day(DateTime d, int index) {
    final selected = DateUtils.isSameDay(date, d),
        today = DateUtils.isSameDay(d, DateTime.now());
    return Semantics(
      label: planDate(d, weekday: true),
      selected: selected,
      child: Material(
        color: selected ? OnboardingTheme.lime : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? OnboardingTheme.selectedBorder
                : OnboardingTheme.border,
          ),
        ),
        child: InkWell(
          onTap: () => onDate(d),
          borderRadius: BorderRadius.circular(14),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                children: [
                  Text(
                    const [
                      'Pts',
                      'Sal',
                      'Çar',
                      'Per',
                      'Cum',
                      'Cts',
                      'Paz',
                    ][index],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? OnboardingTheme.ink
                          : OnboardingTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${d.day}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: today
                          ? const Color(0xFF3D7756)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _review() => PlanSurface(
    color: OnboardingTheme.soft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingIcon('notebook-pen', size: 27),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Planın ve kayıtların',
                    style: OnboardingTheme.heading(
                      18,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Önerilerini ve kaydettiğin öğünleri birlikte incele.',
                    style: TextStyle(
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
        const SizedBox(height: 13),
        OutlinedButton(
          onPressed: onReview,
          style: OutlinedButton.styleFrom(
            backgroundColor: OnboardingTheme.background,
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: OnboardingTheme.selectedBorder),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Plan ve tüketimimi karşılaştır',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              OnboardingIcon('chevron-right', size: 17),
            ],
          ),
        ),
      ],
    ),
  );
}
