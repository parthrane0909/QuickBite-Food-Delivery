/// Design tokens — QuickBite visual system (UI rehaul).
///
/// Direction: the warm, food-led template (vivid coral CTA on warm darks,
/// white cards over cream, big photography, pill controls). ALL colors,
/// shadows, radii and motion durations live here — screens and widgets
/// reference tokens, never raw values (master prompt §6).
///
/// Contrast: `primary` is calibrated so WHITE text on coral reaches WCAG
/// AA (>= 4.5:1); ink tones are AA on the cream/surface backgrounds.
library;

import 'package:flutter/material.dart';

/// Core palette.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFFDB3A1F); // vivid coral-red (AA w/ white)
  static const Color primaryDark = Color(0xFFB22C14); // pressed / high-emphasis
  static const Color primaryDeep = Color(0xFF7E1D0C); // gradient end / dark brand
  static const Color primaryTint = Color(0xFFFFF0EB); // coral 50 — soft chips

  // Warm neutrals (surfaces)
  static const Color background = Color(0xFFFCF7F2); // warm off-white / cream
  static const Color surface = Color(0xFFFFFFFF); // cards
  static const Color surfaceWarm = Color(0xFFF9EFE8); // cream sections / wells
  static const Color outlineSoft = Color(0xFFEFE2D8); // hairlines, borders

  // Warm darks — hero bands, dark headers, on-photo scrims (template look)
  static const Color charcoal = Color(0xFF1C1411); // deep warm black
  static const Color charcoalSoft = Color(0xFF2A1F1A); // raised dark surface
  static const Color onDark = Color(0xFFFFFBF8); // text/icons on warm darks
  static const Color onDarkSoft = Color(0xFFD9CCC4); // secondary text on darks

  // Ink
  static const Color ink = Color(0xFF1C1614); // headings, primary text
  static const Color inkSoft = Color(0xFF6E635C); // secondary text (AA on cream)
  static const Color inkFaint = Color(0xFF9A8D84); // tertiary/disabled text

  // Accents
  static const Color peach = Color(0xFFFCE0D5); // quantity steppers, soft fills
  static const Color peachStrong = Color(0xFFF8C9B6); // stepper pressed
  static const Color success = Color(0xFF237A46); // open/ok (AA w/ white)
  static const Color successTint = Color(0xFFE4F3E9);
  static const Color danger = Color(0xFFB3261E); // failures (AA w/ white)
  static const Color dangerTint = Color(0xFFFBEAE8);
  static const Color warning = Color(0xFF8A5A00); // pending text (AA on tint)
  static const Color warningTint = Color(0xFFFFF3DC);
  static const Color info = Color(0xFF1F6A8A); // confirmed/info text
  static const Color infoTint = Color(0xFFE3F1F7);

  // Immersive brand red — full-bleed onboarding / sign-in backgrounds
  // (reference-led: a vivid red field with a soft radial lift in the middle).
  static const Color brandRed = Color(0xFFE2372A); // vivid red field
  static const Color brandRedDeep = Color(0xFFB22318); // gradient mid
  static const Color brandRedDark = Color(0xFF7C160D); // gradient end / status bar
  static const Color onBrandRed = Color(0xFFFFFFFF);
  static const Color onBrandRedSoft = Color(0xCCFFFFFF);

  // On-color text/icons
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimarySoft = Color(0xFFFFE4DB);

  // Dark surface used for photographic hero headers
  static const Color heroScrim = Color(0xCC2A1A14);

  /// CTA gradient (coral -> deep) — the template's primary button feel.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  /// Warm dark gradient for photographic heroes (transparent -> deep).
  static const LinearGradient heroFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x001C1411), Color(0x661C1411), Color(0xE61C1411)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Immersive brand-red field: deep red top -> vivid middle -> dark bottom.
  static const LinearGradient brandRedGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandRedDark, brandRedDeep, brandRed, brandRedDeep],
    stops: [0.0, 0.22, 0.62, 1.0],
  );

  /// Soft radial lift over [brandRedGradient] (the reference's centre glow).
  static const RadialGradient brandRedGlow = RadialGradient(
    center: Alignment(0, -0.25),
    radius: 1.05,
    colors: [Color(0x47FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.45, 1.0],
  );

  /// Dark discovery band for the home header (photo + scrim friendly).
  static const LinearGradient heroBand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [charcoal, Color(0xFF3A2419), primaryDeep],
    stops: [0.0, 0.55, 1.0],
  );

  /// Scrim used behind text on top-of-image areas.
  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x991C1411), Color(0x001C1411)],
  );
}

/// Spacing scale (4pt grid), corner radii, sizes, elevation shadows and
/// motion durations — one source of truth for rhythmic, consistent layouts.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double screenPadding = 20; // default screen gutter
  static const double cardGap = 16;

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 32;
  static const double radiusPill = 999;

  /// Comfortable control height (buttons/fields).
  static const double controlHeight = 54;

  /// Widest content column on desktop layouts — the same design, centered.
  static const double desktopMaxWidth = 1120;
  static const double desktopFormWidth = 560;

  /// Hero banner heights (mobile / desktop-capped).
  static const double heroHeight = 220;
  static const double landingHeroMax = 560;
}

/// Elevation shadows — soft, warm-tinted; cards read as raised paper, not
/// bordered data rows.
abstract final class AppShadow {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x141C1411), // 8% warm black
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x0A1C1411), // 4%
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x1F1C1411), // 12% — floating bars, sheets
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> cta = [
    BoxShadow(
      color: Color(0x4DDB3A1F), // coral glow under primary CTAs
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}

/// Motion durations & curves — deliberate, quick, never floaty. Used by the
/// transition suite, entrance staggers, button feedback and shimmer loops.
abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration hero = Duration(milliseconds: 520);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve spring = Curves.easeOutBack; // small overshoot, taps only

  /// Stagger step for list/grid entrance cascades.
  static const Duration staggerStep = Duration(milliseconds: 55);
}
