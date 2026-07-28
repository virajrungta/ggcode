import 'package:flutter/material.dart';

/// Design tokens for GreenGenius.
///
/// The palette is carried over from the Expo app's `src/theme/index.ts` — the
/// volt-green-on-near-black identity was the strongest part of it. Structure
/// and typography follow the conventions in GoGlyder: one bundled typeface,
/// a fully-specified [ThemeData] so screens never restyle components locally,
/// and a fixed radius/spacing scale.

/// Bundled variable typeface. Applied app-wide through the text theme.
///
/// This matters more than any single widget: Flutter's default Roboto is what
/// makes an app read as a prototype no matter how the rest is composed.
const String kFontFamily = 'PlusJakartaSans';

abstract final class GGColors {
  // Brand
  static const volt = Color(0xFFD4FF00);
  static const voltDim = Color(0xFF9BBF00);
  static const bgDeep = Color(0xFF050A07);
  static const bgRaised = Color(0xFF0B120E);
  static const surface = Color(0xFF0F1612);

  /// Solid surface tiers. GoGlyder uses opaque surfaces throughout, and it is
  /// the right call: translucency everywhere makes a UI feel washed out and
  /// costs a saveLayer per surface. Glass is now an accent for one hero card
  /// per screen, not the base material.
  static const surface1 = Color(0xFF0C130F); // cards
  static const surface2 = Color(0xFF131C17); // raised / nav
  static const surface3 = Color(0xFF1A241E); // pressed, inputs
  static const hairline = Color(0xFF1F2B24);

  // Gradient stops for hero surfaces.
  static const heroFrom = Color(0xFF0C2A1B);
  static const heroTo = Color(0xFF04120A);

  // Accents
  static const cyan = Color(0xFF2DE2E6);
  static const magenta = Color(0xFFF706CF);
  static const amber = Color(0xFFFF9100);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA3AFA8);
  static const textTertiary = Color(0xFF5C6B62);

  // Status. Not red/green: volt already reads as "good" everywhere else,
  // and a second green would compete with it.
  static const good = volt;
  static const warning = amber;
  static const bad = magenta;
  static const unknown = Color(0xFF5C6B62);

  // Glass. Two border tones — a brighter top edge and a dimmer bottom reads
  // as a lit pane rather than an outlined box.
  static const glassFill = Color(0x0FFFFFFF);
  static const glassFillStrong = Color(0x1AFFFFFF);
  static const glassBorderTop = Color(0x2EFFFFFF);
  static const glassBorderBottom = Color(0x0AFFFFFF);

  static Color statusColor(String status) => switch (status) {
        'good' => good,
        'warning' => warning,
        'bad' => bad,
        _ => unknown,
      };

  /// Gradient for a status-tinted surface.
  static LinearGradient statusGradient(String status) {
    final c = statusColor(status);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.04)],
    );
  }
}

abstract final class GGSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Standard page gutter, so every screen lines up.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 20);
}

abstract final class GGRadius {
  static const double s = 12;
  static const double m = 16;
  static const double l = 20;
  static const double xl = 28;
  static const double hero = 32;
  static const double round = 9999;

  static BorderRadius get sAll => BorderRadius.circular(s);
  static BorderRadius get mAll => BorderRadius.circular(m);
  static BorderRadius get lAll => BorderRadius.circular(l);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}

/// Blur sigmas. Named constants because they are a performance budget, not a
/// style choice — see `GlassSurface`.
abstract final class GGBlur {
  static const double heavy = 24;
  static const double medium = 16;
  static const double light = 10;
}

abstract final class GGDuration {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 600);

  /// Background mesh drift. Deliberately slow — fast movement behind frosted
  /// glass reads as a rendering glitch rather than atmosphere.
  static const ambient = Duration(seconds: 24);
}

/// Ambient glow beneath raised surfaces. On a dark UI a black drop shadow is
/// invisible, so depth has to come from coloured light instead.
List<BoxShadow> ggGlow(Color color, {double opacity = 0.25, double blur = 28}) =>
    [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: -6,
        offset: const Offset(0, 8),
      ),
    ];

abstract final class GGTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    final scheme = base.colorScheme.copyWith(
      primary: GGColors.volt,
      onPrimary: GGColors.bgDeep,
      secondary: GGColors.cyan,
      surface: GGColors.surface,
      error: GGColors.bad,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: GGColors.bgDeep,
      // Surfaces are translucent glass over the mesh background, so opaque
      // Material defaults would flatten the whole effect.
      canvasColor: Colors.transparent,
      cardColor: Colors.transparent,
      dividerColor: Colors.white.withValues(alpha: 0.08),
      splashColor: GGColors.volt.withValues(alpha: 0.10),
      highlightColor: GGColors.volt.withValues(alpha: 0.05),
      splashFactory: InkRipple.splashFactory,

      // iOS-style slide transitions on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      textTheme: _textTheme(base.textTheme),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: GGColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: kFontFamily,
          color: GGColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GGColors.volt,
          foregroundColor: GGColors.bgDeep,
          disabledBackgroundColor: GGColors.volt.withValues(alpha: 0.35),
          disabledForegroundColor: GGColors.bgDeep.withValues(alpha: 0.5),
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(borderRadius: GGRadius.mAll),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GGColors.volt,
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: GGColors.surface,
        contentTextStyle: const TextStyle(
          fontFamily: kFontFamily,
          color: GGColors.textPrimary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: GGRadius.sAll),
        insetPadding: const EdgeInsets.all(GGSpacing.m),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: GGColors.surface,
        shape: RoundedRectangleBorder(borderRadius: GGRadius.lAll),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: GGColors.volt,
      ),

      iconTheme: const IconThemeData(color: GGColors.textSecondary),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
          headlineLarge: base.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
          labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(
          fontFamily: kFontFamily,
          bodyColor: GGColors.textPrimary,
          displayColor: GGColors.textPrimary,
        );
  }
}
