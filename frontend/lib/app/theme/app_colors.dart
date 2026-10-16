import 'package:flutter/material.dart';

/// Semantic colors for QuickBite.
///
/// Palette inspired by the reference shots (visual inspiration only — no
/// licensed assets are used or claimed). Contrast pairs are chosen to stay
/// readable (WCAG AA for body-sized text on their intended backgrounds).
class AppColors {
  AppColors._();

  /// Primary brand: warm coral used for CTAs and active states.
  static const Color primary = Color(0xFFE4572E);
  static const Color primaryDark = Color(0xFFB93B1B);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Surfaces: warm cream background with white cards.
  static const Color background = Color(0xFFFDF7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6EDE4);

  /// Text: deep warm charcoal (AA on both background and surface).
  static const Color textPrimary = Color(0xFF241C18);
  static const Color textSecondary = Color(0xFF6B5D54);
  static const Color textOnDark = Color(0xFFFFFFFF);

  /// Lines and dividers.
  static const Color border = Color(0xFFE7DACC);

  /// Accent: deep green used for success / available states.
  static const Color success = Color(0xFF2E7D4F);
  static const Color successContainer = Color(0xFFDCF1E4);

  /// Warning (e.g. delayed, degraded) and permanent failure.
  static const Color warning = Color(0xFFB26B00);
  static const Color warningContainer = Color(0xFFFFEED2);
  static const Color danger = Color(0xFFC0392B);
  static const Color dangerContainer = Color(0xFFFBE3E0);
}
