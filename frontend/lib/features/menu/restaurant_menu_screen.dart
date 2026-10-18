/// Restaurant menu (M5 §3): the restaurant's ACTUAL menu — names,
/// descriptions, authoritative server prices, availability — with contract
/// pagination. Available items add to the cart (quantity steppers when in
/// cart); unavailable items are never purchasable. Single-restaurant cart
/// rule is enforced by the cart controller; conflicts resolve through an
/// explicit confirm dialog (no silent data loss) via the shared
/// [handleCartAdd] helper.
///
/// UI rehaul v3 (reference-led): a photographic hero from the restaurant's
/// real `imageAsset` carries the back action; a circular restaurant mark sits
/// ON the seam between hero and content (no clipping, no layout gap); a
/// raised info card holds the real name, description and open/closed state.
/// Menu items render as image-led cards in a responsive Wrap (1 column on
/// phones, 2 on tablets, 3 on desktop) — every value is API-backed. The
/// floating **View cart** bar and all contract copy are preserved.
library;

import 'dart:math' as math;

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

/// Widest content column for the menu (desktop-capped, never stretched).
const double _menuMaxWidth = 960;

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
  ConsumerState<RestaurantMenuScreen> createState() =>
      _RestaurantMenuScreenState();
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
      final found = await ref
          .read(restaurantsProvider.notifier)
          .byId(widget.restaurantId);
      if (mounted && _resolved == null) setState(() => _resolved = found);
    } catch (_) {
      // Header simply shows "Menu" — the menu itself still loads.
    }
  }

  void _addToCart(MenuItem item) {
    final result = ref
        .read(cartControllerProvider.notifier)
        .add(
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
    final isAdmin = ref.watch(
      authControllerProvider.select((auth) => auth.isAdmin),
    );
    final restaurant = _resolved;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth =
        math.min(screenWidth, _menuMaxWidth) - 2 * AppSpacing.screenPadding;
    // Rows (image + copy + control) need room either side of the photo, so a
    // second column only appears once it can hold a readable row.
    final columns = contentWidth >= 700 ? 2 : 1;
    final tileWidth =
        (contentWidth - AppSpacing.cardGap * (columns - 1)) / columns;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _menuMaxWidth),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _MenuHeader(restaurant: restaurant),
              ),

              // --- Menu body ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
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
                const SliverToBoxAdapter(
                  child: Shimmer(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding,
                      ),
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
                  child: ErrorState(
                    error: state.error!,
                    onRetry: controller.refresh,
                  ),
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
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    0,
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: AppSpacing.cardGap,
                      runSpacing: AppSpacing.cardGap,
                      children: [
                        for (var index = 0; index < state.items.length; index++)
                          SizedBox(
                            width: tileWidth,
                            child: Entrance(
                              index: index,
                              child: _MenuTile(
                                item: state.items[index],
                                inCartQuantity:
                                    cart.line(state.items[index].id)?.quantity ??
                                    0,
                                onTap: () => _openDetail(state.items[index]),
                                onAdd: () => _addToCart(state.items[index]),
                                onIncrement: () => ref
                                    .read(cartControllerProvider.notifier)
                                    .increment(state.items[index].id),
                                onDecrement: () => ref
                                    .read(cartControllerProvider.notifier)
                                    .decrement(state.items[index].id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl + 96),
                    child: _MenuFooter(
                      loadingMore: state.loadingMore,
                      hasMore: state.hasMore,
                      onLoadMore: controller.loadMore,
                    ),
                  ),
                ),
              ],
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
                      overflow: TextOverflow.ellipsis,
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

/// Photographic hero + circular restaurant mark straddling the seam + raised
/// info card. Fixed hero band means the mark never clips text or leaves a
/// layout gap (the previous `Transform.translate` card did both).
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.restaurant});

  final Restaurant? restaurant;

  static const double _heroHeight = 196;
  static const double _markSize = 76;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final restaurant = this.restaurant;
    final description = restaurant?.description;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            SizedBox(
              height: _heroHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(AppSpacing.radiusXl),
                      bottomRight: Radius.circular(AppSpacing.radiusXl),
                    ),
                    child: _MenuHero(restaurant: restaurant),
                  ),
                  const DecoratedBox(
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
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxxl + AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  boxShadow: AppShadow.raised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      restaurant?.name ?? 'Menu',
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (restaurant != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _StatusPill(available: restaurant.isAvailable),
                    ],
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        // Circular restaurant mark ON the seam (photo if the API provides
        // one, initials otherwise) — painted over the card, so it never
        // depends on negative margins or transforms.
        Positioned(
          top: _heroHeight - _markSize / 2,
          left: 0,
          right: 0,
          child: Center(
            child: _RestaurantMark(
              restaurant: restaurant,
              size: _markSize,
            ),
          ),
        ),
      ],
    );
  }
}

class _RestaurantMark extends StatelessWidget {
  const _RestaurantMark({required this.restaurant, required this.size});

  final Restaurant? restaurant;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Initials mark (the API ships no separate logo asset) inside a white
    // ring so it reads as a badge on the hero seam.
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppShadow.card,
      ),
      child: RestaurantAvatar(
        name: restaurant?.name ?? 'Menu',
        size: size - 8,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
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
    final description = item.description;
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
                FoodImage(itemId: item.id, assetName: item.imageAsset, size: 92),
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
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 2,
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
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusPill,
                                ),
                                border: Border.all(
                                  color: AppColors.outlineSoft,
                                ),
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
                            child: MoneyText(
                              item.priceMinor,
                              currency: item.currency,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          if (available)
                            inCartQuantity == 0
                                ? FilledButton(
                                    onPressed: onAdd,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(76, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
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

class _MenuFooter extends StatelessWidget {
  const _MenuFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
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
    if (!hasMore) return const SizedBox.shrink();
    return Center(
      child: TextButton.icon(
        onPressed: () => onLoadMore(),
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text('Load more'),
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
        errorBuilder: (_, _, _) => _HeroInitials(name: restaurant.name),
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
