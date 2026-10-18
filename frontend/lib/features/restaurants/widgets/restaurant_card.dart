import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../data/dto/catalog_dto.dart';
import '../../../ui/widgets/pressable.dart';

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onTap,
    this.height,
  });
  final Restaurant restaurant;
  final VoidCallback onTap;
  final double? height;
  static const totalHeight = 280.0;
  static const heroHeight = 150.0;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      radius: 16,
      child: Semantics(
        label:
            '${restaurant.name} restaurant, ${restaurant.isAvailable ? 'accepting orders' : 'currently closed'}',
        button: true,
        child: Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.65,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (restaurant.imageAsset != null)
                      Image.asset(
                        restaurant.imageAsset!,
                        fit: BoxFit.cover,
                        cacheWidth: 900,
                        frameBuilder: (_, child, frame, sync) =>
                            sync || frame != null
                            ? child
                            : const ColoredBox(color: AppColors.surfaceWarm),
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppColors.surfaceWarm,
                          child: Icon(Icons.restaurant),
                        ),
                      ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          restaurant.isAvailable ? 'Open' : 'Closed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: restaurant.isAvailable
                                ? AppColors.success
                                : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 10,
                      bottom: 10,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (restaurant.cuisine != null)
                      Text(
                        restaurant.cuisine!,
                        style: text.labelSmall?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (restaurant.description != null)
                      Text(restaurant.description!, style: text.bodySmall),
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
