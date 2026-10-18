/// Welcome / landing — the first screen for signed-out visitors (new in the
/// UI rehaul; the app previously dropped users straight onto the login form).
///
/// One honest hero: brand promise + three REAL capabilities (browse, live
/// tracking, status notifications) + a single "Sign in" action. No invented
/// promos, ratings, ETAs or sign-up flow (the API has no signup endpoint).
///
/// Responsive: phone = stacked hero over content; ≥900px = split layout with
/// a full-height photographic pane (not a stretched phone canvas).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;
import '../../ui/motion/entrance.dart';
import '../../ui/widgets/primary_button.dart';

const String _heroAsset = 'assets/food/rest_bella_napoli.jpg';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppShellBreakpoint.wide;
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 5, child: _ContentPane(constrained: true)),
                Expanded(
                  flex: 6,
                  child: _HeroPane(height: constraints.maxHeight),
                ),
              ],
            );
          }
          return Column(
            children: [
              _HeroPane(height: (constraints.maxHeight * 0.40).clamp(240, 380)),
              // Scrollable: short viewports (e.g. landscape phones, 600px
              // test surfaces) can't show the whole pitch at once.
              Expanded(
                child: SingleChildScrollView(
                  child: _ContentPane(constrained: false),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shared breakpoint with the navigation shell (one source of truth).
abstract final class AppShellBreakpoint {
  static const double wide = 900;
}

class _HeroPane extends StatelessWidget {
  const _HeroPane({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'A margherita pizza being slid into a glowing wood-fired oven',
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppSpacing.radiusXl),
          bottomRight: Radius.circular(AppSpacing.radiusXl),
        ),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _heroAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.charcoalSoft),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroFade),
              ),
              Positioned(
                left: AppSpacing.xl,
                bottom: AppSpacing.xl,
                right: AppSpacing.xl,
                child: Text(
                  'QuickBite',
                  style: AppTypography.wordmark(
                    size: 34,
                    color: AppColors.onDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({required this.constrained});

  /// True on wide layouts: content sits in a centered max-width column.
  final bool constrained;

  static const _features = <(IconData, String, String)>[
    (
      Icons.restaurant_rounded,
      'Discover local restaurants',
      'Browse every open kitchen in the catalogue.',
    ),
    (
      Icons.delivery_dining_rounded,
      'Follow your order live',
      'Watch each status change as it happens.',
    ),
    (
      Icons.notifications_rounded,
      'Stay in the loop',
      'Notifications for every update on your orders.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Entrance(
              index: 0,
              child: Text(
                'Great food, from kitchens near you.',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Entrance(
              index: 1,
              child: Text(
                'Browse local restaurants, place your order in seconds, and '
                'follow it from the kitchen to your door.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.inkSoft, height: 1.5),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < _features.length; i++)
              Entrance(
                index: i + 2,
                child: _FeatureRow(
                  icon: _features[i].$1,
                  title: _features[i].$2,
                  subtitle: _features[i].$3,
                ),
              ),
            const SizedBox(height: AppSpacing.xxl),
            Entrance(
              index: 5,
              child: PrimaryButton(
                label: 'Sign in',
                onPressed: () => context.go('/login'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Entrance(
              index: 6,
              child: Center(
                child: Text(
                  'Sign in with your existing QuickBite account.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!constrained) return content;
    return Center(child: content);
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
