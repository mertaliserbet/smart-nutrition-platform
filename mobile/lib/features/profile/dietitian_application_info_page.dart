import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/web_config.dart';
import '../../core/theme/app_tokens.dart';

class DietitianApplicationInfoPage extends StatefulWidget {
  const DietitianApplicationInfoPage({this.webBaseUrl, super.key});

  final String? webBaseUrl;

  @override
  State<DietitianApplicationInfoPage> createState() =>
      _DietitianApplicationInfoPageState();
}

class _DietitianApplicationInfoPageState
    extends State<DietitianApplicationInfoPage> {
  bool _busy = false;

  void _feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Uri uri) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _feedback(
          'Tarayıcı açılamadı. Adresi kopyalayıp tarayıcınıza yapıştırabilirsiniz.',
        );
      }
    } catch (_) {
      _feedback(
        'Tarayıcı açılamadı. Adresi kopyalayıp tarayıcınıza yapıştırabilirsiniz.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(Uri uri) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      _feedback('Adres kopyalandı.');
    } catch (_) {
      _feedback(
        'Adres kopyalanamadı. Ekrandaki adresi kullanarak tekrar deneyebilirsiniz.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Uri? uri;
    try {
      uri = WebConfig.dietitianApplicationUri(baseUrl: widget.webBaseUrl);
    } on FormatException {
      // Missing release configuration must never launch an invented public URL.
    }
    final destination = uri;
    return Scaffold(
      appBar: AppBar(title: const Text('Diyetisyen başvurusu')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.spacingLarge),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spacingLarge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusMedium,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(
                              AppTokens.spacingMedium,
                            ),
                            child: Icon(
                              Icons.school_outlined,
                              size: AppTokens.brandIconSize,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      Semantics(
                        header: true,
                        child: Text(
                          'Smart Nutrition Platform',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      Text(
                        'Uzmanlığınızla beslenme yolculuklarına eşlik edin.',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      const Text(
                        'Diyetisyen başvurunuzu web sitemiz üzerinden tamamlayabilirsiniz. Başvuru sayfası telefonunuzun varsayılan tarayıcısında açılır.',
                      ),
                      const SizedBox(height: AppTokens.spacingMedium),
                      const Text(
                        'Başvurunuzun kabulü e-posta doğrulaması ve Admin incelemesiyle verilen onayı gerektirir. Başvuru yapmak tek başına diyetisyen yetkisi vermez.',
                      ),
                      const SizedBox(height: AppTokens.spacingMedium),
                      Text(
                        'Web oturumu bağımsızdır. Giriş gerekirse web sitesindeki giriş akışını kullanın; mobil oturumunuz otomatik aktarılmaz.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      Text(
                        'İnternet sitesi',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      if (destination != null)
                        SelectableText(
                          destination.toString(),
                          style: theme.textTheme.bodyLarge,
                        )
                      else
                        const Text(
                          'Web adresi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.',
                        ),
                      const SizedBox(height: AppTokens.spacingLarge),
                      FilledButton(
                        onPressed: _busy || destination == null
                            ? null
                            : () => _open(destination),
                        child: const Text(
                          'Web Sitesine Git',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSmall),
                      OutlinedButton(
                        onPressed: _busy || destination == null
                            ? null
                            : () => _copy(destination),
                        child: const Text(
                          'Adresi Kopyala',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (_busy) ...[
                        const SizedBox(height: AppTokens.spacingMedium),
                        const LinearProgressIndicator(
                          semanticsLabel: 'İşlem sürüyor',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
