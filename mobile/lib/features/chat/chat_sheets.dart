import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../onboarding/onboarding_theme.dart';
import 'chat_view.dart' show chatGivenName, chatInitials;

class ChatSheet extends StatefulWidget {
  const ChatSheet({
    required this.attachment,
    required this.session,
    required this.owner,
    this.expert,
    super.key,
  });
  final bool attachment;
  final AuthSession session;
  final String? owner, expert;
  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> with WidgetsBindingObserver {
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(() => _visible = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthSessionScope.maybeOf(context);
    final authorized =
        _visible &&
        identical(session, widget.session) &&
        session?.isAuthenticated == true &&
        session?.user?.id == widget.owner;
    final name = chatGivenName(widget.expert);
    return Theme(
      data: OnboardingTheme.data,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(21, 11, 21, 23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9D3C1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.attachment
                            ? 'Sohbetine ekle'
                            : '${authorized && name.isNotEmpty ? name : 'Diyetisyenin'} ile sohbetin',
                        style: OnboardingTheme.heading(24),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: widget.attachment
                          ? 'Dosya paylaşımını kapat'
                          : 'Sohbet bilgisini kapat',
                      style: IconButton.styleFrom(
                        backgroundColor: OnboardingTheme.soft,
                      ),
                      icon: const OnboardingIcon('x', size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!authorized)
                  const Text(
                    'Bilgileri görüntülemek için Sohbet ekranını yeniden aç.',
                    style: OnboardingTheme.hint,
                  )
                else if (widget.attachment) ...[
                  const Text(
                    'Konuşmak istediğin dosyayı mesajına ekle.',
                    style: OnboardingTheme.hint,
                  ),
                  const SizedBox(height: 19),
                  _action('file', 'Dosya seç', 'Cihazından bir dosya seç.'),
                  const SizedBox(height: 10),
                  _action(
                    'clipboard-list',
                    'Planımdan paylaş',
                    'Güncel planını konuşmaya ekle.',
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Dosya paylaşımı henüz kullanıma açık değil.',
                    style: OnboardingTheme.hint,
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    decoration: BoxDecoration(
                      color: OnboardingTheme.soft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 21.5,
                          backgroundColor: OnboardingTheme.lime,
                          child: widget.expert == null
                              ? const OnboardingIcon('user-round', size: 22)
                              : Text(
                                  chatInitials(widget.expert),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: OnboardingTheme.ink,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.expert ?? 'Diyetisyenin',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Diyetisyenin',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: OnboardingTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Planınla ilgili soruların ve günlük deneyimlerin için iletişim alanın.',
                    style: OnboardingTheme.hint,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Mesaj gönderimi henüz kullanıma açık değil.',
                    style: OnboardingTheme.hint,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 51),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Sohbete dön'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(String icon, String title, String description) => Semantics(
    button: true,
    enabled: false,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: OnboardingTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            OnboardingIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const OnboardingIcon('chevron-right', size: 16),
          ],
        ),
      ),
    ),
  );
}
