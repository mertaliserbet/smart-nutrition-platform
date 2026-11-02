import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';
import '../../core/theme/app_tokens.dart';

class SessionStatusPage extends StatelessWidget {
  const SessionStatusPage({required this.session, super.key});
  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final busy = session.isBusy || session.phase == SessionPhase.checking;
    return AuthPageLayout(
      title: busy
          ? 'Oturumunuz kontrol ediliyor'
          : 'Oturum kontrolü tamamlanamadı',
      description: 'Hesabınız doğrulandıktan sonra devam edebilirsiniz.',
      icon: Icons.lock_outline_rounded,
      notice: 'Hesabınız doğrulanmadan kişisel alanınız açılmaz.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy)
            const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Oturum kontrol ediliyor',
              ),
            ),
          if (session.notice != null) AuthErrorNotice(message: session.notice!),
          if (!busy) ...[
            const SizedBox(height: AppTokens.spacingMedium),
            if (session.canRetry)
              FilledButton(
                onPressed: () => unawaited(session.refresh()),
                child: const Text('Tekrar dene'),
              ),
            TextButton(
              onPressed: () => unawaited(session.signOut()),
              child: const Text(
                'Oturumu temizle ve girişe dön',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
