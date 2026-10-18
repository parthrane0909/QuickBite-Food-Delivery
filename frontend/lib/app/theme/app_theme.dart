/// Application theme — UI rehaul edition.
///
/// Typography system: **Inter** (bundled, OFL) carries every UI role —
/// display headlines are heavy (w800) with tight tracking for the bold
/// template energy; body is regular Inter for cross-platform consistency.
/// **Playfair Display** is reserved for the QuickBite wordmark only
/// ([AppTypography.wordmark]).
///
/// Surfaces: white cards raised with warm soft shadows over cream; warm
/// darks (`AppColors.charcoal`) for photographic heroes. Every component
/// theme below defines explicit hover / focus / pressed / disabled states.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

const String _uiFamily = 'Inter';
const String _brandFamily = 'PlayfairDisplay';

TextStyle _display(
  double size,
  FontWeight weight,
  double letterSpacing,
  double height,
) => TextStyle(
  fontFamily: _uiFamily,
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
  color: AppColors.ink,
);

/// Brand-only type styles (wordmark, splash lockup).
abstract final class AppTypography {
  static TextStyle wordmark({double size = 24, Color color = AppColors.ink}) =>
      TextStyle(
        fontFamily: _brandFamily,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: 0.2,
        color: color,
      );
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryTint,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.ink,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.peach,
      onSecondaryContainer: AppColors.primaryDark,
      tertiary: AppColors.success,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: AppColors.successTint,
      onTertiaryContainer: AppColors.success,
      error: AppColors.danger,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.dangerTint,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkSoft,
      surfaceContainerHighest: AppColors.surfaceWarm,
      surfaceContainerLow: AppColors.background,
      outline: AppColors.outlineSoft,
      outlineVariant: AppColors.outlineSoft,
    );

    // Inter everywhere: heavy display scale (template energy) + readable body.
    final textTheme = TextTheme(
      displayLarge: _display(56, FontWeight.w800, -1.6, 1.02),
      displayMedium: _display(44, FontWeight.w800, -1.2, 1.06),
      displaySmall: _display(36, FontWeight.w800, -0.9, 1.1),
      headlineLarge: _display(30, FontWeight.w800, -0.7, 1.14),
      headlineMedium: _display(26, FontWeight.w700, -0.5, 1.18),
      headlineSmall: _display(22, FontWeight.w700, -0.3, 1.25),
      titleLarge: _display(20, FontWeight.w700, -0.2, 1.3),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.35,
        letterSpacing: -0.1,
        color: AppColors.ink,
      ),
      titleSmall: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: AppColors.ink,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.5,
        color: AppColors.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14.5,
        height: 1.5,
        color: AppColors.ink,
      ),
      bodySmall: const TextStyle(
        fontSize: 12.5,
        height: 1.45,
        color: AppColors.inkSoft,
      ),
      labelLarge: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: AppColors.ink,
      ),
      labelMedium: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSoft,
      ),
      labelSmall: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: AppColors.inkSoft,
      ),
    );

    // Button states: explicit hover (web), focus ring, pressed overlay and a
    // calm disabled treatment — shared by all button themes.
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.hovered)) {
        return AppColors.primary.withValues(alpha: 0.10);
      }
      if (states.contains(WidgetState.focused)) {
        return AppColors.primary.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.pressed)) {
        return AppColors.primary.withValues(alpha: 0.18);
      }
      return null;
    });
    const focusBorder = BorderSide(color: AppColors.primary, width: 2);
    const restBorder = BorderSide(color: AppColors.outlineSoft);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      splashColor: AppColors.primaryTint,
      highlightColor: AppColors.primaryTint,
      // Translucent tints matching the button overlays below — these feed
      // InkResponse-based widgets (chips, list tiles). Opaque values here
      // made web hover paint a flat fill that washed out a selected chip's
      // coral pill (caught in the web evidence capture).
      focusColor: AppColors.primary.withValues(alpha: 0.14),
      hoverColor: AppColors.primary.withValues(alpha: 0.10),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      // Raised white cards — shadow instead of hairline borders.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: const TextStyle(color: AppColors.inkFaint),
        prefixIconColor: AppColors.inkFaint,
        suffixIconColor: AppColors.inkSoft,
        labelStyle: const TextStyle(
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceWarm,
          disabledForegroundColor: AppColors.inkFaint,
          minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        ).copyWith(overlayColor: overlay),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.ink,
              disabledForegroundColor: AppColors.inkFaint,
              elevation: 0,
              minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              side: const BorderSide(color: AppColors.outlineSoft),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.surfaceWarm;
                }
                if (states.contains(WidgetState.focused)) {
                  return AppColors.primaryTint;
                }
                if (states.contains(WidgetState.pressed)) {
                  return AppColors.peach;
                }
                return null;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              disabledForegroundColor: AppColors.inkFaint,
              minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
              side: const BorderSide(color: AppColors.outlineSoft),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? focusBorder
                    : restBorder,
              ),
              overlayColor: overlay,
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ).copyWith(overlayColor: overlay),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          hoverColor: AppColors.surfaceWarm,
          focusColor: AppColors.primaryTint,
          highlightColor: AppColors.peach,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        checkmarkColor: AppColors.onPrimary,
        side: const BorderSide(color: AppColors.outlineSoft),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        labelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primaryTint,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        shadowColor: const Color(0x141C1411),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.inkSoft,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.inkSoft,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryTint,
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(color: AppColors.inkSoft),
        selectedLabelTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.charcoal,
        contentTextStyle: const TextStyle(
          color: AppColors.onDark,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        elevation: 6,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.inkSoft,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.outlineSoft,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkSoft,
        textColor: AppColors.ink,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
