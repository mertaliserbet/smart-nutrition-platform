import 'package:flutter/material.dart';

import '../home/day_widgets.dart';
import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';
import '../personal_nutrition_targets/target_progress.dart';

/// Presentation only: WaterSummaryCard owns the authenticated reads and writes.
class DayWaterCard extends StatelessWidget {
  const DayWaterCard({
    required this.authorized,
    required this.loading,
    required this.saving,
    required this.total,
    required this.target,
    required this.error,
    required this.onAdd,
    required this.onHistory,
    required this.onRetry,
    super.key,
  });
  final bool authorized, loading, saving;
  final num? total;
  final EffectiveNutritionTarget? target;
  final String? error;
  final VoidCallback? onAdd, onHistory;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final goal = target?.value;
    final knownGoal =
        target != null && !target!.loading && !target!.failed && goal != null;
    final ratio = knownGoal && total != null ? total! / goal : 0;
    final bottle = ratio >= 1
        ? 'dolu'
        : ratio >= .5
        ? 'yari'
        : 'az';
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Su molası', style: OnboardingTheme.heading(20)),
        const SizedBox(height: 5),
        if (loading)
          const Text('Yükleniyor…', style: TextStyle(fontSize: 13))
        else if (total != null)
          Text(
            '${dayNumber(total!)}${knownGoal ? ' / ${dayNumber(goal)}' : ''} ml',
            key: const ValueKey('day-water-total'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        if (total != null && knownGoal)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${dayNumber(total! / 250)} / ${dayNumber(goal / 250)} bardak · 250 ml/bardak',
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: OnboardingTheme.muted,
              ),
            ),
          ),
        if (target?.loading == true)
          const Text(
            'Hedef bilgisi yükleniyor…',
            style: TextStyle(fontSize: 12, color: OnboardingTheme.muted),
          ),
        if (target?.failed == true)
          const Text(
            'Hedef bilgisi alınamadı.',
            style: TextStyle(fontSize: 12, color: OnboardingTheme.muted),
          ),
        if (target != null &&
            !target!.loading &&
            !target!.failed &&
            goal == null)
          const Text(
            'Henüz hedef belirlenmedi',
            style: TextStyle(fontSize: 12, color: OnboardingTheme.muted),
          ),
        if (knownGoal)
          Text(
            target!.source ?? '',
            style: const TextStyle(fontSize: 11, color: OnboardingTheme.muted),
          ),
      ],
    );
    final add = OutlinedButton(
      key: const ValueKey('day-water-add'),
      onPressed: onAdd,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        side: const BorderSide(color: OnboardingTheme.ink, width: 1.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Su kaydediliyor',
              ),
            )
          : const Text(
              '+ 250 ml',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
    );
    return Material(
      color: OnboardingTheme.soft,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onHistory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final large =
                      MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                      constraints.maxWidth < 280;
                  final mascotWidth = constraints.maxWidth < 305 ? 52.0 : 72.0;
                  final mascot = SizedBox(
                    width: mascotWidth,
                    height: 88,
                    child: OverflowBox(
                      maxWidth: mascotWidth + 24,
                      maxHeight: 100,
                      child: LimelyMascot(
                        size: mascotWidth + 24,
                        pose: 'su-molasi',
                      ),
                    ),
                  );
                  final tools = Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!loading && total != null && knownGoal) ...[
                        Image.asset(
                          'assets/limely/bilesenler/su-sisesi-$bottle.png',
                          width: 24,
                          height: 58,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ],
                      add,
                    ],
                  );
                  if (large) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            mascot,
                            const SizedBox(width: 14),
                            Expanded(child: copy),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(alignment: Alignment.centerRight, child: tools),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      mascot,
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(left: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFFCCDDC0)),
                            ),
                          ),
                          child: copy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      tools,
                    ],
                  );
                },
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 9),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Su tüketimi yükleniyor',
                  ),
                ),
              if (!authorized)
                const Text(
                  'Su tüketimini görmek için oturumun doğrulanmalıdır.',
                  style: TextStyle(fontSize: 13, color: OnboardingTheme.muted),
                ),
              if (error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(error!, style: const TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: loading || saving ? null : onRetry,
                  child: const Text('Su bilgilerini yenile'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
