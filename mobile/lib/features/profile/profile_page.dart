import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_outline_rounded,
      title: 'Kişisel alanınız',
      description:
          'Profil bilgileriniz ve gizlilik tercihleriniz burada yer alacak.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/dietitians'),
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Diyetisyen Bul', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pushNamed('/dietitian-account'),
            child: const Text(
              'Diyetisyen Profili ve Başvuru',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
