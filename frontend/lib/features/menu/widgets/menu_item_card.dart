import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../data/dto/catalog_dto.dart';
import '../../../ui/widgets/food_image.dart';
import '../../../ui/widgets/money_text.dart';
import '../../../ui/widgets/pressable.dart';
import '../../../ui/widgets/quantity_stepper.dart';

/// Natural-height content: descriptions are never ellipsized to fit a grid.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    required this.quantity,
    required this.onOpen,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.readOnly = false,
  });
  final MenuItem item;
  final int quantity;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool readOnly;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineSoft),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onOpen,
            radius: 14,
            child: Semantics(
              button: true,
              label: 'View ${item.name}',
              child: AspectRatio(
                aspectRatio: 1.28,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FoodImage(
                      itemId: item.id,
                      assetName: item.imageAsset,
                      expand: true,
                      roundedRadius: 0,
                    ),
                    if (!item.isAvailable)
                      const ColoredBox(color: Color(0x55FFFFFF)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.name,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                if (item.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.description!,
                    style: text.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                MoneyText(
                  item.priceMinor,
                  currency: item.currency,
                  style: text.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (!item.isAvailable)
                  const SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        'Unavailable',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  )
                else if (!readOnly)
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.fast,
                    child: quantity == 0
                        ? SizedBox(
                            key: const ValueKey('add'),
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: onAdd,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 18),
                                  SizedBox(width: 5),
                                  Text('Add'),
                                ],
                              ),
                            ),
                          )
                        : Center(
                            key: const ValueKey('quantity'),
                            child: QuantityStepper(
                              quantity: quantity,
                              onIncrement: onIncrement,
                              onDecrement: onDecrement,
                              dense: true,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
