import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import 'body_measurement_api.dart';

class BodyMeasurementFormPage extends StatefulWidget {
  const BodyMeasurementFormPage({
    this.initial,
    this.api,
    this.now = DateTime.now,
    super.key,
  });
  final BodyMeasurement? initial;
  final BodyMeasurementApi? api;
  final DateTime Function() now;
  @override
  State<BodyMeasurementFormPage> createState() =>
      _BodyMeasurementFormPageState();
}

class _BodyMeasurementFormPageState extends State<BodyMeasurementFormPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in measurementLabels.keys)
      key: TextEditingController(
        text: widget.initial?.values[key]?.toString() ?? '',
      ),
  };
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late DateTime _time =
      widget.initial?.measuredAt.toLocal() ?? widget.now().toLocal();
  AuthSession? _session;
  BodyMeasurementApi? _api;
  String? _owner, _error;
  bool _busy = false,
      _blocked = false,
      _completed = false,
      _changedOwner = false,
      _foreground = true;
  bool get _locked => _busy || _blocked || _completed;
  bool get _authorized =>
      !_changedOwner &&
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
    if (_owner != null &&
        (session?.user?.id != _owner || !identical(session, _session))) {
      _changedOwner = true;
      for (final field in _fields.values) {
        field.clear();
      }
      _note.clear();
    }
    _session = session;
    _owner ??= session?.user?.id;
    _api = widget.api != null && identical(widget.api!.session, session)
        ? widget.api
        : (session == null ? null : BodyMeasurementApi(session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setState(() => _foreground = state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final field in _fields.values) {
      field.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_locked || !_form.currentState!.validate()) return;
    if (!_authorized || _api == null) {
      setState(
        () => _error = 'Ölçüm kaydetmek için oturumunuz doğrulanmalıdır.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final owner = _owner;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = {
        for (final key in measurementLabels.keys)
          key: _fields[key]!.text.trim().isEmpty
              ? null
              : num.parse(_fields[key]!.text.trim().replaceAll(',', '.')),
      };
      if (values.values.every((v) => v == null)) {
        setState(() => _error = 'En az bir ölçüm girin.');
        return;
      }
      final note = _note.text.isEmpty ? null : _note.text;
      if (widget.initial == null) {
        await _api!.create(values: values, measuredAt: _time, note: note);
      } else {
        final changes = <String, Object?>{
          for (final key in values.keys)
            if (values[key] != widget.initial!.values[key]) key: values[key],
        };
        if (note != widget.initial!.note) changes['note'] = note;
        if (!_time.isAtSameMomentAs(widget.initial!.measuredAt)) {
          changes['measuredAt'] = _time.toUtc().toIso8601String();
        }
        if (changes.isEmpty) {
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        await _api!.update(widget.initial!.id, changes);
      }
      if (mounted && !_changedOwner && owner == _owner) {
        if (_authorized) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _completed = true);
        }
      }
    } catch (error) {
      if (mounted && !_changedOwner && owner == _owner) {
        setState(() {
          _error = error is BodyMeasurementApiException
              ? error.message
              : 'Ölçüm kaydı işlemi doğrulanamadı.';
          _blocked =
              error is! BodyMeasurementApiException ||
              error.uncertain ||
              const [401, 403, 404].contains(error.statusCode);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _date() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (mounted && value != null && !_locked) {
      setState(
        () => _time = DateTime(
          value.year,
          value.month,
          value.day,
          _time.hour,
          _time.minute,
        ),
      );
    }
  }

  Future<void> _clock() async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && value != null && !_locked) {
      setState(
        () => _time = DateTime(
          _time.year,
          _time.month,
          _time.day,
          value.hour,
          value.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Ölçüm ekle' : 'Ölçümü düzenle'),
      ),
      body: !_foreground || _changedOwner
          ? const Center(
              child: Text(
                'Ölçüm kaydı bilgileri gizlendi. Oturumunuzu kontrol edin.',
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in measurementLabels.entries) ...[
                            TextFormField(
                              controller: _fields[entry.key],
                              enabled: !_locked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${entry.value} (${measurementUnit(entry.key)})',
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (text.isEmpty) return null;
                                final number = num.tryParse(
                                  text.replaceAll(',', '.'),
                                );
                                return RegExp(
                                          r'^\d+(?:[.,]\d+)?$',
                                        ).hasMatch(text) &&
                                        number != null &&
                                        number.isFinite &&
                                        (entry.key == 'bodyFatPercent'
                                            ? number >= 0 && number <= 100
                                            : number > 0)
                                    ? null
                                    : entry.key == 'bodyFatPercent'
                                    ? '0–100 arasında bir yüzde girin.'
                                    : 'Sıfırdan büyük bir ölçüm girin.';
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _note,
                            enabled: !_locked,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Not (isteğe bağlı)',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value != null &&
                                    (value.runes.length > 2000 ||
                                        value.contains('\u0000'))
                                ? 'Not en çok 2000 karakter olabilir ve NUL içeremez.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _locked ? null : _date,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              'Ölçüm tarihi: ${_time.day}.${_time.month}.${_time.year}',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _locked ? null : _clock,
                            icon: const Icon(Icons.schedule),
                            label: Text(
                              'Ölçüm saati: ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                          const Text(
                            'Tarih ve saat cihazınızın yerel saatine göredir.',
                          ),
                          if (_error != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (_blocked)
                            const Text(
                              'Yeniden kaydetmeden önce geri dönüp ölçüm geçmişini kontrol edin.',
                            ),
                          if (_completed) ...[
                            const Text(
                              'Ölçüm kaydı tamamlandı. Geçmişinizi görmek için geri dönün.',
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Geri dön'),
                            ),
                          ],
                          if (_busy)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Ölçüm kaydediliyor',
                            ),
                          FilledButton.icon(
                            onPressed: _locked ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Kaydet'),
                          ),
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
