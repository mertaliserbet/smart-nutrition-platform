import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'body_measurement_api.dart';

typedef MeasurementPoint = ({DateTime at, num value});
List<MeasurementPoint> measurementPoints(
  List<BodyMeasurement> rows,
  String field,
) {
  final ordered = rows.where((row) => row.values[field] != null).toList()
    ..sort((a, b) {
      final time = a.measuredAt.compareTo(b.measuredAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  return List.unmodifiable(
    ordered.map((row) => (at: row.measuredAt, value: row.values[field]!)),
  );
}

class MeasurementChart extends StatelessWidget {
  const MeasurementChart({required this.rows, required this.field, super.key});
  final List<BodyMeasurement> rows;
  final String field;
  @override
  Widget build(BuildContext context) {
    final points = measurementPoints(rows, field);
    final label = measurementLabels[field]!, unit = measurementUnit(field);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label gelişimi ($unit)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (points.isEmpty)
              Text('Henüz ${label.toLowerCase()} ölçümü yok.')
            else ...[
              Text('${points.length} ölçüm · Son: ${points.last.value} $unit'),
              Semantics(
                label:
                    '$label grafiği. ${points.length} ölçüm. İlk: ${formatMeasurementTime(points.first.at)}, ${points.first.value} $unit. Son: ${formatMeasurementTime(points.last.at)}, ${points.last.value} $unit.',
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: CustomPaint(
                    key: ValueKey('measurement-chart-$field'),
                    painter: _MeasurementPainter(
                      points,
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (points.length == 1)
                const Text(
                  'Tek ölçüm var; gelişim çizgisi için yeni bir ölçüm ekleyin.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MeasurementPainter extends CustomPainter {
  _MeasurementPainter(this.points, this.color, this.textColor);
  final List<MeasurementPoint> points;
  final Color color, textColor;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 100) return;
    final plot = Rect.fromLTRB(54, 16, size.width - 8, size.height - 40);
    var low = points.map((p) => p.value.toDouble()).reduce(math.min);
    var high = points.map((p) => p.value.toDouble()).reduce(math.max);
    final pad = math.max((high - low) * .1, math.max(high.abs() * .01, .1));
    low -= pad;
    high += pad;
    final first = points.first.at.microsecondsSinceEpoch,
        last = points.last.at.microsecondsSinceEpoch;
    Offset position(MeasurementPoint point) => Offset(
      last == first
          ? plot.center.dx
          : plot.left +
                (point.at.microsecondsSinceEpoch - first) /
                    (last - first) *
                    plot.width,
      plot.bottom - (point.value - low) / (high - low) * plot.height,
    );
    void label(String text, Offset at, {bool right = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: textColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(right ? at.dx - painter.width : at.dx, at.dy),
      );
    }

    final axis = Paint()
      ..color = textColor.withValues(alpha: .25)
      ..strokeWidth = 1;
    for (final value in [low, (low + high) / 2, high]) {
      final y = plot.bottom - (value - low) / (high - low) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), axis);
      label(value.toStringAsFixed(1), Offset(0, y - 6));
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    String date(DateTime value) {
      final local = value.toLocal();
      return '${local.day}.${local.month}.${local.year}';
    }

    label(date(points.first.at), Offset(plot.left, plot.bottom + 10));
    if (last != first) {
      label(
        date(points.last.at),
        Offset(plot.right, plot.bottom + 10),
        right: true,
      );
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(position(points.first).dx, position(points.first).dy);
    for (final point in points.skip(1)) {
      final at = position(point);
      path.lineTo(at.dx, at.dy);
    }
    if (points.length > 1) canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(position(point), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _MeasurementPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.textColor != textColor;
}
