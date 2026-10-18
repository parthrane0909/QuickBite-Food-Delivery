/// Welcome / landing — the first screen for signed-out visitors (new in the
/// UI rehaul; the app previously dropped users straight onto the login form).
///
/// Design: an IMMERSIVE brand-red field (reference-led). Phones stack an
/// honest badge, oversized white display type, one large food photograph and
/// two rounded pill controls (a light "Continue with email" primary and an
/// outline "How it works" secondary that opens a real capabilities sheet).
/// ≥900px splits into a content column beside a full-height photographic
/// pane. No invented promos, ratings, reward programmes, social sign-in or
/// sign-up (the API has no signup endpoint and there is no social provider).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;
import '../../ui/motion/entrance.dart';

const String _heroAsset = 'assets/food/item_margherita_pizza.jpg';
const double _wideBreakpoint = 900;

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandRedDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.brandRedGradient),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.brandRedGlow),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final actions = _Actions(
                  onHowItWorks: () => _showHowItWorks(context),
                );
                if (constraints.maxWidth >= _wideBreakpoint) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _HeroCopy(),
                                const SizedBox(height: AppSpacing.xl),
                                actions,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(flex: 6, child: const _PhotoPane()),
                    ],
                  );
                }
                // Reference order: badge → type → photo → controls.
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        0,
                      ),
                      child: _HeroCopy(),
                    ),
                    const Expanded(child: _PhotoPane()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                      ),
                      child: actions,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => const _HowItWorksSheet(),
    );
  }
}

/// Badge + oversized brand heading + one honest sentence.
class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Entrance(index: 0, child: _Badge()),
        const SizedBox(height: AppSpacing.lg),
        Entrance(
          index: 1,
          child: Semantics(
            header: true,
            child: Text(
              'Welcome to\nQuickBite',
              style: text.displaySmall?.copyWith(
                color: AppColors.onBrandRed,
                fontWeight: FontWeight.w800,
                height: 1.02,
                letterSpacing: -1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Entrance(
          index: 2,
          child: Text(
            'Great food, from kitchens near you. Sign in to browse '
            'restaurants and track every order.',
            style: text.bodyLarge?.copyWith(
              color: AppColors.onBrandRedSoft,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.onBrandRed.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: AppColors.onBrandRed.withValues(alpha: 0.34),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 15,
              color: AppColors.onBrandRed,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Local kitchens, real menus',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppColors.onBrandRed.withValues(alpha: 0.95),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two reference-led pill controls + honest fine print.
class _Actions extends StatelessWidget {
  const _Actions({required this.onHowItWorks});

  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Entrance(
          index: 3,
          child: FilledButton.icon(
            onPressed: () => context.go('/login'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.ink,
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.mail_outline_rounded, size: 20),
            label: const Text('Continue with email'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Entrance(
          index: 4,
          child: OutlinedButton.icon(
            onPressed: onHowItWorks,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onBrandRed,
              minimumSize: const Size.fromHeight(56),
              side: BorderSide(
                color: AppColors.onBrandRed.withValues(alpha: 0.7),
                width: 1.5,
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.delivery_dining_rounded, size: 20),
            label: const Text('How it works'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Entrance(
          index: 5,
          child: Text(
            'Customer and admin accounts sign in here. Sign-up and social '
            'sign-in are not part of this build.',
            style: text.bodySmall?.copyWith(
              color: AppColors.onBrandRed.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-bleed photograph filling whatever space it is given.
class _PhotoPane extends StatelessWidget {
  const _PhotoPane();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'A freshly baked margherita pizza',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
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
                right: AppSpacing.xl,
                bottom: AppSpacing.xl,
                child: Entrance(
                  index: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'QuickBite',
                        style: AppTypography.wordmark(
                          size: 28,
                          color: AppColors.onDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Wood-fired, delivered.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ],
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

/// The real product capabilities — the same three honest promises the app
/// actually delivers (browse, live tracking, order notifications).
const List<(IconData, String, String)> _capabilities = [
  (
    Icons.restaurant_rounded,
    'Discover local restaurants',
    'Browse every open kitchen with real menu prices and availability.',
  ),
  (
    Icons.delivery_dining_rounded,
    'Follow your order live',
    'Watch each status change as it happens, straight from the server.',
  ),
  (
    Icons.notifications_rounded,
    'Stay in the loop',
    'Every persisted notification for your order, in one place.',
  ),
];

class _HowItWorksSheet extends StatelessWidget {
  const _HowItWorksSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'How QuickBite works',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final capability in _capabilities)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryTint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        capability.$1,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            capability.$2,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            capability.$3,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/login');
              },
              child: const Text('Continue with email'),
            ),
          ],
        ),
      ),
    );
  }
}
