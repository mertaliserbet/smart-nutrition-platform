import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'body_measurement_api.dart';
import 'body_measurement_form_page.dart';

class BodyMeasurementDetailPage extends StatefulWidget {
  const BodyMeasurementDetailPage({required this.id, this.api, super.key});
  final String id;
  final BodyMeasurementApi? api;
  @override
  State<BodyMeasurementDetailPage> createState() =>
      _BodyMeasurementDetailPageState();
}

class _BodyMeasurementDetailPageState extends State<BodyMeasurementDetailPage>
    with WidgetsBindingObserver {
  AuthSession? _session;
  BodyMeasurementApi? _api;
  BodyMeasurement? _measurement;
  String? _owner, _error;
  int _generation = 0;
  bool _busy = false, _foreground = true, _deleting = false;
  bool get _authorized =>
      _foreground &&
      _session?.isAuthenticated == true &&
      _session?.user?.id == _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthSessionScope.maybeOf(context) ?? widget.api?.session;
    if (!identical(session, _session) || _owner != session?.user?.id) {
      _clear();
      _session = session;
      _owner = session?.user?.id;
      _api = widget.api != null && identical(widget.api!.session, session)
          ? widget.api
          : (session == null ? null : BodyMeasurementApi(session));
    }
    if (!_authorized) {
      _clear();
    } else if (_measurement == null && !_busy && _error == null) {
      _load();
    }
  }

  void _clear() {
    ++_generation;
    _measurement = null;
    _error = null;
    _busy = _deleting;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_clear);
    if (_authorized) _load();
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized || _api == null || _busy) return;
    final generation = ++_generation;
    setState(() {
      _measurement = null;
      _error = null;
      _busy = true;
    });
    try {
      final meal = await _api!.get(widget.id);
      if (mounted && _authorized && generation == _generation) {
        setState(() => _measurement = meal);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(
          () => _error = error is BodyMeasurementApiException
              ? error.message
              : 'Ölçüm yüklenemedi.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (_measurement == null || _busy || !_authorized) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BodyMeasurementFormPage(api: _api, initial: _measurement),
      ),
    );
    if (!mounted || !_authorized) return;
    if (changed == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ölçüm güncellendi.')));
    }
    await _load();
  }

  Future<void> _delete() async {
    if (_measurement == null || _busy || !_authorized) return;
    final owner = _owner;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ölçüm silinsin mi?'),
        content: const Text('Bu ölçüm geçmişinizden kaldırılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        !_authorized ||
        owner != _owner ||
        _busy) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _deleting = true;
    });
    try {
      await _api!.delete(widget.id);
      if (mounted && _authorized && generation == _generation) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted && _authorized && generation == _generation) {
        setState(() {
          _measurement = null;
          _error =
              '${error is BodyMeasurementApiException ? error.message : 'Silme işlemi doğrulanamadı.'} Yeniden işlem yapmadan önce durumu yenileyin.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
        if (_authorized && generation != _generation) await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Ölçüm detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_authorized)
            const Text('Ölçüm bilgileri gizlendi. Oturumunuzu kontrol edin.')
          else ...[
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Ölçüm işlemi sürüyor',
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_measurement case final row?) ...[
              Text(
                formatMeasurementTime(row.measuredAt),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Kaynak: ${row.source == "manual"
                    ? "Manuel"
                    : row.source == "wearable"
                    ? "Cihaz"
                    : "AI destekli"}',
              ),
              for (final entry in measurementLabels.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: Text(
                    row.values[entry.key] == null
                        ? 'Belirtilmemiş'
                        : '${row.values[entry.key]} ${measurementUnit(entry.key)}',
                  ),
                ),
              if (row.note != null) Text('Not: ${row.note}'),
              if (row.canEdit)
                FilledButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Düzenle'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Ölçümü sil'),
              ),
            ],
            TextButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Durumu yenile'),
            ),
          ],
        ],
      ),
    ),
  );
}
