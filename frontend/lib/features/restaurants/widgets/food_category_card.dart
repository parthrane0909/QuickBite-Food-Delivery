import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Compact image-first cuisine selector for the discovery rail.
class FoodCategoryCard extends StatelessWidget {
  const FoodCategoryCard({
    super.key,
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label cuisine${selected ? ', selected' : ''}',
    child: Material(
      color: selected ? AppColors.primaryTint : Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 104,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outlineSoft,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.surfaceWarm,
                        child: Icon(Icons.restaurant_rounded),
                      ),
                    ),
                    if (selected)
                      const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: AppColors.primary,
                            child: Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 29,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String cuisineImageAsset(String cuisine) {
  final slug = cuisine
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return 'assets/food/family_$slug.jpg';
}
