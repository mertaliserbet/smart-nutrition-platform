import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import 'water_log_api.dart';

class WaterLogFormPage extends StatefulWidget {
  const WaterLogFormPage({
    this.initial,
    this.api,
    this.now = DateTime.now,
    super.key,
  });
  final WaterLog? initial;
  final WaterLogApi? api;
  final DateTime Function() now;
  @override
  State<WaterLogFormPage> createState() => _WaterLogFormPageState();
}

class _WaterLogFormPageState extends State<WaterLogFormPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.initial?.amountMl.toString() ?? '',
  );
  late DateTime _time =
      widget.initial?.consumedAt.toLocal() ?? widget.now().toLocal();
  AuthSession? _session;
  WaterLogApi? _api;
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
      _amount.clear();
    }
    _session = session;
    _owner ??= session?.user?.id;
    _api = widget.api ?? (session == null ? null : WaterLogApi(session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setState(() => _foreground = state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_locked || !_form.currentState!.validate()) return;
    if (!_authorized || _api == null) {
      setState(() => _error = 'Su kaydetmek için oturumunuz doğrulanmalıdır.');
      return;
    }
    FocusScope.of(context).unfocus();
    final owner = _owner;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final amount = num.parse(_amount.text.trim().replaceAll(',', '.'));
      if (widget.initial == null) {
        await _api!.create(amountMl: amount, consumedAt: _time);
      } else {
        await _api!.update(
          widget.initial!.id,
          amountMl: amount,
          consumedAt: _time,
        );
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
          _error = error is WaterLogApiException
              ? error.message
              : 'Su kaydı işlemi doğrulanamadı.';
          _blocked =
              error is! WaterLogApiException ||
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
        title: Text(widget.initial == null ? 'Su ekle' : 'Su kaydını düzenle'),
      ),
      body: !_foreground || _changedOwner
          ? const Center(
              child: Text(
                'Su kaydı bilgileri gizlendi. Oturumunuzu kontrol edin.',
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
                          TextFormField(
                            controller: _amount,
                            enabled: !_locked,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Su miktarı (mL)',
                              suffixText: 'mL',
                              border: OutlineInputBorder(),
                              errorMaxLines: 3,
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '',
                                  number = num.tryParse(
                                    (value ?? '').trim().replaceAll(',', '.'),
                                  );
                              return RegExp(
                                        r'^\d+(?:[.,]\d+)?$',
                                      ).hasMatch(text) &&
                                      number != null &&
                                      number.isFinite &&
                                      number > 0
                                  ? null
                                  : 'Sıfırdan büyük bir su miktarı girin.';
                            },
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final ml in [250, 500, 1000])
                                ActionChip(
                                  label: Text('$ml mL'),
                                  onPressed: _locked
                                      ? null
                                      : () => _amount.text = '$ml',
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _locked ? null : _date,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              'Tüketim tarihi: ${_time.day}.${_time.month}.${_time.year}',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _locked ? null : _clock,
                            icon: const Icon(Icons.schedule),
                            label: Text(
                              'Tüketim saati: ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
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
                              'Yeniden kaydetmeden önce geri dönüp su geçmişini kontrol edin.',
                            ),
                          if (_completed) ...[
                            const Text(
                              'Su kaydı tamamlandı. Geçmişinizi görmek için geri dönün.',
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Geri dön'),
                            ),
                          ],
                          if (_busy)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Su kaydediliyor',
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
