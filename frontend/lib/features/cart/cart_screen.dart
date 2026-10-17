/// Cart (M5 §3): add/increase/decrease/remove, selected restaurant,
/// subtotal in server currency, quantity limits (1..20, 20 distinct — the
/// backend's exact bounds), single-restaurant rule, empty state, and the
/// path to checkout. The subtotal shown here is a UI PREVIEW — FastAPI
/// computes the authoritative total at checkout; no taxes, fees or
/// discounts are shown because the backend has none.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../state/cart_controller.dart';
import '../../state/checkout_controller.dart';
import '../../ui/widgets/app_banner.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/food_image.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/section_header.dart';
import 'widgets/cart_line_tile.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the cart?'),
        content: const Text('All items will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) ref.read(cartControllerProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final checkout = ref.watch(checkoutControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Clear cart',
              onPressed: () => _confirmClear(context, ref),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message: 'Add items from a restaurant menu to get started.',
              actionLabel: 'Browse restaurants',
              onAction: () => context.go('/restaurants'),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  children: [
                    if (checkout.hasPendingAttempt) ...[
                      const AppBanner(
                        kind: AppBannerKind.warning,
                        message:
                            'A previous checkout attempt is waiting to be retried. '
                            'Opening checkout will let you safely retry it.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Selected restaurant
                    Card(
                      child: ListTile(
                        leading: RestaurantAvatar(
                          name: cart.restaurantName ?? 'Restaurant',
                          size: 42,
                        ),
                        title: Text(
                          cart.restaurantName ?? '',
                          style: text.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'All cart items must be from one restaurant',
                          style: text.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    const SectionHeader('Items'),
                    for (final line in cart.lines) ...[
                      CartLineTile(
                        line: line,
                        onIncrement: () => controller.increment(line.menuItemId),
                        onDecrement: () => controller.decrement(line.menuItemId),
                        onRemove: () => controller.remove(line.menuItemId),
                      ),
                      const SizedBox(height: AppSpacing.cardGap),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Subtotal', style: text.bodyLarge),
                                MoneyText(
                                  cart.subtotalMinor,
                                  currency: cart.currency,
                                  style: text.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Preview only — the server computes your final '
                              'order total at checkout.',
                              style: text.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    FilledButton(
                      onPressed: () => context.push('/checkout'),
                      child: const Text('Proceed to checkout'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
    );
  }
}
