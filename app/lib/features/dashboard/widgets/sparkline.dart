import 'package:flutter/material.dart';

import '../../../design/tokens.dart';

/// A tiny inline trend line.
///
/// Hand-painted rather than an fl_chart instance: a sparkline has no axes,
/// no grid, no tooltip and no legend, so a full chart widget is several
/// hundred objects of machinery to draw one path. This is a single path plus
/// a fill, and it can sit inside a grid tile without costing anything.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 2,
    this.showFill = true,
    this.showEndDot = true,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool showFill;
  final bool showEndDot;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          color: color,
          strokeWidth: strokeWidth,
          showFill: showFill,
          showEndDot: showEndDot,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.showFill,
    required this.showEndDot,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool showFill;
  final bool showEndDot;

  @override
  void paint(Canvas canvas, Size size) {
    var min = values.first, max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    // A flat series would divide by zero and collapse to the top edge; centre
    // it instead so "nothing changed" reads as a level line.
    final span = (max - min).abs() < 1e-6 ? 1.0 : max - min;
    final inset = strokeWidth + (showEndDot ? 2.5 : 0);

    Offset at(int i) {
      final x = size.width * (i / (values.length - 1));
      final norm = (values[i] - min) / span;
      final y = inset + (size.height - inset * 2) * (1 - norm);
      return Offset(x, y);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = at(i), prev = at(i - 1);
      // Horizontal-tangent cubic: smooths the line without the overshoot a
      // Catmull-Rom spline produces, which on a sensor trace would invent
      // peaks that the data never had.
      final cx = (prev.dx + p.dx) / 2;
      path.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
    }

    if (showFill) {
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    if (showEndDot) {
      final end = at(values.length - 1);
      canvas.drawCircle(end, strokeWidth + 1.5,
          Paint()..color = GGColors.surface);
      canvas.drawCircle(end, strokeWidth, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}
