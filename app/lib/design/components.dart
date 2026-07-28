import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'tokens.dart';

/// Staggered entrance used across screens.
///
/// GoGlyder applies fade + slide with an increasing delay down the page, which
/// is what makes a screen feel composed rather than dumped. Wrapped in a
/// helper so the timings stay identical everywhere instead of being retyped
/// with slightly different numbers on each screen.
extension GGEntrance on Widget {
  Widget entrance({int index = 0}) => animate(delay: (60 * index).ms)
      .fadeIn(duration: 420.ms)
      .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic);
}

/// An icon in a filled, rounded square.
class GGIconTile extends StatelessWidget {
  const GGIconTile({
    super.key,
    required this.icon,
    this.color = GGColors.volt,
    this.size = 48,
    this.iconSize = 22,
    this.filled = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

class GGSectionHeader extends StatelessWidget {
  const GGSectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: GGColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// Small uppercase label above a value. Used for metric captions.
class GGCaption extends StatelessWidget {
  const GGCaption(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color ?? GGColors.textSecondary,
        letterSpacing: 1.4,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Tappable card with correct ink feedback.
///
/// `Material` + `InkWell` rather than `GestureDetector`: a card that does not
/// visibly respond to touch is the clearest tell of an unfinished app, and a
/// bare GestureDetector gives no feedback at all.
class GGTappable extends StatelessWidget {
  const GGTappable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = GGRadius.l,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: GGColors.volt.withValues(alpha: 0.08),
        highlightColor: GGColors.volt.withValues(alpha: 0.04),
        child: child,
      ),
    );
  }
}

/// Compact square action button with a label, for a quick-actions row.
class GGQuickAction extends StatelessWidget {
  const GGQuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.color = GGColors.volt,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GGTappable(
      onTap: onTap,
      radius: GGRadius.l,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: GGSpacing.m),
        decoration: BoxDecoration(
          borderRadius: GGRadius.lAll,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(color: GGColors.glassBorderTop),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: GGSpacing.s),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GGColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill — a dot plus a short label.
class GGStatusPill extends StatelessWidget {
  const GGStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.glowing = false,
  });

  final String label;
  final Color color;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: GGSpacing.m, vertical: GGSpacing.s - 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(GGRadius.round),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: glowing
                  ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 7)]
                  : null,
            ),
          ),
          const SizedBox(width: GGSpacing.s),
          Text(
            label,
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed gradient header with rounded bottom corners.
///
/// The strongest structural device in GoGlyder's home screen: it anchors the
/// top of the page and gives the scroll something to run out from, instead of
/// text starting cold against the background.
class GGHeroHeader extends StatelessWidget {
  const GGHeroHeader({
    super.key,
    required this.child,
    this.accent = GGColors.volt,
  });

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        GGSpacing.l,
        MediaQuery.of(context).padding.top + GGSpacing.l,
        GGSpacing.l,
        GGSpacing.xl,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GGColors.heroFrom, GGColors.heroTo],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(GGRadius.hero),
          bottomRight: Radius.circular(GGRadius.hero),
        ),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.18)),
        ),
      ),
      child: child,
    );
  }
}

class GGEmptyState extends StatelessWidget {
  const GGEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GGSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GGIconTile(icon: icon, size: 72, iconSize: 32,
              color: GGColors.textTertiary),
          const SizedBox(height: GGSpacing.l),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: GGColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: GGSpacing.s),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 14,
              color: GGColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: GGSpacing.l),
            action!,
          ],
        ],
      ),
    );
  }
}
