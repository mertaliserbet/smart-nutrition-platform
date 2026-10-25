import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class NutritionPage extends StatelessWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.restaurant_menu_rounded,
      title: 'Beslenme alanınız',
      description: 'Öğünleriniz ve beslenme programınız burada yer alacak.',
    );
  }
}
