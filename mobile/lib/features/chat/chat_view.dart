import 'package:flutter/material.dart';
import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';

String chatInitials(String? name) => name == null || name.trim().isEmpty
    ? '?'
    : name
          .trim()
          .split(RegExp(r'\s+'))
          .take(2)
          .map(
            (part) => part.characters.first.replaceAll('i', 'İ').toUpperCase(),
          )
          .join();
String chatGivenName(String? name) {
  final parts =
      name?.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList() ??
      [];
  return (parts.length > 1 ? parts.take(parts.length - 1) : parts).join(' ');
}

class ChatView extends StatelessWidget {
  const ChatView({
    required this.authorized,
    required this.loading,
    required this.loaded,
    required this.connected,
    required this.draft,
    required this.focus,
    required this.scroll,
    required this.onRetry,
    required this.onConnect,
    required this.onPrompt,
    required this.onInfo,
    required this.onAttach,
    this.onProfile,
    this.name,
    this.expert,
    this.error,
    this.transcript = const [],
    this.dayLabel,
    super.key,
  });
  final bool authorized, loading, loaded, connected;
  final String? name, expert, error, dayLabel;
  final TextEditingController draft;
  final FocusNode focus;
  final ScrollController scroll;
  final Future<void> Function() onRetry;
  final VoidCallback onConnect, onInfo, onAttach;
  final ValueChanged<String> onPrompt;
  final VoidCallback? onProfile;
  // Presentation slots, not API records. The page has no thread datasource yet.
  final List<Widget> transcript;
  @override
  Widget build(BuildContext context) {
    final ready = authorized && !loading && error == null && connected;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRetry,
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 21),
                        _hero(context),
                        const SizedBox(height: 17),
                        if (!authorized)
                          const Text(
                            'Sohbeti görüntülemek için oturumun doğrulanmalıdır.',
                          )
                        else if (loading)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Diyetisyen bağlantın yükleniyor',
                          )
                        else if (error != null)
                          _status(error!, retry: true)
                        else if (loaded && !connected)
                          _noConnection()
                        else if (connected) ...[
                          _expert(),
                          if (transcript.isEmpty)
                            _empty()
                          else ...[
                            const SizedBox(height: 20),
                            if (dayLabel != null)
                              Row(
                                children: [
                                  const Expanded(
                                    child: Divider(
                                      color: OnboardingTheme.border,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      dayLabel!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: OnboardingTheme.muted,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    child: Divider(
                                      color: OnboardingTheme.border,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 19),
                            for (final bubble in transcript) ...[
                              bubble,
                              const SizedBox(height: 13),
                            ],
                            _prompts(first: false),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _composer(ready),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            'assets/limely/logolar/limely-yazili-logo-renkli.png',
            width: 151,
            height: 54,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Limely',
          ),
        ),
      ),
      const Tooltip(
        message: 'Bildirimler henüz kullanıma açık değil',
        child: SizedBox.square(
          dimension: 44,
          child: Center(child: OnboardingIcon('bell', size: 25)),
        ),
      ),
      const SizedBox(width: 12),
      Semantics(
        label: 'Hesabım',
        button: onProfile != null,
        child: Material(
          color: const Color(0xFFE1EDD3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onProfile,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 43,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    chatInitials(name),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _hero(BuildContext context) {
    final user = chatGivenName(name), professional = chatGivenName(expert);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SOHBET',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Bir mesaj,\nbir adım.',
          style: OnboardingTheme.heading(
            MediaQuery.sizeOf(context).width < 355 ? 28 : 32,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          '${user.isEmpty ? '' : '$user, '}${professional.isEmpty ? 'aklındakileri diyetisyeninle paylaş.' : 'aklındakileri $professional ile paylaş.'}',
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: OnboardingTheme.muted,
          ),
        ),
      ],
    );
    final mascot = TweenAnimationBuilder<double>(
      tween: Tween(
        begin: MediaQuery.disableAnimationsOf(context) ? 0 : -.04,
        end: .03,
      ),
      duration: const Duration(milliseconds: 900),
      builder: (context, angle, child) => Transform.rotate(
        angle: MediaQuery.disableAnimationsOf(context) ? .03 : angle,
        child: child,
      ),
      child: const LimelyMascot(size: 107, pose: 'goz-kirpma'),
    );
    return large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: mascot),
            ],
          )
        : Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 5),
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 355 ? 90 : 107,
                child: mascot,
              ),
            ],
          );
  }

  Widget _expert() => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: const BorderSide(color: OnboardingTheme.border),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Row(
        children: [
          _expertAvatar(),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expert ?? 'Diyetisyenin',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Diyetisyenin · Birlikte, adım adım.',
                  style: TextStyle(fontSize: 11, color: OnboardingTheme.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onInfo,
            tooltip: 'Sohbet bilgisini aç',
            icon: const OnboardingIcon('info', size: 21),
          ),
        ],
      ),
    ),
  );
  Widget _expertAvatar() => CircleAvatar(
    radius: 21.5,
    backgroundColor: OnboardingTheme.lime,
    child: expert == null
        ? const OnboardingIcon('user-round', size: 22)
        : Text(
            chatInitials(expert),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: OnboardingTheme.ink,
            ),
          ),
  );
  Widget _empty() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
    child: Column(
      children: [
        SizedBox.square(
          dimension: 154,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: OnboardingTheme.soft,
                ),
                alignment: Alignment.center,
                child: const LimelyMascot(size: 146),
              ),
              Positioned(
                right: -5,
                top: 7,
                child: Transform.rotate(
                  angle: .14,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: OnboardingTheme.border),
                    ),
                    child: const OnboardingIcon('message-circle', size: 21),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Text(
          'İlk adım, bir merhaba.',
          textAlign: TextAlign.center,
          style: OnboardingTheme.heading(24),
        ),
        const SizedBox(height: 10),
        Text(
          '${chatGivenName(expert).isEmpty ? 'Diyetisyenin' : chatGivenName(expert)} ile gününü konuş, aklına takılanları sor.\nBu yolculukta birlikte ilerliyorsunuz.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.65,
            color: OnboardingTheme.muted,
          ),
        ),
        const SizedBox(height: 22),
        _prompts(first: true),
      ],
    ),
  );
  Widget _prompts({required bool first}) => Wrap(
    alignment: first ? WrapAlignment.center : WrapAlignment.start,
    spacing: 7,
    runSpacing: 7,
    children: [
      _prompt(
        first ? 'Merhaba diyelim' : 'Planımla ilgili',
        first
            ? 'Merhaba${chatGivenName(expert).isEmpty ? '' : ' ${chatGivenName(expert)}'}, nasılsın?'
            : 'Planımla ilgili bir sorum var.',
      ),
      _prompt(
        first ? 'Planımı konuşalım' : 'Öğünümle ilgili',
        first
            ? 'Planımla ilgili bir sorum var.'
            : 'Öğünümle ilgili konuşmak istiyorum.',
      ),
    ],
  );
  Widget _prompt(String label, String value) => OutlinedButton(
    onPressed: () => onPrompt(value),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      backgroundColor: const Color(0xFFF1F6E9),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      side: const BorderSide(color: Color(0xFFD9E4CE)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, height: 1.3)),
  );
  Widget _noConnection() => _status(
    'Diyetisyen bağlantın henüz yok. Bağlantı kurduğunda diyetisyenin burada görünecek.',
    connect: true,
  );
  Widget _status(String value, {bool retry = false, bool connect = false}) =>
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: OnboardingTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(value, style: OnboardingTheme.hint),
            ),
            if (retry)
              TextButton(onPressed: onRetry, child: const Text('Yeniden dene')),
            if (connect)
              TextButton(
                onPressed: onConnect,
                child: const Text('Diyetisyen bul'),
              ),
          ],
        ),
      );
  Widget _composer(bool ready) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
    decoration: const BoxDecoration(
      color: OnboardingTheme.background,
      border: Border(top: BorderSide(color: OnboardingTheme.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ready)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Mesaj gönderimi henüz kullanıma açık değil.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: OnboardingTheme.muted),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: ready ? onAttach : null,
              tooltip: 'Dosya ekle',
              style: IconButton.styleFrom(
                backgroundColor: OnboardingTheme.soft,
                minimumSize: const Size(42, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const OnboardingIcon('plus', size: 21),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: 'Gönderilmeyen mesaj taslağı',
                child: TextField(
                  controller: draft,
                  focusNode: focus,
                  enabled: ready,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, height: 1.65),
                  decoration: InputDecoration(
                    hintText:
                        '${chatGivenName(expert).isEmpty ? 'Diyetisyenine' : '${chatGivenName(expert)} için'} bir mesaj yaz…',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFD7E0D0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFD7E0D0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: OnboardingTheme.ink),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Mesaj gönderimi henüz kullanıma açık değil',
              child: IconButton(
                onPressed: null,
                tooltip: 'Mesajı gönder',
                style: IconButton.styleFrom(
                  disabledBackgroundColor: OnboardingTheme.ink.withValues(
                    alpha: .42,
                  ),
                  minimumSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Image.asset(
                  'assets/limely/ikonlar/beyaz/send.png',
                  width: 22,
                  height: 22,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Approved bubble layout, independent of any unapproved transport/model.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.own,
    required this.author,
    required this.text,
    required this.time,
    this.attachment,
    super.key,
  });
  final bool own;
  final String author, text, time;
  final Widget? attachment;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$author · $time',
    child: Padding(
      padding: EdgeInsets.only(left: own ? 34 : 0, right: own ? 0 : 27),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!own) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 12.5,
                backgroundColor: const Color(0xFFE1EDD3),
                child: Text(
                  chatInitials(author),
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: OnboardingTheme.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: own
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: own ? OnboardingTheme.lime : Colors.white,
                    border: Border.all(
                      color: own
                          ? const Color(0xFFBFDC88)
                          : OnboardingTheme.border,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(own ? 18 : 5),
                      bottomRight: Radius.circular(own ? 5 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (text.isNotEmpty)
                        Text(
                          text,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      if (attachment != null) ...[
                        if (text.isNotEmpty) const SizedBox(height: 10),
                        attachment!,
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(3, 5, 3, 0),
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 9,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ChatFileCard extends StatelessWidget {
  const ChatFileCard({
    required this.name,
    required this.description,
    this.onOpen,
    super.key,
  });
  final String name, description;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Material(
    color: OnboardingTheme.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: OnboardingTheme.border),
    ),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        label: '$name dosyasını görüntüle',
        button: true,
        enabled: onOpen != null,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OnboardingTheme.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const OnboardingIcon('file', size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.4,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const OnboardingIcon('chevron-right', size: 16),
            ],
          ),
        ),
      ),
    ),
  );
}
