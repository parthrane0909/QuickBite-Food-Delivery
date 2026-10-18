/// Splash: shown while the persisted session is being validated
/// (`GET /me`). Branded, non-interactive, no fabricated data — the wordmark
/// settles in with a gentle scale/fade, then hands off to `/welcome`
/// (signed out) or the role home (signed in) via router redirects.
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : 0.86, end: 1),
          duration: AppMotion.hero,
          curve: AppMotion.spring,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                image: true,
                label: 'QuickBite logo',
                child: Image.asset(
                  'assets/images/logo_mark.png',
                  width: 84,
                  height: 84,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.fastfood_rounded,
                    size: 68,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'QuickBite',
                style: AppTypography.wordmark(size: 34),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Restoring your session…',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
