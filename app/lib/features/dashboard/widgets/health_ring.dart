import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/tokens.dart';

/// Circular health gauge. Ported from the RN `CircularProgress`/
/// `PlantRingDashboard` pair, with one behavioural change: a null score
/// renders as an explicit "no data" state rather than an empty ring.
///
/// An empty ring and a 0% ring are visually near-identical, and the difference
/// between "this plant is dying" and "the sensor is offline" is exactly the
/// thing the user needs to tell apart.
class HealthRing extends StatelessWidget {
  const HealthRing({
    super.key,
    required this.score,
    required this.status,
    this.size = 180,
    this.strokeWidth = 12,
  });

  /// 0..100, or null when nothing could be assessed.
  final int? score;
  final String status;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final color = GGColors.statusColor(status);
    final hasScore = score != null;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: hasScore ? score! / 100 : 0),
            duration: GGDuration.slow,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: value,
                color: color,
                strokeWidth: strokeWidth,
                showTrackOnly: !hasScore,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasScore) ...[
                Text(
                  '$score',
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: size * 0.30,
                    fontWeight: FontWeight.w800,
                    color: GGColors.textPrimary,
                    height: 1,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: GGSpacing.xs),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1.5,
                  ),
                ),
              ] else ...[
                Icon(Icons.sensors_off_rounded,
                    size: size * 0.2, color: GGColors.textTertiary),
                const SizedBox(height: GGSpacing.s),
                const Text(
                  'NO DATA',
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: GGColors.textTertiary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.showTrackOnly,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final bool showTrackOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    if (showTrackOnly || progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;
    final sweep = 2 * math.pi * progress;

    // Glow underneath, so the arc reads as emissive rather than painted.
    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          colors: [color.withValues(alpha: 0.55), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.showTrackOnly != showTrackOnly;
}
