import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';
import '../auth/auth_session.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthSessionScope.maybeOf(context)?.user;
    return EmptyState(
      icon: Icons.person_outline_rounded,
      title: 'Kişisel alanınız',
      description:
          'Profil bilgileriniz ve gizlilik tercihleriniz burada yer alacak.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null) ...[
            if (user.displayName != null)
              Text(user.displayName!, textAlign: TextAlign.center),
            Text(user.email, textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/dietitians'),
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Diyetisyen Bul', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
