/// Restaurant menu (M5 §3): the restaurant's ACTUAL menu — names,
/// descriptions, authoritative server prices, availability — with contract
/// pagination. Available items add to the cart (quantity steppers when in
/// cart); unavailable items are never purchasable. Single-restaurant cart
/// rule is enforced by the cart controller; conflicts resolve through an
/// explicit confirm dialog (no silent data loss).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dto/catalog_dto.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/food_image.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/quantity_stepper.dart';

class RestaurantMenuScreen extends ConsumerStatefulWidget {
  const RestaurantMenuScreen({
    super.key,
    required this.restaurantId,
    this.restaurant,
  });

  final String restaurantId;

  /// Passed as the route's extra for instant headers; deep links resolve it
  /// asynchronously (single-restaurant endpoint does not exist).
  final Restaurant? restaurant;

  @override
  ConsumerState<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  Restaurant? _resolved;

  @override
  void initState() {
    super.initState();
    _resolved = widget.restaurant;
    if (_resolved == null) _resolveRestaurant();
  }

  Future<void> _resolveRestaurant() async {
    try {
      final found =
          await ref.read(restaurantsProvider.notifier).byId(widget.restaurantId);
      if (mounted && _resolved == null) setState(() => _resolved = found);
    } catch (_) {
      // Header simply shows "Menu" — the menu itself still loads.
    }
  }

  void _addToCart(MenuItem item) {
    final cart = ref.read(cartControllerProvider.notifier);
    final restaurantName = _resolved?.name ?? '';
    final result = cart.add(
      item,
      restaurantId: widget.restaurantId,
      restaurantName: restaurantName,
    );
    _handleResult(result, item, restaurantName);
  }

  void _handleResult(CartAddResult result, MenuItem item, String restaurantName) {
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case CartAddResult.added:
        return;
      case CartAddResult.quantityMaxed:
        messenger.showSnackBar(
          const SnackBar(content: Text('Maximum quantity per item is 20.')),
        );
      case CartAddResult.tooManyDistinctItems:
        messenger.showSnackBar(
          const SnackBar(content: Text('Cart holds up to 20 different items.')),
        );
      case CartAddResult.restaurantConflict:
        _showConflictDialog(item, restaurantName);
    }
  }

  Future<void> _showConflictDialog(MenuItem item, String newRestaurantName) async {
    final cart = ref.read(cartControllerProvider);
    final existingName = cart.restaurantName?.isNotEmpty == true
        ? cart.restaurantName!
        : 'another restaurant';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
          'Your cart has items from $existingName. '
          'Adding "${item.name}" from ${newRestaurantName.isEmpty ? 'this restaurant' : newRestaurantName} '
          'will clear it first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(150, 44)),
            child: const Text('Clear & add'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      ref.read(cartControllerProvider.notifier).replaceAndAdd(
            item,
            restaurantId: widget.restaurantId,
            restaurantName: newRestaurantName,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider(widget.restaurantId));
    final controller = ref.read(menuProvider(widget.restaurantId).notifier);
    final cart = ref.watch(cartControllerProvider);
    final isAdmin = ref.watch(authControllerProvider.select((auth) => auth.isAdmin));
    final restaurant = _resolved;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // --- Photographic hero + restaurant info (reference layout) ---
          SliverToBoxAdapter(
            child: Stack(
              children: [
                SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/images/hero_banner.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF3A241C)),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.heroScrim.withValues(alpha: 0.5),
                          AppColors.heroScrim.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: AppSpacing.md,
                  child: _CircleAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    // canPop guard: a deep-link reload (web) starts with an
                    // empty stack, so pop() alone would have nowhere to go.
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/restaurants');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RestaurantAvatar(
                          name: restaurant?.name ?? 'Menu',
                          size: 58,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                restaurant?.name ?? 'Menu',
                                style: Theme.of(context).textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (restaurant?.description != null &&
                                  restaurant!.description!.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  restaurant.description!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (restaurant != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  restaurant.isAvailable
                                      ? 'Accepting orders'
                                      : 'Currently closed',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: restaurant.isAvailable
                                        ? AppColors.success
                                        : AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // --- Menu body ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.sm,
              ),
              child: Text('Menu', style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          if (state.initialLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingState(label: 'Loading menu…'),
            )
          else if (state.error != null && state.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(error: state.error!, onRetry: controller.refresh),
            )
          else if (state.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.no_food_rounded,
                title: 'No menu items yet',
                message: 'This restaurant has no items on the menu right now.',
                actionLabel: 'Refresh',
                onAction: controller.refresh,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.xxl + 96,
              ),
              sliver: SliverList.separated(
                itemCount: state.items.length + (state.hasMore || state.loadingMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) {
                  if (index >= state.items.length) {
                    if (state.loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: controller.loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load more'),
                      ),
                    );
                  }
                  final item = state.items[index];
                  return _MenuRow(
                    item: item,
                    inCartQuantity: cart.line(item.id)?.quantity ?? 0,
                    onAdd: () => _addToCart(item),
                    onIncrement: () =>
                        ref.read(cartControllerProvider.notifier).increment(item.id),
                    onDecrement: () =>
                        ref.read(cartControllerProvider.notifier).decrement(item.id),
                  );
                },
              ),
            ),
        ],
      ),

      // --- Floating cart bar (customers only) ---
      bottomNavigationBar: (!isAdmin && cart.itemCount > 0)
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: FilledButton(
                onPressed: () => context.push('/cart'),
                // Flexible label: the bar must never overflow, whatever the
                // font metrics or the cart count (ellipsis absorbs the rest).
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'View cart  •  ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    MoneyText(
                      cart.subtotalMinor,
                      currency: cart.currency,
                      semanticsLabel: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.inCartQuantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final MenuItem item;
  final int inCartQuantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final available = item.isAvailable;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: available ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodImage(itemId: item.id, assetName: item.imageAsset, size: 68),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: text.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!available)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceWarm,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusPill),
                              border: Border.all(color: AppColors.outlineSoft),
                            ),
                            child: Text(
                              'Unavailable',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description!,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        MoneyText(
                          item.priceMinor,
                          currency: item.currency,
                          style: text.titleSmall?.copyWith(color: AppColors.primary),
                        ),
                        const Spacer(),
                        if (available)
                          inCartQuantity == 0
                              ? FilledButton(
                                  onPressed: onAdd,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(84, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: const Text('Add'),
                                )
                              : QuantityStepper(
                                  quantity: inCartQuantity,
                                  onIncrement: onIncrement,
                                  onDecrement: onDecrement,
                                  dense: true,
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

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
        onPressed: onPressed,
      ),
    );
  }
}
