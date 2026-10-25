import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Local form presentation only; no DTO, persistence or API submission.
class ManualMealLogPage extends StatefulWidget {
  const ManualMealLogPage({super.key});

  @override
  State<ManualMealLogPage> createState() => _ManualMealLogPageState();
}

class _ManualMealLogPageState extends State<ManualMealLogPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _quantityGrams = TextEditingController();
  DateTime _consumedAt = DateTime.now();
  bool _showUnavailable = false;

  @override
  void dispose() {
    _displayName.dispose();
    _quantityGrams.dispose();
    super.dispose();
  }

  void _clearFeedback() {
    if (_showUnavailable) setState(() => _showUnavailable = false);
  }

  Future<void> _checkDetails() async {
    FocusScope.of(context).unfocus();
    _clearFeedback();
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalidFields.first.context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }
    setState(() => _showUnavailable = true);
  }

  String? _validateQuantity(String? value) {
    final input = value?.trim() ?? '';
    // quantityGrams is nullable. No portion conversion or precision policy.
    if (input.isEmpty) return null;
    final number = double.tryParse(input.replaceAll(',', '.'));
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(input) ||
        number == null ||
        !number.isFinite ||
        number <= 0) {
      return 'Sıfırdan büyük bir gram miktarı girin (ör. 125,5).';
    }
    return null;
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final date = await showDatePicker(
      context: context,
      initialDate: _consumedAt,
      // Technical picker bounds, not a restriction on the meal-log contract.
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Tüketim tarihi',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (!mounted || date == null) return;
    setState(() {
      _consumedAt = DateTime(
        date.year,
        date.month,
        date.day,
        _consumedAt.hour,
        _consumedAt.minute,
      );
      _showUnavailable = false;
    });
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_consumedAt),
      helpText: 'Tüketim saati',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
      hourLabelText: 'Saat',
      minuteLabelText: 'Dakika',
      errorInvalidText: 'Geçerli bir saat girin.',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    setState(() {
      _consumedAt = DateTime(
        _consumedAt.year,
        _consumedAt.month,
        _consumedAt.day,
        time.hour,
        time.minute,
      );
      _showUnavailable = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date =
        '${_consumedAt.day.toString().padLeft(2, '0')}.'
        '${_consumedAt.month.toString().padLeft(2, '0')}.${_consumedAt.year}';
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_consumedAt),
      alwaysUse24HourFormat: true,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Öğün ekle')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppTokens.spacingMedium),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: colors.primary),
                      const SizedBox(width: AppTokens.spacingSmall),
                      Expanded(
                        child: Text(
                          'Manuel giriş',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spacingMedium),
                  Semantics(
                    header: true,
                    child: Text(
                      'Öğününüzü anlatın.',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingSmall),
                  Text(
                    'Ne yediğinizi ve ne zaman tükettiğinizi belirtin.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingLarge),
                  Text(
                    'Önizleme · Kayıt oluşturulmaz',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingMedium),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(
                        AppTokens.radiusMedium,
                      ),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.spacingMedium),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MealTypeField(onChanged: _clearFeedback),
                            const SizedBox(height: AppTokens.spacingLarge),
                            TextFormField(
                              controller: _displayName,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Yemek adını girin.'
                                  : null,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              onChanged: (_) => _clearFeedback(),
                              decoration: const InputDecoration(
                                labelText: 'Yemek adı',
                                hintText: 'Ör. Mercimek çorbası',
                                border: OutlineInputBorder(),
                                errorMaxLines: 3,
                              ),
                            ),
                            const SizedBox(height: AppTokens.spacingLarge),
                            TextFormField(
                              controller: _quantityGrams,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.done,
                              validator: _validateQuantity,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              onChanged: (_) => _clearFeedback(),
                              onFieldSubmitted: (_) => _checkDetails(),
                              decoration: const InputDecoration(
                                labelText: 'Miktar (gram)',
                                suffixText: 'g',
                                helperText:
                                    'İsteğe bağlı · Bilmiyorsanız boş bırakın. Porsiyon/adet dönüşümü yapılmaz.',
                                helperMaxLines: 4,
                                errorMaxLines: 4,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: AppTokens.spacingLarge),
                            Text(
                              'Tüketim zamanı',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppTokens.spacingSmall),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked =
                                    constraints.maxWidth < 400 ||
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.3;
                                final dateButton = _ConsumedAtButton(
                                  label: 'Tarih',
                                  value: date,
                                  icon: Icons.calendar_today_outlined,
                                  onPressed: _pickDate,
                                );
                                final timeButton = _ConsumedAtButton(
                                  label: 'Saat',
                                  value: time,
                                  icon: Icons.schedule_rounded,
                                  onPressed: _pickTime,
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      dateButton,
                                      const SizedBox(
                                        height: AppTokens.spacingSmall,
                                      ),
                                      timeButton,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: dateButton),
                                    const SizedBox(
                                      width: AppTokens.spacingSmall,
                                    ),
                                    Expanded(child: timeButton),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: AppTokens.spacingSmall),
                            Text(
                              'Cihazınızın yerel saati',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingLarge),
                  Text(
                    'Kalori ve makro bilgisi yok',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppTokens.spacingSmall),
                  Text(
                    'Besin bilgisi olmadan değer hesaplanmaz.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingLarge),
                  if (_showUnavailable) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Kayıt özelliği henüz kullanıma açık değil. Öğün kaydedilmedi.',
                        key: const ValueKey('mealLogUnavailable'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingMedium),
                  ],
                  FilledButton.icon(
                    onPressed: _checkDetails,
                    icon: const Icon(Icons.fact_check_outlined),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(AppTokens.spacingMedium),
                    ),
                    label: const Text(
                      'Bilgileri kontrol et',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingMedium),
                  Text(
                    'Girdiler yalnızca bu ekran açıkken tutulur.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The four requested UI choices use canonical MealType names from docs/04.
// This private subset is not the complete domain enum or a transport model.
enum _MealType {
  breakfast('Kahvaltı', Icons.wb_twilight_rounded),
  lunch('Öğle', Icons.light_mode_outlined),
  dinner('Akşam', Icons.dark_mode_outlined),
  snack('Ara öğün', Icons.local_cafe_outlined);

  const _MealType(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _MealTypeField extends StatelessWidget {
  const _MealTypeField({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FormField<_MealType>(
      validator: (value) => value == null ? 'Bir öğün türü seçin.' : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Öğün türü', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppTokens.spacingMedium),
          Wrap(
            spacing: AppTokens.spacingSmall,
            runSpacing: AppTokens.spacingSmall,
            children: [
              for (final mealType in _MealType.values)
                ChoiceChip(
                  avatar: Icon(mealType.icon, size: 20),
                  label: Text(mealType.label),
                  selected: field.value == mealType,
                  onSelected: (_) {
                    field.didChange(mealType);
                    onChanged();
                  },
                  padding: const EdgeInsets.all(AppTokens.spacingSmall),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          if (field.hasError) ...[
            const SizedBox(height: AppTokens.spacingSmall),
            Semantics(
              liveRegion: true,
              child: Text(
                field.errorText!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsumedAtButton extends StatelessWidget {
  const _ConsumedAtButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    style: OutlinedButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.all(AppTokens.spacingMedium),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
      ),
    ),
    label: Text('$label: $value'),
  );
}
