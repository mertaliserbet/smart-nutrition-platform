import 'package:flutter/material.dart';
import '../onboarding/onboarding_theme.dart';
import 'nutrition_plan_api.dart';
import 'nutrition_plan_widgets.dart';

class PlanMealCard extends StatefulWidget {
  const PlanMealCard({
    required this.items,
    required this.order,
    required this.recorded,
    this.initiallyExpanded = false,
    super.key,
  });
  final List<NutritionPlanItem> items;
  final int order;
  final bool recorded, initiallyExpanded;
  @override
  State<PlanMealCard> createState() => _PlanMealCardState();
}

class _PlanMealCardState extends State<PlanMealCard> {
  late bool _expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) {
    final type = widget.items.first.mealType;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final alternatives = <String, List<NutritionPlanItem>>{};
    for (final item in widget.items) {
      if (item.alternativeGroupId != null) {
        alternatives.putIfAbsent(item.alternativeGroupId!, () => []).add(item);
      }
    }
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.order.toString().padLeft(2, '0')} · ÖĞÜN ÖNERİSİ',
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: .6,
            color: OnboardingTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 7,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              nutritionMealLabels[type]!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (widget.recorded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: OnboardingTheme.soft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OnboardingIcon('check', size: 12),
                    SizedBox(width: 3),
                    Text(
                      'Kayıt var',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF3D7756),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          widget.items
                  .where((i) => i.alternativeGroupId == null)
                  .map((i) => i.description)
                  .join(', ')
                  .isEmpty
              ? 'Porsiyon alternatiflerini incele'
              : widget.items
                    .where((i) => i.alternativeGroupId == null)
                    .map((i) => i.description)
                    .join(', '),
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: OnboardingTheme.muted,
          ),
          maxLines: _expanded || large ? null : 2,
          overflow: _expanded || large ? null : TextOverflow.ellipsis,
        ),
      ],
    );
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(21),
        side: BorderSide(
          color: _expanded ? const Color(0xFFBCD3AA) : OnboardingTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!large) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: SizedBox.square(
                          dimension: MediaQuery.sizeOf(context).width < 355
                              ? 58
                              : 68,
                          child: switch (type) {
                            'breakfast' => Image.asset(
                              'assets/limely/gorseller/breakfast-bowl.webp',
                              fit: BoxFit.cover,
                              semanticLabel: 'Örnek kahvaltı sunumu',
                            ),
                            'lunch' => Image.asset(
                              'assets/limely/gorseller/balanced-plate.webp',
                              fit: BoxFit.cover,
                              semanticLabel: 'Örnek öğle yemeği sunumu',
                            ),
                            _ => ColoredBox(
                              color: type == 'snack'
                                  ? const Color(0xFFFFF7D6)
                                  : OnboardingTheme.soft,
                              child: Center(
                                child: OnboardingIcon(
                                  type == 'snack' ? 'leaf' : 'salad',
                                  size: 31,
                                ),
                              ),
                            ),
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: title),
                    const SizedBox(width: 6),
                    RotatedBox(
                      quarterTurns: _expanded ? 2 : 0,
                      child: const OnboardingIcon('chevron-down', size: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 0, 17, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: OnboardingTheme.border),
                  const SizedBox(height: 14),
                  const Text(
                    'PLANINDAKİ PORSİYONLAR',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w600,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                  for (final item in widget.items.where(
                    (i) => i.alternativeGroupId == null,
                  ))
                    _portion(item),
                  for (final group in alternatives.values)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: PlanSurface(
                        color: const Color(0xFFF4F7ED),
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: OnboardingTheme.data.copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 11,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              12,
                            ),
                            leading: const OnboardingIcon(
                              'rotate-ccw',
                              size: 15,
                            ),
                            title: Text(
                              '${group.length} porsiyon alternatifi',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: const OnboardingIcon(
                              'chevron-down',
                              size: 15,
                            ),
                            children: [
                              const Text(
                                'Bu seçeneklerden biri, öğününün yanında.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: OnboardingTheme.muted,
                                ),
                              ),
                              for (var i = 0; i < group.length; i++) ...[
                                if (i > 0)
                                  const Text(
                                    'veya',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: OnboardingTheme.muted,
                                    ),
                                  ),
                                _portion(group[i]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (widget.recorded)
                    const Padding(
                      padding: EdgeInsets.only(top: 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OnboardingIcon('info', size: 14),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Bu öğün türünde kaydın var. Tüketim ayrıntıların kayıtlarında.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                color: OnboardingTheme.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _portion(NutritionPlanItem item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, c) {
        final name = Text(
          item.description,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        );
        final amount = Text(
          item.recommendedQuantity ?? 'Miktar belirtilmemiş',
          style: const TextStyle(fontSize: 11, color: OnboardingTheme.muted),
        );
        return MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [name, const SizedBox(height: 4), amount],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: name),
                  const SizedBox(width: 12),
                  Flexible(flex: 2, child: amount),
                ],
              );
      },
    ),
  );
}
