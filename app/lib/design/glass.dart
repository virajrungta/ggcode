import 'dart:ui';

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A frosted-glass surface.
///
/// ## Performance
///
/// `BackdropFilter` is one of the most expensive widgets in Flutter. Each one
/// forces a `saveLayer`, which allocates an offscreen buffer the size of the
/// clip and blurs it every frame. The cost scales with area, not with content,
/// so a full-width card is far worse than a chip.
///
/// The rules this widget is built around:
///
///  * **Never inside a scrolling list item.** A `ListView` of 20 glass cards
///    is 20 saveLayers per frame and will drop frames on mid-range Android.
///    Use [FauxGlassSurface] for repeated elements — it approximates the look
///    with a plain gradient and costs essentially nothing.
///  * **Cap at ~3 real blurs on screen.** Typically: nav bar, one hero card,
///    one modal.
///  * Always clipped, so the blur region is bounded.
///  * Wrapped in a `RepaintBoundary`, so a repaint in a sibling doesn't
///    re-blur this subtree.
///
/// Set [enabled] to false to degrade to the cheap path — useful for a
/// low-end-device setting or golden tests.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = GGBlur.medium,
    this.radius = GGRadius.l,
    this.padding = const EdgeInsets.all(GGSpacing.m),
    this.fill,
    this.glowColor,
    this.enabled = true,
  });

  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? fill;

  /// Optional accent glow. Used sparingly — on a plant-health card it carries
  /// meaning (volt = healthy, amber = attention), so it should not be decoration.
  final Color? glowColor;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fill ?? GGColors.glassFillStrong,
            fill ?? GGColors.glassFill,
          ],
        ),
        border: Border.all(color: GGColors.glassBorderTop, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );

    Widget result = ClipRRect(
      borderRadius: borderRadius,
      child: enabled
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: surface,
            )
          : surface,
    );

    if (glowColor != null) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.18),
              blurRadius: 32,
              spreadRadius: -8,
            ),
          ],
        ),
        child: result,
      );
    }

    return RepaintBoundary(child: result);
  }
}

/// Glass-*looking* surface with no blur.
///
/// Visually near-identical to [GlassSurface] at a fraction of the cost, because
/// it never calls `saveLayer`. This is what belongs in lists, grids, and
/// anything that repeats — the difference is only perceptible when there is
/// high-contrast content directly behind the surface, which in a list there
/// generally isn't.
class FauxGlassSurface extends StatelessWidget {
  const FauxGlassSurface({
    super.key,
    required this.child,
    this.radius = GGRadius.l,
    this.padding = const EdgeInsets.all(GGSpacing.m),
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
        ),
        border: Border.all(
          color: borderColor ?? GGColors.glassBorderTop,
          width: 1,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
