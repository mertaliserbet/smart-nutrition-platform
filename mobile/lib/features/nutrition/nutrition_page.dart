import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/empty_state.dart';
import 'manual_meal_log_page.dart';

class NutritionPage extends StatelessWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.restaurant_menu_rounded,
      title: 'Beslenme alanınız',
      description: 'Öğünleriniz ve beslenme programınız burada yer alacak.',
      action: Column(
        children: [
          const Text(
            'Öğün listesi henüz kullanıma açık değil. Manuel giriş ekranını inceleyebilirsiniz.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.spacingMedium),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const ManualMealLogPage(),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Öğün ekle'),
          ),
        ],
      ),
    );
  }
}
