import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.insights_outlined,
      title: 'Gelişiminizi takip edin',
      description:
          'Ölçüm geçmişiniz ve gelişim grafikleriniz burada yer alacak.',
    );
  }
}
