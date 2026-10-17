/// Restaurant card from the reference design: avatar, name, one-line
/// description, availability chip, chevron. Shows ONLY API-backed fields —
/// no ratings, delivery times or fees are invented (the contract has none).
library;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../data/dto/catalog_dto.dart';
import '../../../ui/widgets/food_image.dart';

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({super.key, required this.restaurant, required this.onTap});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${restaurant.name} restaurant'
          '${restaurant.isAvailable ? ', open' : ', currently closed'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RestaurantAvatar(name: restaurant.name, size: 62),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              restaurant.name,
                              style: text.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _AvailabilityChip(available: restaurant.isAvailable),
                        ],
                      ),
                      if (restaurant.description != null &&
                          restaurant.description!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          restaurant.description!,
                          style: text.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Text(
                            'View menu',
                            style: text.labelMedium?.copyWith(color: AppColors.primary),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
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
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.success : AppColors.inkSoft;
    final background = available ? AppColors.successTint : AppColors.surfaceWarm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.store_mall_directory_outlined : Icons.hourglass_empty_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            available ? 'Open' : 'Closed',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
