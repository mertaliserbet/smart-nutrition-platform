import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../onboarding/onboarding_theme.dart';
import 'body_measurement_api.dart';

typedef MeasurementPoint = ({DateTime at, num value});
List<MeasurementPoint> measurementPoints(
  List<BodyMeasurement> rows,
  String field,
) {
  final ordered = rows.where((r) => r.values[field] != null).toList()
    ..sort((a, b) {
      final n = a.measuredAt.compareTo(b.measuredAt);
      return n == 0 ? a.id.compareTo(b.id) : n;
    });
  return List.unmodifiable(
    ordered.map((r) => (at: r.measuredAt, value: r.values[field]!)),
  );
}

class MeasurementTrendCard extends StatefulWidget {
  const MeasurementTrendCard({
    required this.rows,
    required this.now,
    this.field = 'weightKg',
    this.onFieldChanged,
    super.key,
  });
  final List<BodyMeasurement> rows;
  final DateTime now;
  final String field;
  final ValueChanged<String>? onFieldChanged;
  @override
  State<MeasurementTrendCard> createState() => _MeasurementTrendCardState();
}

class _MeasurementTrendCardState extends State<MeasurementTrendCard> {
  int _days = 30;
  @override
  Widget build(BuildContext context) {
    final now = widget.now.toLocal();
    final from = DateTime(now.year, now.month, now.day - _days + 1),
        to = DateTime(now.year, now.month, now.day + 1);
    final rows = widget.rows
        .where((r) => !r.measuredAt.isBefore(from) && r.measuredAt.isBefore(to))
        .toList();
    final count = rows.where((r) => r.values[widget.field] != null).length;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final picker = Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: OnboardingTheme.background,
        border: Border.all(color: OnboardingTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          OnboardingIcon(
            widget.field == 'weightKg'
                ? 'body-scale'
                : widget.field == 'bodyFatPercent'
                ? 'activity'
                : 'ruler',
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('measurement-metric-picker'),
                value: widget.field,
                isDense: true,
                isExpanded: true,
                icon: const OnboardingIcon('chevron-down', size: 17),
                dropdownColor: OnboardingTheme.background,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: OnboardingTheme.ink,
                ),
                items: [
                  for (final e in measurementLabels.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.key == 'bodyFatPercent' ? 'Yağ oranı' : e.value,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) widget.onFieldChanged?.call(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('measurement-trend'),
      padding: const EdgeInsets.fromLTRB(18, 19, 18, 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .85),
        border: Border.all(color: OnboardingTheme.border),
        borderRadius: BorderRadius.circular(23),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final title = Text(
                'Değişimine bir bak.',
                style: OnboardingTheme.heading(
                  21,
                ).copyWith(fontWeight: FontWeight.w700),
              );
              if (large || c.maxWidth < 285) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 12),
                    SizedBox(width: large ? 210 : 125, child: picker),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  SizedBox(width: 116, child: picker),
                ],
              );
            },
          ),
          const SizedBox(height: 17),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              Text(
                'Son $_days gün · $count ölçüm',
                style: const TextStyle(
                  fontSize: 11,
                  color: OnboardingTheme.muted,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4EA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Wrap(
                    spacing: 2,
                    children: [
                      for (final days in [7, 30, 90])
                        Semantics(
                          selected: _days == days,
                          child: TextButton(
                            onPressed: () => setState(() => _days = days),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(37, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 7,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: _days == days
                                  ? Colors.white
                                  : Colors.transparent,
                              foregroundColor: _days == days
                                  ? OnboardingTheme.ink
                                  : OnboardingTheme.muted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              '$days gün',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MeasurementChart(rows: rows, field: widget.field),
        ],
      ),
    );
  }
}

class MeasurementChart extends StatelessWidget {
  const MeasurementChart({required this.rows, required this.field, super.key});
  final List<BodyMeasurement> rows;
  final String field;
  @override
  Widget build(BuildContext context) {
    final points = measurementPoints(rows, field),
        label = measurementLabels[field]!,
        unit = measurementUnit(field);
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 42),
        child: Text(
          'Bu aralıkta ${label.toLowerCase()} ölçümü yok.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: OnboardingTheme.muted, fontSize: 14),
        ),
      );
    }
    Widget value(String label, num number) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: OnboardingTheme.muted),
          ),
          TextSpan(
            text: '${measurementValue(number, minimumDecimal: true)} $unit',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              '$label grafiği. ${points.length} ölçüm. İlk: ${formatMeasurementTime(points.first.at)}, ${points.first.value} $unit. Son: ${formatMeasurementTime(points.last.at)}, ${points.last.value} $unit. Ayrıntılar ölçüm geçmişinde.',
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, c) => SizedBox(
                width: double.infinity,
                height: c.maxWidth * 185 / 350,
                child: CustomPaint(
                  key: ValueKey('measurement-chart-$field'),
                  painter: _MeasurementPainter(points, unit),
                ),
              ),
            ),
          ),
        ),
        if (points.length == 1)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Tek ölçüm var; değişim çizgisi için yeni bir ölçüm ekleyebilirsin.',
              style: TextStyle(fontSize: 12, color: OnboardingTheme.muted),
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE8EDE3))),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            children: [
              value('İlk kayıt', points.first.value),
              value('Son kayıt', points.last.value),
            ],
          ),
        ),
      ],
    );
  }
}

class _MeasurementPainter extends CustomPainter {
  _MeasurementPainter(this.points, this.unit);
  final List<MeasurementPoint> points;
  final String unit;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 100 || points.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 350, size.height / 185);
    final min = points.map((p) => p.value.toDouble()).reduce(math.min),
        max = points.map((p) => p.value.toDouble()).reduce(math.max);
    final padding = math.max(.6, max.abs() * .01);
    final low = math.max(0.0, (min - padding).floorToDouble());
    final high = math.max(
      low + 1,
      unit == '%'
          ? math.min(100.0, (max + padding).ceilToDouble())
          : (max + padding).ceilToDouble(),
    );
    final first = points.first.at.microsecondsSinceEpoch,
        last = points.last.at.microsecondsSinceEpoch;
    Offset at(MeasurementPoint p) => Offset(
      first == last
          ? 181
          : 40 + (p.at.microsecondsSinceEpoch - first) / (last - first) * 282,
      35 + (high - p.value) / (high - low) * 102,
    );
    void text(
      String value,
      Offset p, {
      Color color = OnboardingTheme.muted,
      double fontSize = 10,
      TextAlign align = TextAlign.left,
      FontWeight weight = FontWeight.w400,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: fontSize,
            color: color,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          p.dx -
              (align == TextAlign.right
                  ? painter.width
                  : align == TextAlign.center
                  ? painter.width / 2
                  : 0),
          p.dy,
        ),
      );
    }

    text(unit, const Offset(0, 7), fontSize: 9);
    final grid = Paint()
      ..color = const Color(0xFFE4EBDC)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 35.0 + i * 51, value = high - (high - low) * i / 2;
      for (var x = 40.0; x < 330; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, 330), y), grid);
      }
      text(measurementValue(value), Offset(0, y - 5));
    }
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    if (points.length > 1) {
      final area = Path.from(path)
        ..lineTo(at(points.last).dx, 144)
        ..lineTo(at(points.first).dx, 144)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              OnboardingTheme.lime.withValues(alpha: .65),
              OnboardingTheme.lime.withValues(alpha: .04),
            ],
          ).createShader(const Rect.fromLTWH(40, 35, 290, 109)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF83B977)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    for (var i = 0; i < points.length; i++) {
      final selected = i == points.length - 1, p = at(points[i]);
      canvas.drawCircle(
        p,
        selected ? 6 : 4,
        Paint()
          ..color = selected
              ? OnboardingTheme.background
              : const Color(0xFF83B977),
      );
      canvas.drawCircle(
        p,
        selected ? 4.5 : 2.5,
        Paint()
          ..color = selected ? OnboardingTheme.ink : OnboardingTheme.background,
      );
    }
    final selected = at(points.last),
        bx = (selected.dx - 29).clamp(40.0, 263.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, selected.dy - 33, 67, 24),
        const Radius.circular(8),
      ),
      Paint()..color = OnboardingTheme.ink,
    );
    text(
      measurementValue(points.last.value, minimumDecimal: true),
      Offset(bx + 33.5, selected.dy - 28),
      color: OnboardingTheme.background,
      fontSize: 11,
      weight: FontWeight.w600,
      align: TextAlign.center,
    );
    final indices = points.length == 1
        ? [0]
        : points.length == 2
        ? [0, 1]
        : [0, (points.length - 1) ~/ 2, points.length - 1];
    for (final i in indices) {
      text(
        measurementDate(points[i].at, year: false),
        Offset(at(points[i]).dx, 157),
        align: i == 0
            ? TextAlign.left
            : i == points.length - 1
            ? TextAlign.right
            : TextAlign.center,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeasurementPainter old) =>
      old.points != points || old.unit != unit;
}
