import 'package:flutter/material.dart';

import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../../onboarding/pair_pot_screen.dart';

/// Persistent "add another pot" entry at the end of the dashboard.
///
/// Pairing used to live only under Settings → Device → Pair a new pot: three
/// taps deep, in the place people go to change things rather than to add
/// them. Adding a pot is the single most important action for anyone who owns
/// fewer pots than they intend to, so it belongs on the home screen.
///
/// Dashed rather than solid so it reads as a slot to fill rather than a card
/// with content — the standard visual language for "add" in a list.
class AddPotCard extends StatelessWidget {
  const AddPotCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GGTappable(
      radius: GGRadius.l,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PairPotScreen()),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: GGColors.primary.withValues(alpha: 0.45),
          radius: GGRadius.l,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: GGSpacing.l, horizontal: GGSpacing.m),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const GGIconTile(icon: Icons.add_rounded, size: 40, iconSize: 20),
              const SizedBox(width: GGSpacing.m - 2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pair another pot',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GGColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Takes about a minute',
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 12.5,
                      color: GGColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded rectangle. Flutter has no dashed border out of the box, and
/// a package for one stroke is not worth the dependency.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // Walk the outline and emit alternating segments. computeMetrics() is
    // what makes a path traversable by distance; a Path itself is not
    // iterable.
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
