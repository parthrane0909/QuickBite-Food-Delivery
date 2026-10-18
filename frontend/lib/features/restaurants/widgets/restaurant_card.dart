/// Restaurant card (UI rehaul v3): full-bleed photography on a raised white
/// card — image on top with the real open/closed state, then name, one-line
/// description and a "View menu" affordance. Shows ONLY API-backed fields —
/// no ratings, delivery times, fees or offers are invented (the contract has
/// none).
///
/// Layout: the photo fills all vertical space the card is given (fixed
/// 156px in lists; taller in responsive grid cells), content sits in a
/// fixed block beneath — so one component works at every breakpoint without
/// clipping. Interaction comes from the shared [Pressable] (press scale,
/// web hover lift); the whole card is one semantic button with the
/// open/closed state in its accessible label.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../data/dto/catalog_dto.dart';
import '../../../ui/widgets/pressable.dart';

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onTap,
    this.height = totalHeight,
  });

  final Restaurant restaurant;
  final VoidCallback onTap;

  /// List-mode height; pass `null` inside grid cells (tight constraints
  /// size the card, the photo expands to fill).
  final double? height;

  /// Fixed list height: 156 photo + content block.
  static const double totalHeight = 272;
  static const double heroHeight = 156;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final description = restaurant.description;
    return Pressable(
      onTap: onTap,
      child: Semantics(
        button: true,
        label:
            '${restaurant.name} restaurant'
            '${restaurant.isAvailable ? ', open' : ', currently closed'}',
        child: Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            boxShadow: AppShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _HeroImage(restaurant: restaurant),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x331C1411), Color(0x001C1411)],
                          stops: [0.0, 0.45],
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: _AvailabilityChip(
                        available: restaurant.isAvailable,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'View menu',
                            style: text.labelMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final asset = restaurant.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _InitialsFallback(restaurant: restaurant),
      );
    }
    return _InitialsFallback(restaurant: restaurant);
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final name = restaurant.name;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryTint, AppColors.surfaceWarm],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available
                ? Icons.store_mall_directory_outlined
                : Icons.hourglass_empty_rounded,
            size: 13,
            color: available ? AppColors.success : AppColors.inkSoft,
          ),
          const SizedBox(width: 5),
          Text(
            available ? 'Open' : 'Closed',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: available ? AppColors.success : AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
