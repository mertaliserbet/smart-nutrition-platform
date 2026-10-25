import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_widgets.dart';

class EmailVerificationPage extends StatelessWidget {
  const EmailVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthPageLayout(
      title: 'E-posta adresinizi doğrulayın',
      description: 'Adres doğrulama, hesabınızın güvenliği için bir adımdır.',
      icon: Icons.mark_email_unread_outlined,
      footer: TextButton(
        onPressed: Navigator.of(context).canPop()
            ? () => Navigator.pop(context)
            : null,
        child: const Text('Önceki ekrana dön', textAlign: TextAlign.center),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Doğrulama nasıl çalışır?', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppTokens.spacingMedium),
          const Text(
            'Hesap oluşturma tamamlandığında, e-posta adresinize iletilen bağlantı üzerinden adresinizi doğrulayabilirsiniz.',
          ),
          const SizedBox(height: AppTokens.spacingMedium),
          const Text(
            'Bağlantıyı bulamazsanız gelen kutunuzu ve istenmeyen posta klasörünü kontrol edebilirsiniz.',
          ),
          const SizedBox(height: AppTokens.spacingLarge),
          const Text(
            'Bu önizlemede doğrulama e-postası gönderilmez ve adres doğrulanmaz.',
          ),
        ],
      ),
    );
  }
}
