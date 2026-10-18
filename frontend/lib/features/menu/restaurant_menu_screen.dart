import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dto/catalog_dto.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/layout/adaptive_layout.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/money_text.dart';
import '../cart/cart_add_actions.dart';
import 'widgets/menu_item_card.dart';

class RestaurantMenuScreen extends ConsumerStatefulWidget {
  const RestaurantMenuScreen({
    super.key,
    required this.restaurantId,
    this.restaurant,
  });
  final String restaurantId;
  final Restaurant? restaurant;
  @override
  ConsumerState<RestaurantMenuScreen> createState() =>
      _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  Restaurant? _restaurant;
  @override
  void initState() {
    super.initState();
    _restaurant = widget.restaurant;
    if (_restaurant == null) _resolve();
  }

  Future<void> _resolve() async {
    try {
      final result = await ref
          .read(restaurantsProvider.notifier)
          .byId(widget.restaurantId);
      if (mounted) setState(() => _restaurant = result);
    } catch (_) {
      /* Menu request owns the visible error/retry state. */
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/restaurants');
    }
  }

  void _add(MenuItem item) {
    final name = _restaurant?.name ?? '';
    final result = ref
        .read(cartControllerProvider.notifier)
        .add(item, restaurantId: widget.restaurantId, restaurantName: name);
    handleCartAdd(
      context: context,
      ref: ref,
      result: result,
      item: item,
      restaurantId: widget.restaurantId,
      restaurantName: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider(widget.restaurantId));
    final controller = ref.read(menuProvider(widget.restaurantId).notifier);
    final cart = ref.watch(cartControllerProvider);
    final admin = ref.watch(authControllerProvider.select((a) => a.isAdmin));
    final restaurant = _restaurant;
    return Scaffold(
      backgroundColor: Colors.white,
      body: ContentFrame(
        child: LayoutBuilder(
          builder: (context, box) {
            final columns = AdaptiveLayout.menuColumns(context, box.maxWidth);
            final cardWidth =
                (box.maxWidth - 32 - 12 * (columns - 1)) / columns;
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _RestaurantHero(
                      restaurant: restaurant,
                      onBack: _back,
                      onCart: admin ? null : () => context.push('/cart'),
                      count: cart.itemCount,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.storefront_outlined,
                                size: 17,
                                color: restaurant?.isAvailable == false
                                    ? AppColors.inkSoft
                                    : AppColors.success,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  restaurant?.isAvailable == false
                                      ? 'Currently closed'
                                      : 'Accepting orders',
                                  style: TextStyle(
                                    color: restaurant?.isAvailable == false
                                        ? AppColors.inkSoft
                                        : AppColors.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (restaurant?.description != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              restaurant!.description!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.inkSoft,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'On the menu',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (!state.initialLoading)
                                Text(
                                  '${state.total} dishes',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (state.initialLoading)
                    SliverToBoxAdapter(
                      child: Shimmer(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var i = 0; i < columns * 2; i++)
                                SizedBox(
                                  width: cardWidth,
                                  child: const SkeletonDishTile(),
                                ),
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
                        icon: Icons.no_food,
                        title: 'No menu items yet',
                        actionLabel: 'Refresh',
                        onAction: controller.refresh,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverToBoxAdapter(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var i = 0; i < state.items.length; i++)
                              SizedBox(
                                width: cardWidth,
                                child: Entrance(
                                  index: i.clamp(0, 3),
                                  child: MenuItemCard(
                                    item: state.items[i],
                                    quantity:
                                        cart
                                            .line(state.items[i].id)
                                            ?.quantity ??
                                        0,
                                    readOnly: admin,
                                    onOpen: () => context.push(
                                      '/menu/${widget.restaurantId}/item/${state.items[i].id}',
                                      extra: restaurant,
                                    ),
                                    onAdd: () => _add(state.items[i]),
                                    onIncrement: () => ref
                                        .read(cartControllerProvider.notifier)
                                        .increment(state.items[i].id),
                                    onDecrement: () => ref
                                        .read(cartControllerProvider.notifier)
                                        .decrement(state.items[i].id),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (state.hasMore)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: state.loadingMore
                              ? null
                              : controller.loadMore,
                          child: Text(
                            state.loadingMore ? 'Loading…' : 'Load more',
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: !admin && cart.itemCount > 0
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ContentFrame(
                  maxWidth: 620,
                  child: FilledButton(
                    onPressed: () => context.push('/cart'),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'View cart • ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        MoneyText(
                          cart.subtotalMinor,
                          currency: cart.currency,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _RestaurantHero extends StatelessWidget {
  const _RestaurantHero({
    required this.restaurant,
    required this.onBack,
    required this.onCart,
    required this.count,
  });
  final Restaurant? restaurant;
  final VoidCallback onBack;
  final VoidCallback? onCart;
  final int count;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Container(
      color: AppColors.brandRed,
      child: SizedBox(
        height:
            218 +
            MediaQuery.paddingOf(context).top +
            (MediaQuery.textScalerOf(context).scale(33) - 33) * 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (restaurant?.imageAsset != null)
              Positioned.fill(
                left: 75,
                child: Image.asset(
                  restaurant!.imageAsset!,
                  fit: BoxFit.cover,
                  cacheWidth: 1400,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFE51C0B),
                    Color(0xB3C51B0A),
                    Color(0x22000000),
                  ],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x44000000),
                    Colors.transparent,
                    Color(0x66000000),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + 8,
                16,
                20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: onBack,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.ink,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      if (onCart != null)
                        IconButton(
                          tooltip: 'Cart',
                          onPressed: onCart,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.ink,
                          ),
                          icon: Badge(
                            isLabelVisible: count > 0,
                            label: Text('$count'),
                            child: const Icon(Icons.shopping_bag_outlined),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'FRESH FROM THE KITCHEN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    restaurant?.name ?? 'Menu',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 33,
                      height: 1.04,
                      letterSpacing: -1.2,
                    ),
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
