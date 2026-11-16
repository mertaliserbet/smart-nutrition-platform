import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import 'meal_log_api.dart';

class ManualMealLogPage extends StatefulWidget {
  const ManualMealLogPage({this.api, this.initial, super.key});
  final MealLogApi? api;
  final MealLog? initial;
  @override
  State<ManualMealLogPage> createState() => _ManualMealLogPageState();
}

class _ManualMealLogPageState extends State<ManualMealLogPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final _note = TextEditingController(text: widget.initial?.note);
  late final _items =
      widget.initial?.items.map(_ItemFields.new).toList() ??
      [_ItemFields(null)];
  late DateTime _consumedAt =
      widget.initial?.consumedAt.toLocal() ?? DateTime.now();
  late String? _mealType = widget.initial?.mealType;
  AuthSession? _session;
  MealLogApi? _api;
  String? _owner, _error;
  bool _busy = false,
      _uncertain = false,
      _completed = false,
      _ownerChanged = false,
      _foreground = true;
  bool get _authorized =>
      !_ownerChanged &&
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
      _ownerChanged = true;
      _note.clear();
      for (final item in _items) {
        for (final field in item.fields.values) {
          field.clear();
        }
      }
    }
    _session = session;
    _owner ??= session?.user?.id;
    _api = widget.api ?? (session == null ? null : MealLogApi(session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setState(() => _foreground = state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _note.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _uncertain || _completed) return;
    FocusScope.of(context).unfocus();
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 150),
      );
      return;
    }
    if (!_authorized || _api == null) {
      setState(
        () => _error = 'Öğün kaydetmek için oturumunuz doğrulanmalıdır.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final owner = _owner;
    try {
      final body = <String, Object?>{
        'mealType': _mealType,
        'consumedAt': _consumedAt.toUtc().toIso8601String(),
        'note': _note.text.trim().isEmpty ? null : _note.text,
        'items': _items.map((item) => item.input()).toList(),
      };
      if (widget.initial == null) {
        body['source'] = 'manual';
        await _api!.create(body);
      } else {
        if (_items.length == widget.initial!.items.length &&
            _items.indexed.every(
              (entry) => entry.$2.unchanged(widget.initial!.items[entry.$1]),
            )) {
          body.remove('items');
        }
        await _api!.update(widget.initial!.id, body);
      }
      if (mounted && !_ownerChanged && _owner == owner) {
        if (_authorized) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _completed = true);
        }
      }
    } catch (error) {
      if (mounted && _owner == owner && !_ownerChanged) {
        setState(() {
          _error = error is MealLogApiException
              ? error.message
              : 'Öğün işlemi doğrulanamadı.';
          _uncertain = error is! MealLogApiException || error.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _consumedAt,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Tüketim tarihi',
    );
    if (mounted && date != null && !_busy) {
      setState(
        () => _consumedAt = DateTime(
          date.year,
          date.month,
          date.day,
          _consumedAt.hour,
          _consumedAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_consumedAt),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && time != null && !_busy) {
      setState(
        () => _consumedAt = DateTime(
          _consumedAt.year,
          _consumedAt.month,
          _consumedAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? 'Öğünü düzenle' : 'Öğün ekle')),
        body: !_foreground || _ownerChanged
            ? const Center(
                child: Text(
                  'Öğün bilgileri gizlendi. Oturumunuzu kontrol edin.',
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(AppTokens.spacingMedium),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Tükettiğiniz besinleri ve bildiğiniz değerleri girin. Bilmediğiniz miktar veya besin değerlerini boş bırakabilirsiniz.',
                            ),
                            const SizedBox(height: 16),
                            FormField<String>(
                              initialValue: _mealType,
                              validator: (value) =>
                                  value == null ? 'Bir öğün türü seçin.' : null,
                              builder: (field) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Öğün türü'),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final entry
                                          in mealTypeLabels.entries)
                                        ChoiceChip(
                                          label: Text(entry.value),
                                          selected: field.value == entry.key,
                                          onSelected:
                                              _busy || _uncertain || _completed
                                              ? null
                                              : (_) {
                                                  field.didChange(entry.key);
                                                  _mealType = entry.key;
                                                },
                                        ),
                                    ],
                                  ),
                                  if (field.hasError)
                                    Text(
                                      field.errorText!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy || _uncertain || _completed
                                      ? null
                                      : _pickDate,
                                  icon: const Icon(Icons.calendar_today),
                                  label: Text(
                                    'Tüketim tarihi: ${_consumedAt.day}.${_consumedAt.month}.${_consumedAt.year}',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy || _uncertain || _completed
                                      ? null
                                      : _pickTime,
                                  icon: const Icon(Icons.schedule),
                                  label: Text(
                                    'Tüketim saati: ${_consumedAt.hour.toString().padLeft(2, '0')}:${_consumedAt.minute.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'Tarih ve saat cihazınızın yerel saatine göredir.',
                            ),
                            for (final (index, item) in _items.indexed)
                              Card(
                                key: ObjectKey(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Besin ${index + 1}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      for (final entry
                                          in _ItemFields.labels.entries)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: TextFormField(
                                            key: ValueKey(
                                              'item-$index-${entry.key}',
                                            ),
                                            controller: item.fields[entry.key],
                                            enabled:
                                                !_busy &&
                                                !_uncertain &&
                                                !_completed,
                                            decoration: InputDecoration(
                                              labelText: entry.value,
                                              border:
                                                  const OutlineInputBorder(),
                                              errorMaxLines: 3,
                                            ),
                                            keyboardType:
                                                entry.key == 'displayName'
                                                ? TextInputType.text
                                                : const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                            validator: (value) =>
                                                entry.key == 'displayName'
                                                ? _textError(
                                                    value,
                                                    required: true,
                                                  )
                                                : _numberError(
                                                    value,
                                                    quantity:
                                                        entry.key ==
                                                        'quantityGrams',
                                                  ),
                                          ),
                                        ),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Besin değerleri tahminidir',
                                        ),
                                        value: item.isEstimated,
                                        onChanged:
                                            _busy || _uncertain || _completed
                                            ? null
                                            : (value) => setState(
                                                () => item.isEstimated = value!,
                                              ),
                                      ),
                                      if (_items.length > 1)
                                        TextButton.icon(
                                          onPressed:
                                              _busy || _uncertain || _completed
                                              ? null
                                              : () {
                                                  setState(
                                                    () =>
                                                        _items.removeAt(index),
                                                  );
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback(
                                                        (_) => item.dispose(),
                                                      );
                                                },
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                          label: const Text('Besini kaldır'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_items.length < 100)
                              OutlinedButton.icon(
                                onPressed: _busy || _uncertain || _completed
                                    ? null
                                    : () => setState(
                                        () => _items.add(_ItemFields(null)),
                                      ),
                                icon: const Icon(Icons.add),
                                label: const Text('Besin ekle'),
                              ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _note,
                              enabled: !_busy && !_uncertain && !_completed,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Not',
                                border: OutlineInputBorder(),
                              ),
                              validator: _textError,
                            ),
                            const SizedBox(height: 16),
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
                            if (_uncertain)
                              const Text(
                                'İşlemin sonucu belirsiz. Yeniden kaydetmeden önce geri dönüp öğün geçmişini kontrol edin.',
                              ),
                            if (_completed) ...[
                              const Text(
                                'Öğün kaydedildi. Geçmişinizi kontrol etmek için geri dönün.',
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Geri dön'),
                              ),
                            ],
                            if (_busy)
                              const LinearProgressIndicator(
                                semanticsLabel: 'Öğün kaydediliyor',
                              ),
                            FilledButton.icon(
                              onPressed: _busy || _uncertain || _completed
                                  ? null
                                  : _save,
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
}

String? _textError(String? text, {bool required = false}) {
  if (required && (text == null || text.trim().isEmpty)) {
    return 'Yemek adını girin.';
  }
  if (text != null && (text.runes.length > 2000 || text.contains('\u0000'))) {
    return 'En fazla 2000 karakter girin; geçersiz karakterleri kaldırın.';
  }
  return null;
}

String? _numberError(String? text, {required bool quantity}) {
  final input = text?.trim() ?? '';
  if (input.isEmpty) return null;
  final number = num.tryParse(input.replaceAll(',', '.'));
  if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(input) ||
      number == null ||
      !number.isFinite ||
      (quantity ? number <= 0 : number < 0)) {
    return quantity
        ? 'Sıfırdan büyük bir gram miktarı girin (ör. 125,5).'
        : 'Sıfır veya daha büyük bir sayı girin.';
  }
  return null;
}

class _ItemFields {
  _ItemFields(MealLogItem? initial) {
    final values = initial?.toInput() ?? <String, Object?>{};
    for (final key in labels.keys) {
      fields[key] = TextEditingController(text: values[key]?.toString() ?? '');
    }
    isEstimated = initial?.isEstimated ?? true;
  }
  static const labels = {
    'displayName': 'Yemek adı',
    'quantityGrams': 'Miktar (gram)',
    'caloriesKcal': 'Kalori (kcal)',
    'proteinGrams': 'Protein (g)',
    'carbsGrams': 'Karbonhidrat (g)',
    'fatGrams': 'Yağ (g)',
  };
  final fields = <String, TextEditingController>{};
  bool isEstimated = true;
  Map<String, Object?> input() => {
    for (final key in fields.keys)
      key: key == 'displayName'
          ? fields[key]!.text.trim()
          : fields[key]!.text.trim().isEmpty
          ? null
          : num.parse(fields[key]!.text.trim().replaceAll(',', '.')),
    'isEstimated': isEstimated,
  };
  bool unchanged(MealLogItem original) {
    final values = original.toInput();
    return isEstimated == original.isEstimated &&
        fields.entries.every(
          (entry) => entry.value.text == (values[entry.key]?.toString() ?? ''),
        );
  }

  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
  }
}
