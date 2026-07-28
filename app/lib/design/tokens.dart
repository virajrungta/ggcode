import 'package:flutter/material.dart';

/// Design tokens ported from the Expo app's `src/theme/index.ts`.
///
/// The palette carries over unchanged — the volt-green-on-near-black identity
/// was the strongest part of the old app. What changes is the surface
/// treatment: the RN version had a `GlassStyles` block that was explicitly
/// deprecated down to flat `#0F1612` cards. Here glass is real, so surfaces
/// are translucent and the depth comes from what shows through them.
abstract final class GGColors {
  // Core identity
  static const volt = Color(0xFFD4FF00);
  static const bgDeep = Color(0xFF050A07);
  static const surface = Color(0xFF0F1612);

  // Accents for rings and charts
  static const cyan = Color(0xFF2DE2E6);
  static const magenta = Color(0xFFF706CF);
  static const amber = Color(0xFFFF9100);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textTertiary = Color(0xFF555555);

  // Status. Deliberately not red/green: the volt-green already means "good"
  // everywhere else in this palette, and a second green would compete with it.
  static const good = volt;
  static const warning = amber;
  static const bad = magenta;
  static const unknown = Color(0xFF555555);

  /// Glass fill and border. Two borders, not one — a brighter top edge and a
  /// dimmer bottom reads as a lit pane of glass rather than an outlined box.
  static const glassFill = Color(0x0FFFFFFF); // white @ ~6%
  static const glassFillStrong = Color(0x1AFFFFFF); // white @ ~10%
  static const glassBorderTop = Color(0x2EFFFFFF); // white @ ~18%
  static const glassBorderBottom = Color(0x0AFFFFFF); // white @ ~4%

  static Color statusColor(String status) => switch (status) {
        'good' => good,
        'warning' => warning,
        'bad' => bad,
        _ => unknown,
      };
}

abstract final class GGSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class GGRadius {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double round = 9999;
}

/// Blur sigmas. Kept as named constants rather than inline numbers because
/// they are a performance budget, not a style choice — see [GlassSurface].
abstract final class GGBlur {
  /// Full-strength blur. Reserve for at most one or two surfaces per screen.
  static const double heavy = 24;

  /// Default for cards.
  static const double medium = 16;

  /// Nav bars and small chips.
  static const double light = 10;
}

abstract final class GGDuration {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 600);

  /// Background mesh drift. Deliberately very slow — fast movement behind
  /// frosted glass reads as a rendering glitch rather than atmosphere.
  static const ambient = Duration(seconds: 24);
}
