import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../onboarding/onboarding_theme.dart';
import 'body_measurement_api.dart';

Future<bool?> showBodyMeasurementForm(
  BuildContext context, {
  required BodyMeasurementApi api,
  BodyMeasurement? initial,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  constraints: const BoxConstraints(maxWidth: 480),
  backgroundColor: OnboardingTheme.background,
  barrierColor: const Color(0x7010271C),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  clipBehavior: Clip.antiAlias,
  builder: (context) => Theme(
    data: OnboardingTheme.data,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: BodyMeasurementFormPage(api: api, initial: initial, isSheet: true),
    ),
  ),
);

class BodyMeasurementFormPage extends StatefulWidget {
  const BodyMeasurementFormPage({
    this.initial,
    this.api,
    this.now = DateTime.now,
    this.isSheet = false,
    super.key,
  });
  final BodyMeasurement? initial;
  final bool isSheet;
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

  Widget _numberField(String key) {
    final label = switch (key) {
      'waistCm' => 'Bel çevresi',
      'hipCm' => 'Kalça çevresi',
      'chestCm' => 'Göğüs çevresi',
      'bodyFatPercent' => 'Yağ oranı',
      _ => 'Kilo',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              if (key == 'weightKg') ...[
                const OnboardingIcon('body-scale', size: 16),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          label: '$label (${measurementUnit(key)})',
          child: TextFormField(
            key: ValueKey('measurement-field-$key'),
            controller: _fields[key],
            enabled: !_locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontFamily: 'Figtree', fontSize: 16),
            decoration: _decoration(switch (key) {
              'weightKg' => 'Örn. 72,4',
              'waistCm' => '82',
              'hipCm' => '98,5',
              'chestCm' => '96',
              _ => '22,4',
            }, unit: measurementUnit(key)),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              final n = num.tryParse(text.replaceAll(',', '.'));
              return RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text) &&
                      n != null &&
                      n.isFinite &&
                      (key == 'bodyFatPercent' ? n >= 0 && n <= 100 : n > 0)
                  ? null
                  : key == 'bodyFatPercent'
                  ? '0–100 arasında bir yüzde girin.'
                  : 'Sıfırdan büyük bir ölçüm girin.';
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(String hint, {String? unit}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF8B9687)),
    suffixIcon: unit == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 13),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                unit,
                style: const TextStyle(
                  fontSize: 13,
                  color: OnboardingTheme.muted,
                ),
              ),
            ),
          ),
    suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
    errorMaxLines: 3,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFDCE5D5)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFDCE5D5)),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFDCE5D5)),
    ),
  );
  Widget _dateButton({required bool clock}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        clock ? 'Saat' : 'Ölçüm tarihi',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      OutlinedButton(
        onPressed: _locked
            ? null
            : clock
            ? _clock
            : _date,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 49),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDCE5D5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                clock
                    ? measurementClock(_time)
                    : '${_time.day.toString().padLeft(2, '0')}.${_time.month.toString().padLeft(2, '0')}.${_time.year}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 4),
            OnboardingIcon(clock ? 'clock' : 'calendar', size: 19),
          ],
        ),
      ),
    ],
  );
  Widget _pair(Widget a, Widget b) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, const SizedBox(height: 14), b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isSheet)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 11, bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC9D3C1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          if (!widget.isSheet) const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.initial == null
                      ? 'Yeni bir adım kaydet.'
                      : 'Ölçümünü düzenle.',
                  style: OnboardingTheme.heading(
                    25,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.isSheet) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            Navigator.of(context).pop(_completed ? true : null),
                  tooltip: 'Ölçüm formunu kapat',
                  style: IconButton.styleFrom(
                    backgroundColor: OnboardingTheme.soft,
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(8),
                  ),
                  icon: const OnboardingIcon('x', size: 19),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            widget.initial == null
                ? 'Bugünkü ölçümlerini ekle.\nYalnızca ölçtüğün alanları doldurabilirsin.'
                : 'Kaydındaki ölçümleri ve notunu güncelleyebilirsin.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: OnboardingTheme.muted,
            ),
          ),
          const SizedBox(height: 20),
          if (!_foreground || _changedOwner)
            const Text(
              'Ölçüm kaydı bilgileri gizlendi. Oturumunuzu kontrol edin.',
            )
          else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pair(_dateButton(clock: false), _dateButton(clock: true)),
                  const SizedBox(height: 14),
                  _numberField('weightKg'),
                  const SizedBox(height: 14),
                  _pair(_numberField('waistCm'), _numberField('hipCm')),
                  const SizedBox(height: 14),
                  _pair(
                    _numberField('chestCm'),
                    _numberField('bodyFatPercent'),
                  ),
                  const SizedBox(height: 14),
                  const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Kendine bir not ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '· İsteğe bağlı',
                          style: TextStyle(color: OnboardingTheme.muted),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  Semantics(
                    label: 'Not (isteğe bağlı)',
                    child: TextFormField(
                      key: const ValueKey('measurement-note'),
                      controller: _note,
                      enabled: !_locked,
                      minLines: 2,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 14),
                      decoration: _decoration(
                        'Ölçümünle ilgili bir not ekleyebilirsin.',
                      ),
                      validator: (v) =>
                          v != null &&
                              (v.runes.length > 2000 || v.contains('\u0000'))
                          ? 'Not en çok 2000 karakter olabilir ve NUL içeremez.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardingIcon('info', size: 15),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'En az bir ölçüm girmen yeterli. Eksik alanlar boş kalır.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: OnboardingTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: OnboardingTheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (_blocked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Yeniden kaydetmeden önce geri dönüp ölçüm geçmişini kontrol edin.',
                        style: TextStyle(fontSize: 12),
                      ),
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
                  const SizedBox(height: 19),
                  if (_busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Ölçüm kaydediliyor',
                    ),
                  FilledButton.icon(
                    onPressed: _locked ? null : _save,
                    icon: const OnboardingIcon('check'),
                    label: Text(
                      _busy
                          ? 'Kaydediliyor…'
                          : widget.initial == null
                          ? 'Ölçümümü kaydet'
                          : 'Değişiklikleri kaydet',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final scroll = SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: content,
        ),
      ),
    );
    return Theme(
      data: OnboardingTheme.data,
      child: PopScope(
        canPop: !_busy,
        child: widget.isSheet
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      (MediaQuery.sizeOf(context).height * .93 -
                              MediaQuery.viewInsetsOf(context).bottom)
                          .clamp(100.0, MediaQuery.sizeOf(context).height),
                ),
                child: SafeArea(top: false, child: scroll),
              )
            : Scaffold(
                backgroundColor: OnboardingTheme.background,
                appBar: AppBar(
                  backgroundColor: OnboardingTheme.background,
                  title: Text(
                    widget.initial == null ? 'Yeni ölçüm' : 'Ölçümü düzenle',
                  ),
                ),
                body: SafeArea(child: scroll),
              ),
      ),
    );
  }
}
