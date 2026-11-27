import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../home/day_widgets.dart' show dayNumber;
import '../onboarding/onboarding_theme.dart';
import 'nutrition_plan_api.dart';
import 'nutrition_plan_widgets.dart';

class NutritionPlanInfo extends StatefulWidget {
  const NutritionPlanInfo({
    required this.plan,
    required this.expert,
    required this.owner,
    required this.onAction,
    super.key,
  });
  final NutritionPlanResponse? plan;
  final String? expert, owner;
  final ValueChanged<String> onAction;
  @override
  State<NutritionPlanInfo> createState() => _NutritionPlanInfoState();
}

class _NutritionPlanInfoState extends State<NutritionPlanInfo>
    with WidgetsBindingObserver {
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(() => _visible = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthSessionScope.maybeOf(context);
    final authorized =
        _visible &&
        session?.isAuthenticated == true &&
        session?.user?.id == widget.owner;
    final p = authorized ? widget.plan : null;
    return Theme(
      data: OnboardingTheme.data,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 23),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const PlanSheetHeader('Planın hakkında'),
                const SizedBox(height: 8),
                if (!authorized)
                  const Text('Bilgileri görüntülemek için planını yeniden aç.')
                else ...[
                  if (p != null) ...[
                    Text(
                      '${p.title}\nSana eşlik eden öğün önerilerin.',
                      style: OnboardingTheme.hint,
                    ),
                    const SizedBox(height: 20),
                    PlanSurface(
                      color: OnboardingTheme.soft,
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: OnboardingTheme.lime,
                            child: Text(
                              planInitials(widget.expert),
                              style: const TextStyle(
                                color: OnboardingTheme.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.dietitianId == null
                                      ? 'Kişisel planın'
                                      : widget.expert ?? 'Diyetisyenin',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.dietitianId == null
                                      ? 'Kendi oluşturduğun plan'
                                      : 'Planını hazırlayan diyetisyenin',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: OnboardingTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    _row('Başlangıç', planDate(DateTime.parse(p.startDate))),
                    _row(
                      'Bitiş',
                      p.endDate == null
                          ? 'Bitiş tarihi yok'
                          : planDate(DateTime.parse(p.endDate!)),
                    ),
                    _row(
                      'Günlük enerji hedefi',
                      p.dailyCaloriesTargetKcal == null
                          ? 'Belirlenmedi'
                          : '${dayNumber(p.dailyCaloriesTargetKcal!)} kcal',
                    ),
                    _row(
                      'Günlük su hedefi',
                      p.dailyWaterTargetMl == null
                          ? 'Belirlenmedi'
                          : '${dayNumber(p.dailyWaterTargetMl!)} ml',
                    ),
                    _row('Güncel sürüm', 'Sürüm ${p.versionNumber}'),
                    _row(
                      'Durum',
                      p.dietitianId == null
                          ? 'Aktif kişisel plan'
                          : 'Aktif diyetisyen planı',
                    ),
                    const SizedBox(height: 17),
                    Text(
                      p.dietitianId == null
                          ? 'Bu görünüm kişisel planını gösterir. Tüketim kayıtların planını değiştirmez.'
                          : 'Planın diyetisyeninin önerilerini gösterir. Tükettiğin öğünleri ayrıca kaydedebilirsin; bu kayıtlar planını değiştirmez.',
                      style: OnboardingTheme.hint,
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Planıma dön'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    children: [
                      for (final action in const {
                        'add': 'Öğün ekle',
                        'history': 'Öğün geçmişi',
                        'targets': 'Günlük hedeflerim',
                        'expert': 'Diyetisyen Bul',
                      }.entries)
                        TextButton(
                          onPressed: () => widget.onAction(action.key),
                          child: Text(
                            action.value,
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
      ),
    );
  }

  Widget _row(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 13, color: OnboardingTheme.muted),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
