import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'device_health_reader.dart';

class DeviceHealthPage extends StatefulWidget {
  const DeviceHealthPage({this.reader, this.now = DateTime.now, super.key});
  final DeviceHealthReader? reader;
  final DateTime Function() now;

  @override
  State<DeviceHealthPage> createState() => _DeviceHealthPageState();
}

class _DeviceHealthPageState extends State<DeviceHealthPage>
    with WidgetsBindingObserver {
  late final _reader = widget.reader ?? DeviceHealthReader();
  AuthSession? _session;
  String? _owner, _message;
  DeviceHealthAvailability? _availability;
  Map<DeviceHealthMetric, DeviceHealthReading>? _readings;
  DateTime? _readAt;
  bool _changedOwner = false, _busy = false;
  int _revision = 0;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _authorized =>
      !_changedOwner &&
      _foreground &&
      _owner != null &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  bool _current(int revision) =>
      mounted && revision == _revision && _authorized;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context);
    if (_session != null &&
        (!identical(session, _session) || session?.user?.id != _owner)) {
      ++_revision;
      _changedOwner = true;
      _readings = null;
      _readAt = null;
      _message = null;
    }
    _session = session;
    _owner ??= session?.user?.id;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        ++_revision;
        _readings = null;
        _readAt = null;
        _message = null;
      }
    });
    // Permission/settings screens can suspend the app. Returning never reads
    // automatically; the user must explicitly request another foreground read.
  }

  @override
  void dispose() {
    ++_revision;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run({bool permissions = false, bool install = false}) async {
    if (!_authorized || _busy) return;
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _readings = null;
      _readAt = null;
      _message = null;
    });
    try {
      final available = await _reader.source.availability();
      if (!_current(revision)) return;
      setState(() => _availability = available);
      if (available != DeviceHealthAvailability.available) {
        if (install && available == DeviceHealthAvailability.installRequired) {
          await _reader.source.install();
        }
        return;
      }
      if (permissions) {
        await _reader.requestPermissions(isCurrent: () => _current(revision));
        if (_current(revision)) {
          setState(
            () => _message =
                'İzin isteği tamamlandı. Açık izinlerle okumak için '
                '“Bugünün verilerini oku” düğmesine dokunun.',
          );
        }
        return;
      }
      final now = widget.now();
      final from = DateTime(now.year, now.month, now.day);
      if (!from.isBefore(now)) {
        setState(() => _message = 'Bugün için henüz okuma aralığı oluşmadı.');
        return;
      }
      final readings = await _reader.read(
        from: from,
        to: now,
        isCurrent: () => _current(revision),
      );
      if (!_current(revision)) return;
      setState(() {
        _readings = readings;
        _readAt = now;
      });
    } on HealthReadCancelled {
      // Discard results after logout/account change/app suspension.
    } catch (_) {
      if (_current(revision)) {
        setState(
          () => _message =
              'Sağlık verilerine erişilemedi. Cihaz izinlerini kontrol edip '
              'yeniden deneyin.',
        );
      }
    } finally {
      // Keep the lock until the native permission dialog actually finishes.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihaz sağlık verileri')),
      body: !_authorized
          ? const Center(
              child: Text('Bu ekranı mevcut hesabınızla yeniden açın.'),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Health Connect / Apple Sağlık',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Adım, mesafe, egzersiz, aktif kalori ve varsa nabız '
                  'kayıtları yalnız izninizle cihazdan okunur. Sağlık verisi '
                  'yazılmaz ve sunucuya gönderilmez. Bu aşamada yalnız '
                  'cihazın yerel saatine göre bugün başlayan kayıtlar okunur.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cihazdaki sağlık deposu telefonun kullanıcısına aittir. '
                  'Ortak cihaz kullanıyorsanız bu verilerin size ait olduğundan '
                  'emin olun. İzinler uygulama hesabından bağımsızdır.',
                ),
                const SizedBox(height: 8),
                Text(
                  _reader.source.isIOS
                      ? 'İzinleri Apple Sağlık uygulamasından yönetebilirsiniz. '
                            'Apple, okuma izninin reddedilip reddedilmediğini bildirmez.'
                      : 'İzinleri cihaz ayarlarında Health Connect > Uygulama '
                            'izinleri bölümünden değiştirebilir veya geri alabilirsiniz.',
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(permissions: true),
                  child: const Text('Okuma izinlerini iste'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(),
                  child: const Text('Bugünün verilerini oku'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                  const Text('Cihaz yanıtı bekleniyor…'),
                ],
                if (_availability == DeviceHealthAvailability.unsupported)
                  const Text('Bu cihazda sağlık verisi okuma desteklenmiyor.'),
                if (_availability ==
                    DeviceHealthAvailability.installRequired) ...[
                  const Text('Health Connect kurulmalı veya güncellenmeli.'),
                  TextButton(
                    onPressed: _busy ? null : () => _run(install: true),
                    child: const Text('Health Connect kur / güncelle'),
                  ),
                ],
                if (_message != null) Text(_message!),
                if (_readAt == null &&
                    !_busy &&
                    _message == null &&
                    _availability == null)
                  const Text('Henüz cihazdan veri okunmadı.'),
                if (_readAt != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Son yerel okuma: ${_readAt!.day}.${_readAt!.month}.'
                    '${_readAt!.year} '
                    '${TimeOfDay.fromDateTime(_readAt!).format(context)}',
                  ),
                  const Text(
                    'Kaynak kayıtlarıdır; farklı cihaz ve uygulamaların '
                    'kayıtları çakışabileceğinden günlük toplam oluşturulmaz.',
                  ),
                  for (final metric in DeviceHealthMetric.values)
                    _readingCard(metric, _readings![metric]!),
                ],
              ],
            ),
    );
  }

  Widget _readingCard(DeviceHealthMetric metric, DeviceHealthReading reading) {
    final message = switch (reading.state) {
      DeviceHealthReadState.data => '${reading.samples.length} kaynak kaydı',
      DeviceHealthReadState.empty =>
        _reader.source.isIOS
            ? 'Veri yok veya okuma izni kapalı.'
            : 'Bugün için kayıt bulunamadı.',
      DeviceHealthReadState.denied => 'Okuma izni verilmedi veya geri alındı.',
      DeviceHealthReadState.unavailable => 'Bu veri türü desteklenmiyor.',
      DeviceHealthReadState.error => 'Veri okunamadı. Yeniden deneyin.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(message),
            if (reading.samples.isNotEmpty) ...[
              const Text('Son kaynak kayıtları (en fazla 5):'),
              for (final sample in reading.samples.reversed.take(5))
                Text(
                  '${TimeOfDay.fromDateTime(sample.start.toLocal()).format(context)}'
                  ' · ${sample.value.toStringAsFixed(metric == DeviceHealthMetric.steps ? 0 : 1)}'
                  ' ${metric.unit} · ${sample.sourceName}',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
