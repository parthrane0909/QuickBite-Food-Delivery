/// Design tokens extracted from the provided food-delivery references
/// (warm cream surfaces, vivid coral CTAs, peach quantity controls,
/// charcoal serif headings, green success accents) and the Dribbble
/// palette's warm neutrals. ALL colors live here — screens and widgets
/// reference tokens, never raw hex values (master prompt §6).
library;

import 'package:flutter/material.dart';

/// Core palette. `primary` is calibrated so WHITE text on coral reaches
/// WCAG AA (>= 4.5:1) while staying visually close to the reference coral.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFFDB3A1F); // vivid coral-red (AA w/ white)
  static const Color primaryDark = Color(0xFFB22C14); // pressed / high-emphasis
  static const Color primaryTint = Color(0xFFFFF0EB); // coral 50 — soft chips

  // Warm neutrals (surfaces)
  static const Color background = Color(0xFFFCF7F2); // warm off-white / cream
  static const Color surface = Color(0xFFFFFFFF); // cards
  static const Color surfaceWarm = Color(0xFFF9EFE8); // cream sections / wells
  static const Color outlineSoft = Color(0xFFEFE2D8); // hairlines, borders

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

  // On-color text/icons
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimarySoft = Color(0xFFFFE4DB);

  // Dark surface used for photographic hero headers
  static const Color heroScrim = Color(0xCC2A1A14);
}

/// Spacing scale (4pt grid) and corner radii — one source of truth so
/// layouts stay rhythmically consistent across every screen.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double screenPadding = 20; // default screen gutter (design ref)
  static const double cardGap = 16;

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 32;
  static const double radiusPill = 999;

  /// Comfortable control height (buttons/fields), matching the reference.
  static const double controlHeight = 54;

  /// Widest content column on desktop layouts — the same design, centered,
  /// rather than a stretched mobile screen.
  static const double desktopMaxWidth = 1120;
  static const double desktopFormWidth = 560;
}
