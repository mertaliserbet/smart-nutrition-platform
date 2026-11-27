import 'package:flutter/material.dart';
import '../onboarding/limely_mascot.dart';
import '../onboarding/onboarding_theme.dart';
import 'body_measurement_api.dart';
import 'measurement_chart.dart';

/// Presentation of the approved measurement concept; every value comes from rows.
class MeasurementOverview extends StatefulWidget {
  const MeasurementOverview({
    required this.rows,
    required this.now,
    required this.authorized,
    required this.loading,
    required this.onAdd,
    required this.onRetry,
    required this.onOpen,
    this.name,
    this.error,
    this.onProfile,
    super.key,
  });
  final List<BodyMeasurement> rows;
  final DateTime now;
  final bool authorized, loading;
  final String? name, error;
  final VoidCallback onAdd, onRetry;
  final VoidCallback? onProfile;
  final ValueChanged<BodyMeasurement> onOpen;
  @override
  State<MeasurementOverview> createState() => _MeasurementOverviewState();
}

class _MeasurementOverviewState extends State<MeasurementOverview> {
  String _field = 'weightKg';
  bool _all = false;
  int _page = 1;
  final _expanded = <String>{};
  final _chart = GlobalKey();
  static const _bodyFields = ['waistCm', 'hipCm', 'chestCm', 'bodyFatPercent'];
  String _label(String key) => switch (key) {
    'waistCm' => 'Bel çevresi',
    'hipCm' => 'Kalça çevresi',
    'chestCm' => 'Göğüs çevresi',
    'bodyFatPercent' => 'Yağ oranı',
    _ => 'Kilo',
  };
  List<BodyMeasurement> _with(String field) =>
      widget.rows.where((r) => r.values[field] != null).toList()..sort((a, b) {
        final n = a.measuredAt.compareTo(b.measuredAt);
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
  String _delta(num value, String unit) =>
      '${value < 0
          ? '−'
          : value > 0
          ? '+'
          : ''}${measurementValue(value.abs(), minimumDecimal: true)} $unit';
  Widget _heading(String text) => Text(
    text,
    style: OnboardingTheme.heading(21).copyWith(fontWeight: FontWeight.w700),
  );
  @override
  Widget build(BuildContext context) {
    final history = widget.rows.toList()
      ..sort((a, b) {
        final n = b.measuredAt.compareTo(a.measuredAt);
        return n == 0 ? b.id.compareTo(a.id) : n;
      });
    final ready = widget.authorized && !widget.loading && widget.error == null;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final weights = _with('weightKg');
    final pageCount = history.isEmpty ? 1 : (history.length / 10).ceil();
    final page = _page.clamp(1, pageCount).toInt();
    final visible = _all
        ? history.skip((page - 1) * 10).take(10)
        : history.take(3);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 24),
              _hero(context),
              const SizedBox(height: 20),
              if (ready && weights.isNotEmpty) ...[
                _latest(weights, large),
                const SizedBox(height: 13),
              ],
              FilledButton.icon(
                key: const ValueKey('new-measurement'),
                onPressed: widget.authorized && !widget.loading
                    ? widget.onAdd
                    : null,
                icon: const OnboardingIcon('plus'),
                label: const Text('Yeni ölçüm ekle'),
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
              const SizedBox(height: 23),
              if (!widget.authorized)
                const Text(
                  'Ölçümleri görüntülemek için oturumunuz doğrulanmalıdır.',
                )
              else if (widget.loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Ölçümler yükleniyor',
                )
              else if (widget.error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: OnboardingTheme.error),
                  ),
                )
              else if (history.isEmpty)
                _empty()
              else ...[
                MeasurementTrendCard(
                  key: _chart,
                  rows: history,
                  now: widget.now,
                  field: _field,
                  onFieldChanged: (v) => setState(() => _field = v),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _heading('Vücut ölçülerin')),
                    const OnboardingIcon('ruler', size: 21),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _bodyDate(history),
                  style: const TextStyle(
                    fontSize: 12,
                    color: OnboardingTheme.muted,
                  ),
                ),
                const SizedBox(height: 15),
                for (var i = 0; i < _bodyFields.length; i += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _metric(_bodyFields[i])),
                        const SizedBox(width: 11),
                        Expanded(child: _metric(_bodyFields[i + 1])),
                      ],
                    ),
                  ),
                  if (i == 0) const SizedBox(height: 11),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _heading('Ölçüm geçmişin'),
                    TextButton(
                      onPressed: () => setState(() {
                        _all = !_all;
                        _page = 1;
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _all ? 'Daha az göster' : 'Tümünü gör',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3D7756),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const OnboardingIcon('chevron-right', size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('measurement-history'),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: OnboardingTheme.border),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Column(
                    children: [
                      for (final (i, row) in visible.indexed)
                        _historyRow(
                          row,
                          first: i == 0,
                          last: i == visible.length - 1,
                          large: large,
                          latest: history.first.id == row.id,
                        ),
                    ],
                  ),
                ),
                if (_all && history.length > 10) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${history.length} ölçüm · Sayfa $page',
                    style: const TextStyle(
                      fontSize: 12,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 10,
                    children: [
                      TextButton(
                        onPressed: page <= 1
                            ? null
                            : () => setState(() => _page = page - 1),
                        child: const Text('Önceki sayfa'),
                      ),
                      TextButton(
                        onPressed: page >= pageCount
                            ? null
                            : () => setState(() => _page = page + 1),
                        child: const Text('Sonraki sayfa'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 19),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OnboardingTheme.soft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardingIcon('sprout', size: 22),
                      SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Her ölçüm, yolculuğunun bir parçası.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Ölçümlerini benzer saat ve koşullarda kaydetmek, değişimini takip etmeyi kolaylaştırır.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Color(0xFF536951),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.authorized)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.loading ? null : widget.onRetry,
                    child: const Text(
                      'Ölçümleri yenile',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final parts =
        widget.name
            ?.trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList() ??
        [];
    final initials = parts.isEmpty
        ? '?'
        : parts
              .take(2)
              .map((p) => p.characters.first.replaceAll('i', 'İ').toUpperCase())
              .join();
    return Row(
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
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: OnboardingIcon('bell', size: 25)),
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: 'Hesabım',
          button: widget.onProfile != null,
          child: Material(
            color: const Color(0xFFE1EDD3),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.onProfile,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: 43,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      initials,
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
  }

  Widget _hero(BuildContext context) {
    final parts =
        widget.name
            ?.trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList() ??
        [];
    final name = parts.length > 1
        ? parts.take(parts.length - 1).join(' ')
        : parts.join(' ');
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return LayoutBuilder(
      builder: (context, c) {
        final small = c.maxWidth < 315;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ÖLÇÜMLERİM',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Her adımın\nbir izi var.',
              style: OnboardingTheme.heading(
                small ? 29 : 33,
              ).copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.25),
            ),
            const SizedBox(height: 12),
            Text(
              '${name.isEmpty ? '' : '$name, '}değişimini\nkendi ritminde takip et.',
              style: TextStyle(
                fontSize: small ? 12 : 14,
                height: 1.5,
                color: OnboardingTheme.muted,
              ),
            ),
          ],
        );
        final mascot = LimelyMascot(
          size: small ? 110 : 133,
          pose: 'olcum',
          animated: widget.authorized,
        );
        if (large) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(alignment: Alignment.centerRight, child: mascot),
              copy,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 3),
            Transform.rotate(angle: .052, child: mascot),
          ],
        );
      },
    );
  }

  Widget _latest(List<BodyMeasurement> weights, bool large) {
    final latest = weights.last;
    final value = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          measurementValue(latest.weightKg!, minimumDecimal: true),
          key: const ValueKey('measurement-latest-weight'),
          style: const TextStyle(
            fontSize: 56,
            height: 1.12,
            letterSpacing: -2.5,
            fontWeight: FontWeight.w700,
            color: OnboardingTheme.background,
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'kg',
          style: TextStyle(fontSize: 21, color: Color(0xFFD4DFCE)),
        ),
      ],
    );
    final delta = Column(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: OnboardingTheme.lime.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            weights.length > 1
                ? _delta(latest.weightKg! - weights.first.weightKg!, 'kg')
                : 'İlk kaydın',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: OnboardingTheme.lime,
            ),
          ),
        ),
        if (weights.length > 1) ...[
          const SizedBox(height: 7),
          const Text(
            'İlk kayda göre',
            style: TextStyle(fontSize: 11, color: Color(0xFFCBD9C5)),
          ),
        ],
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: OnboardingTheme.ink,
        child: Stack(
          children: [
            Positioned(
              right: -66,
              top: 29,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: OnboardingTheme.lime.withValues(alpha: .08),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -35,
              top: 57,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x1483B977),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      const Text(
                        'SON KİLO ÖLÇÜMÜN',
                        style: TextStyle(
                          color: OnboardingTheme.lime,
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x2CF8FAF2)),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/limely/ikonlar/koyu/${latest.source == 'manual'
                                  ? 'pencil'
                                  : latest.source == 'wearable'
                                  ? 'activity'
                                  : 'info'}.png',
                              width: 12,
                              height: 12,
                              color: OnboardingTheme.background,
                              excludeFromSemantics: true,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              measurementSource(latest.source),
                              style: const TextStyle(
                                color: Color(0xFFE4EDDD),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (large) ...[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: value,
                    ),
                    const SizedBox(height: 10),
                    delta,
                  ] else
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: delta),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Image.asset(
                        'assets/limely/ikonlar/koyu/calendar.png',
                        width: 15,
                        height: 15,
                        color: const Color(0xFFD4DFCE),
                        excludeFromSemantics: true,
                      ),
                      Text(
                        '${measurementDate(latest.measuredAt)} · ${measurementClock(latest.measuredAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFD4DFCE),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: OnboardingTheme.border),
      borderRadius: BorderRadius.circular(23),
    ),
    child: const Column(
      children: [
        OnboardingIcon('body-scale', size: 35),
        SizedBox(height: 14),
        Text(
          'Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
      ],
    ),
  );
  String _bodyDate(List<BodyMeasurement> rows) {
    final body = rows.where(
      (r) => _bodyFields.any((field) => r.values[field] != null),
    );
    return body.isEmpty
        ? 'Ölçtüğün alanları ekleyebilirsin.'
        : 'Son kayıt · ${measurementDate(body.first.measuredAt)}';
  }

  Widget _metric(String field) {
    final rows = _with(field), latest = rows.isEmpty ? null : rows.last;
    final value = latest?.values[field], unit = measurementUnit(field);
    final delta = value == null
        ? 'Henüz kayıt yok'
        : rows.length == 1
        ? 'İlk kaydın'
        : _delta(
            value - rows.first.values[field]!,
            field == 'bodyFatPercent' ? 'puan' : unit,
          );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: OnboardingTheme.border),
        borderRadius: BorderRadius.circular(19),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() => _field = field);
          final context = _chart.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: .1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: field == 'bodyFatPercent'
                          ? const Color(0xFFFBF1C9)
                          : OnboardingTheme.soft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: OnboardingIcon(
                        field == 'bodyFatPercent' ? 'activity' : 'ruler',
                        size: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _label(field),
                      style: const TextStyle(
                        fontSize: 13,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value == null ? '—' : measurementValue(value),
                      style: const TextStyle(
                        fontSize: 27,
                        height: 1.1,
                        letterSpacing: -.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: value == null ? '' : ' $unit',
                      style: const TextStyle(
                        fontSize: 13,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: delta,
                      style: TextStyle(
                        color: value == null
                            ? OnboardingTheme.muted
                            : const Color(0xFF3D7756),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rows.length > 1)
                      const TextSpan(text: ' · İlk kayda göre'),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 11,
                  color: OnboardingTheme.muted,
                ),
              ),
              if (latest != null &&
                  widget.rows.any(
                    (row) =>
                        _bodyFields.any((key) => row.values[key] != null) &&
                        row.measuredAt.isAfter(latest.measuredAt),
                  ))
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    measurementDate(latest.measuredAt, year: false),
                    style: const TextStyle(
                      fontSize: 10,
                      color: OnboardingTheme.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyRow(
    BodyMeasurement row, {
    required bool first,
    required bool last,
    required bool large,
    required bool latest,
  }) {
    final expanded = _expanded.contains(row.id),
        local = row.measuredAt.toLocal();
    final count = row.values.values.where((v) => v != null).length;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${measurementDate(local, year: false)}${latest ? ' · Son kayıt' : ''}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '${measurementClock(local)} · $count ölçüm · ${measurementSource(row.source)}',
          style: const TextStyle(fontSize: 11, color: OnboardingTheme.muted),
        ),
      ],
    );
    final value = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: row.weightKg == null
                ? '—'
                : measurementValue(row.weightKg!, minimumDecimal: true),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (row.weightKg != null)
            const TextSpan(
              text: ' kg',
              style: TextStyle(fontSize: 12, color: OnboardingTheme.muted),
            ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE9EEE4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              key: ValueKey('measurement-record-${row.id}'),
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(row.id);
                } else {
                  _expanded.add(row.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: first
                            ? OnboardingTheme.soft
                            : const Color(0xFFF1F5EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${local.day}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            measurementMonths[local.month - 1].substring(0, 3),
                            style: const TextStyle(
                              fontSize: 10,
                              color: OnboardingTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: large
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 8),
                                value,
                              ],
                            )
                          : title,
                    ),
                    if (!large) ...[const SizedBox(width: 8), value],
                    const SizedBox(width: 8),
                    RotatedBox(
                      quarterTurns: expanded ? 1 : 0,
                      child: const OnboardingIcon('chevron-right', size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final e in measurementLabels.entries)
                          SizedBox(
                            width: (c.maxWidth - 12) / 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _label(e.key),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: OnboardingTheme.muted,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  row.values[e.key] == null
                                      ? 'Belirtilmemiş'
                                      : '${measurementValue(row.values[e.key]!)} ${measurementUnit(e.key)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (row.note != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      row.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: OnboardingTheme.muted,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => widget.onOpen(row),
                      child: const Text(
                        'Kaydı yönet',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
