import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.person_outline_rounded,
      title: 'Kişisel alanınız',
      description:
          'Profil bilgileriniz ve gizlilik tercihleriniz burada yer alacak.',
    );
  }
}
