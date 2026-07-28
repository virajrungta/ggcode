import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Slowly drifting radial gradients behind the glass layer.
///
/// This exists because frosted glass over a flat fill is indistinguishable
/// from a flat grey card — the blur has nothing to sample. The depth people
/// read as "glassy" comes entirely from colour variation *behind* the surface.
///
/// Painted with a `CustomPainter` rather than stacked `Container`s: it is one
/// draw call into a single layer, it never rebuilds the widget tree, and it
/// sits behind every `BackdropFilter` in the app, so it is the one thing every
/// blurred surface samples every frame.
class MeshBackground extends StatefulWidget {
  const MeshBackground({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;

  /// Disable for tests, screenshots, or a battery-saver setting.
  final bool animate;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GGDuration.ambient,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(MeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GGColors.bgDeep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Isolated so the drifting gradient never repaints the UI above it.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _MeshPainter(_controller.value),
                isComplex: true,
                willChange: widget.animate,
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.t);

  /// 0..1, wrapping.
  final double t;

  static const _blobs = [
    (color: GGColors.volt, alpha: 0.16, radius: 0.75, phase: 0.0),
    (color: GGColors.cyan, alpha: 0.13, radius: 0.65, phase: 0.38),
    (color: GGColors.magenta, alpha: 0.07, radius: 0.55, phase: 0.71),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);

    for (final blob in _blobs) {
      final angle = (t + blob.phase) * 2 * math.pi;

      // Lissajous drift: the two axes use different frequencies so the blobs
      // never retrace the same loop, which would read as a visible cycle.
      final center = Offset(
        size.width * (0.5 + 0.34 * math.cos(angle)),
        size.height * (0.42 + 0.30 * math.sin(angle * 0.73)),
      );

      final radius = diagonal * blob.radius;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              blob.color.withValues(alpha: blob.alpha),
              blob.color.withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) => oldDelegate.t != t;
}
