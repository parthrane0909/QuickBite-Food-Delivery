/// One cart line: thumbnail, name, unit price, peach quantity stepper,
/// line total and a remove action. Unavailable items show a warning and
/// remain removable (the server rejects them at checkout anyway).
library;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../state/cart_controller.dart';
import '../../../ui/widgets/food_image.dart';
import '../../../ui/widgets/money_text.dart';
import '../../../ui/widgets/quantity_stepper.dart';

class CartLineTile extends StatelessWidget {
  const CartLineTile({
    super.key,
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodImage(
              itemId: line.menuItemId,
              assetName: line.imageAsset,
              size: 64,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.name,
                          style:
                              text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${line.name}',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: AppColors.inkSoft,
                        ),
                        onPressed: onRemove,
                      ),
                    ],
                  ),
                  MoneyText(
                    line.priceMinor,
                    currency: line.currency,
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!line.isAvailable) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'No longer available — remove it to continue.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  // The total is Flexible: with wide font metrics (or large
                  // minor-unit amounts) the row must never overflow — the
                  // stepper's hit targets stay fixed, the text yields.
                  Row(
                    children: [
                      QuantityStepper(
                        quantity: line.quantity,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
                      ),
                      const Spacer(),
                      Flexible(
                        child: MoneyText(
                          line.lineTotalMinor,
                          currency: line.currency,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
