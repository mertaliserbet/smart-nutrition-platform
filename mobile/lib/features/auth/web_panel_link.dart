import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/web_config.dart';
import 'auth_session.dart';
import 'auth_widgets.dart';

class WebPanelLink extends StatefulWidget {
  const WebPanelLink({
    this.enabled = true,
    this.webBaseUrl,
    this.onOpening,
    super.key,
  });
  final bool enabled;
  final String? webBaseUrl;
  final VoidCallback? onOpening;
  @override
  State<WebPanelLink> createState() => _WebPanelLinkState();
}

class _WebPanelLinkState extends State<WebPanelLink> {
  bool _opening = false;
  String? _error;
  Future<void> _open(Uri uri) async {
    if (_opening || !widget.enabled) return;
    widget.onOpening?.call();
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(
          () => _error =
              'Tarayıcı açılamadı. Web adresini kopyalayıp tarayıcınıza yapıştırabilirsiniz.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Tarayıcı açılamadı. Web adresini kopyalayıp tarayıcınıza yapıştırabilirsiniz.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _copy(Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Adres kopyalandı.')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Adres kopyalanamadı. Ekrandaki web adresini kullanabilirsiniz.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Uri? uri;
    try {
      uri = WebConfig.loginUri(baseUrl: widget.webBaseUrl);
    } on FormatException {
      /* No invented production URL. */
    }
    if (uri == null) {
      return const Text(
        'Diyetisyen web adresi şu anda kullanılamıyor.',
        textAlign: TextAlign.center,
      );
    }
    final destination = uri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          onPressed: widget.enabled && !_opening
              ? () => _open(destination)
              : null,
          child: Text(
            'Diyetisyen misiniz? Web paneline gidin\n$destination',
            textAlign: TextAlign.center,
          ),
        ),
        if (_opening)
          const LinearProgressIndicator(semanticsLabel: 'Web paneli açılıyor'),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(_error!, textAlign: TextAlign.center),
          ),
          TextButton(
            onPressed: widget.enabled && !_opening
                ? () => _copy(destination)
                : null,
            child: const Text('Web adresini kopyala'),
          ),
        ],
      ],
    );
  }
}

/// Professional mobile sessions see only a handoff; no mobile expert workspace.
class WebPanelPage extends StatelessWidget {
  const WebPanelPage({this.showSignOut = false, super.key});
  final bool showSignOut;
  @override
  Widget build(BuildContext context) {
    final session = AuthSessionScope.maybeOf(context);
    return AuthPageLayout(
      title: 'Diyetisyen ve yönetici web paneli',
      description:
          'Diyetisyen ve yönetici işlemleri için web panelini kullanın.',
      notice:
          'Mobil uygulama danışan kullanımı içindir. Web sitesinde ayrıca giriş yapmanız gerekir.',
      icon: Icons.open_in_browser,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WebPanelLink(),
          if (showSignOut && session != null)
            OutlinedButton(
              onPressed: session.isBlocking ? null : () => session.signOut(),
              child: const Text('Mobil giriş ekranına dön'),
            ),
        ],
      ),
    );
  }
}
