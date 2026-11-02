import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';
import 'dietitian_application_info_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_outline_rounded,
      title: 'Kişisel alanınız',
      description:
          'Profil bilgileriniz ve gizlilik tercihleriniz burada yer alacak.',
      action: FilledButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/dietitian-application'),
            builder: (context) => const DietitianApplicationInfoPage(),
          ),
        ),
        child: const Text(
          'Diyetisyen Olarak Başvur',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
