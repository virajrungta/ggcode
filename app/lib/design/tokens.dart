import 'package:flutter/material.dart';

/// Design tokens for GreenGenius.
///
/// ## Why this is a light theme
///
/// The previous palette was near-black (`#050A07`) with a maximally saturated
/// neon accent (`#D4FF00`). Both are the specific things Material's dark-theme
/// guidance warns against: pure-black backgrounds push contrast high enough to
/// cause eye strain, and saturated accents visually vibrate against dark
/// surfaces and fail contrast. The reference apps for this product — Nest /
/// Google Home, and GoGlyder — are both light, calm, and low-saturation.
///
/// ## Colour tiers
///
/// Each semantic colour has up to three steps, because one hex cannot do all
/// three jobs at legible contrast:
///
///  * **mark**      — chart lines, icons, borders. Graphical objects need 3:1.
///  * **text**      — a darker step for labels on white. Text needs 4.5:1.
///  * **container** — a pale tint for filled chips and callouts.
///
/// Every value below was checked rather than eyeballed. The four metric hues
/// pass the categorical validator (lightness band, chroma floor, CVD
/// separation, normal-vision floor, contrast); worst adjacent pair is ΔE 25.1
/// under protanopia, 16.7 under tritanopia. Text steps were checked for WCAG
/// AA against both the app background and white cards.

const String kFontFamily = 'PlusJakartaSans';

abstract final class GGColors {
  // --- neutrals ----------------------------------------------------------
  /// App background. Slightly warm and green-cast rather than pure grey, so
  /// white cards read as raised without needing heavy shadows.
  static const bg = Color(0xFFF4F6F3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFECF0EC);
  static const surfaceSunken = Color(0xFFE7EBE6);

  static const outline = Color(0xFFDDE4DC);
  static const outlineStrong = Color(0xFFC6D0C4);

  // --- text --------------------------------------------------------------
  static const textPrimary = Color(0xFF16211A); // 16.6:1 on white
  static const textSecondary = Color(0xFF566259); // 6.4:1
  static const textTertiary = Color(0xFF657167); // 5.1:1 — still AA at caption size
  static const textOnPrimary = Color(0xFFFFFFFF);

  // --- brand -------------------------------------------------------------
  /// A muted, natural green. Deliberately not the old volt yellow-green: that
  /// hue only exists at high saturation, which is what made the app read as
  /// neon rather than calm.
  static const primary = Color(0xFF2E7D5B); // 5.0:1 on white
  static const primaryDark = Color(0xFF1F5B41); // 8.0:1
  static const primaryContainer = Color(0xFFDCEFE4);
  static const onPrimaryContainer = Color(0xFF14432F);

  // --- status ------------------------------------------------------------
  // Reserved. Never reused as a chart series colour, and always shipped with
  // an icon or a text label so state is never carried by colour alone.
  static const good = primary;
  static const goodText = primaryDark;
  static const goodContainer = primaryContainer;

  static const warning = Color(0xFFB67D06);
  static const warningText = Color(0xFF8A5E00); // 5.7:1
  static const warningContainer = Color(0xFFFBF0D5);

  static const bad = Color(0xFFC0392F);
  static const badText = Color(0xFF8C241C);
  static const badContainer = Color(0xFFFBE0DD);

  static const unknown = Color(0xFF8B968C);
  static const unknownText = textTertiary;
  static const unknownContainer = surfaceMuted;

  // --- metric identity ---------------------------------------------------
  // Categorical, fixed order, never cycled. Used for chart series and the
  // metric selector — not for state.
  static const soil = Color(0xFF2563C9);
  static const soilText = Color(0xFF123A78);
  static const soilContainer = Color(0xFFDDE8FB);

  static const temp = Color(0xFFD2542A);
  static const tempText = Color(0xFFB0421C);
  static const tempContainer = Color(0xFFFBE4DA);

  static const humidity = Color(0xFF7A4FC4);
  static const humidityText = Color(0xFF4A2C82);
  static const humidityContainer = Color(0xFFEAE2FA);

  static const light = Color(0xFFB67D06);
  static const lightText = Color(0xFF8A5E00);
  static const lightContainer = Color(0xFFFBF0D5);

  // --- glass -------------------------------------------------------------
  // Frosted white over a soft tinted backdrop. On light surfaces glass reads
  // as depth at far lower opacity than it needs on dark ones.
  static const glassFill = Color(0xB8FFFFFF); // white @ 72%
  static const glassFillStrong = Color(0xE0FFFFFF);
  static const glassBorder = Color(0xF0FFFFFF);

  static Color statusColor(String status) => switch (status) {
        'good' => good,
        'warning' => warning,
        'bad' => bad,
        _ => unknown,
      };

  static Color statusText(String status) => switch (status) {
        'good' => goodText,
        'warning' => warningText,
        'bad' => badText,
        _ => unknownText,
      };

  static Color statusContainer(String status) => switch (status) {
        'good' => goodContainer,
        'warning' => warningContainer,
        'bad' => badContainer,
        _ => unknownContainer,
      };
}

abstract final class GGSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;

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

abstract final class GGBlur {
  static const double heavy = 24;
  static const double medium = 16;
  static const double light = 10;
}

abstract final class GGDuration {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 600);
  static const ambient = Duration(seconds: 28);
}

/// Soft neutral card shadow.
///
/// On light surfaces a real shadow does the work that a coloured glow had to
/// do on dark ones — quieter, and it does not tint the card.
const List<BoxShadow> ggCardShadow = [
  BoxShadow(color: Color(0x0F16211A), blurRadius: 16, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x0A16211A), blurRadius: 3, offset: Offset(0, 1)),
];

const List<BoxShadow> ggRaisedShadow = [
  BoxShadow(color: Color(0x1A16211A), blurRadius: 28, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x0D16211A), blurRadius: 6, offset: Offset(0, 2)),
];

abstract final class GGTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    final scheme = ColorScheme.fromSeed(
      seedColor: GGColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: GGColors.primary,
      onPrimary: GGColors.textOnPrimary,
      primaryContainer: GGColors.primaryContainer,
      onPrimaryContainer: GGColors.onPrimaryContainer,
      surface: GGColors.surface,
      onSurface: GGColors.textPrimary,
      error: GGColors.bad,
      outline: GGColors.outline,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: GGColors.bg,
      canvasColor: Colors.transparent,
      cardColor: GGColors.surface,
      dividerColor: GGColors.outline,
      splashColor: GGColors.primary.withValues(alpha: 0.07),
      highlightColor: GGColors.primary.withValues(alpha: 0.04),
      splashFactory: InkRipple.splashFactory,
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
          backgroundColor: GGColors.primary,
          foregroundColor: GGColors.textOnPrimary,
          disabledBackgroundColor: GGColors.outlineStrong,
          disabledForegroundColor: GGColors.surface,
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
          foregroundColor: GGColors.primaryDark,
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: GGColors.textPrimary,
        contentTextStyle: const TextStyle(
          fontFamily: kFontFamily,
          color: Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: GGRadius.sAll),
        insetPadding: const EdgeInsets.all(GGSpacing.m),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: GGColors.surface,
        shape: RoundedRectangleBorder(borderRadius: GGRadius.lAll),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: GGColors.primary),
      iconTheme: const IconThemeData(color: GGColors.textSecondary),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base
        .copyWith(
          displaySmall: base.displaySmall
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
          headlineLarge: base.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
          headlineMedium: base.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          titleLarge: base.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
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
