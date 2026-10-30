import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'auth_widgets.dart';

class EmailVerificationPage extends StatelessWidget {
  const EmailVerificationPage({this.email, super.key});

  // Presentation context only; this does not prove registration or delivery.
  final String? email;

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
          if (email != null) ...[
            const Text('E-posta adresi'),
            const SizedBox(height: AppTokens.spacingSmall),
            Text(email!, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTokens.spacingLarge),
          ],
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
