/// Restaurant menu (M5 §3): the restaurant's ACTUAL menu — names,
/// descriptions, authoritative server prices, availability — with contract
/// pagination. Available items add to the cart (quantity steppers when in
/// cart); unavailable items are never purchasable. Single-restaurant cart
/// rule is enforced by the cart controller; conflicts resolve through an
/// explicit confirm dialog (no silent data loss) via the shared
/// [handleCartAdd] helper.
///
/// UI rehaul: photographic hero from the restaurant's real `imageAsset`
/// (the old static brown banner is gone), a raised overlapping info card,
/// shimmer row skeletons, pressable rows that open the NEW item detail
/// screen, and a desktop-capped content column. The floating **View cart**
/// bar and all contract copy are preserved (integration contract).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dto/catalog_dto.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/food_image.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/quantity_stepper.dart';
import '../cart/cart_add_actions.dart';

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
    final result = ref.read(cartControllerProvider.notifier).add(
          item,
          restaurantId: widget.restaurantId,
          restaurantName: _resolved?.name ?? '',
        );
    handleCartAdd(
      context: context,
      ref: ref,
      result: result,
      item: item,
      restaurantId: widget.restaurantId,
      restaurantName: _resolved?.name ?? '',
    );
  }

  void _openDetail(MenuItem item) {
    context.push(
      '/menu/${widget.restaurantId}/item/${item.id}',
      extra: _resolved ?? widget.restaurant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider(widget.restaurantId));
    final controller = ref.read(menuProvider(widget.restaurantId).notifier);
    final cart = ref.watch(cartControllerProvider);
    final isAdmin = ref.watch(authControllerProvider.select((auth) => auth.isAdmin));
    final restaurant = _resolved;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: CustomScrollView(
            slivers: [
              // --- Photographic hero from the restaurant's real image ---
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      height: 236,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(AppSpacing.radiusXl),
                          bottomRight: Radius.circular(AppSpacing.radiusXl),
                        ),
                        child: _MenuHero(restaurant: restaurant),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x661C1411),
                              Color(0x001C1411),
                              Color(0x991C1411),
                            ],
                            stops: [0.0, 0.5, 1.0],
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
              // --- Overlapping raised info card ---
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        boxShadow: AppShadow.raised,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RestaurantAvatar(
                            name: restaurant?.name ?? 'Menu',
                            size: 56,
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  restaurant?.name ?? 'Menu',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (restaurant?.description != null &&
                                    restaurant!.description!.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    restaurant.description!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (restaurant != null) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  _StatusPill(
                                      available: restaurant.isAvailable),
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

              // --- Menu body ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.xs,
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                  ),
                  child: Text(
                    'Menu',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                  ),
                ),
              ),
              if (state.initialLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Shimmer(
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonListTile(leading: 84),
                          SizedBox(height: AppSpacing.cardGap),
                          SkeletonListTile(leading: 84),
                          SizedBox(height: AppSpacing.cardGap),
                          SkeletonListTile(leading: 84),
                          SizedBox(height: AppSpacing.cardGap),
                          SkeletonListTile(leading: 84),
                        ],
                      ),
                    ),
                  ),
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
                    itemCount:
                        state.items.length + (state.hasMore || state.loadingMore ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.cardGap),
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
                      return Entrance(
                        index: index,
                        child: _MenuRow(
                          item: item,
                          inCartQuantity: cart.line(item.id)?.quantity ?? 0,
                          onTap: () => _openDetail(item),
                          onAdd: () => _addToCart(item),
                          onIncrement: () => ref
                              .read(cartControllerProvider.notifier)
                              .increment(item.id),
                          onDecrement: () => ref
                              .read(cartControllerProvider.notifier)
                              .decrement(item.id),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
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
    required this.onTap,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final MenuItem item;
  final int inCartQuantity;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final available = item.isAvailable;
    return Pressable(
      onTap: onTap,
      radius: AppSpacing.radiusMd,
      child: Semantics(
        button: true,
        label: '${item.name}, menu item, opens details',
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            boxShadow: AppShadow.card,
          ),
          child: Opacity(
            opacity: available ? 1 : 0.62,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoodImage(itemId: item.id, assetName: item.imageAsset, size: 84),
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
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
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
                              child: const Text(
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
                          style: text.bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
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
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
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
      ),
    );
  }
}

class _MenuHero extends StatelessWidget {
  const _MenuHero({required this.restaurant});

  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    final restaurant = this.restaurant;
    final asset = restaurant?.imageAsset;
    if (restaurant == null) {
      // Deep link: header resolves asynchronously; branded placeholder.
      return const ColoredBox(color: AppColors.charcoalSoft);
    }
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _HeroInitials(name: restaurant.name),
      );
    }
    return _HeroInitials(name: restaurant.name);
  }
}

class _HeroInitials extends StatelessWidget {
  const _HeroInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.charcoalSoft, AppColors.primaryDeep],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.w800,
          color: AppColors.onDark,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
      decoration: BoxDecoration(
        color: available ? AppColors.successTint : AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: available ? AppColors.success : AppColors.inkFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          // Flexible + ellipsis: the pill must never force the info card's
          // column wider than a 360px phone allows.
          Flexible(
            child: Text(
              available ? 'Accepting orders' : 'Currently closed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: available ? AppColors.success : AppColors.inkSoft,
              ),
            ),
          ),
        ],
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
        icon: Icon(icon, color: AppColors.ink),
        onPressed: onPressed,
      ),
    );
  }
}
