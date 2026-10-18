/// Item detail (NEW in the UI rehaul) — the dish's own page, the reference
/// template's core pattern: full-bleed photo hero, name, authoritative
/// server price, full description, availability, and a quantity stepper +
/// "Add to cart" bar.
///
/// Data rules: the item is resolved from the REAL menu contract payload
/// (`menuProvider`) — nothing is invented. Unknown ids (stale deep links)
/// render an honest not-found state with a way back. Server caps are
/// respected: the stepper maxes out at the remaining line headroom (20),
/// caps/conflicts route through the shared [handleCartAdd] helper.
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
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/quantity_stepper.dart';
import '../cart/cart_add_actions.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.restaurantId,
    required this.itemId,
    this.restaurant,
  });

  final String restaurantId;
  final String itemId;

  /// Route extra from the menu screen for instant hero/header resolution.
  final Restaurant? restaurant;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  int _quantity = 1;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/menu/${widget.restaurantId}');
    }
  }

  void _add(MenuItem item) {
    final cart = ref.read(cartControllerProvider.notifier);
    final restaurantName = widget.restaurant?.name ?? '';
    final result = cart.add(
      item,
      restaurantId: widget.restaurantId,
      restaurantName: restaurantName,
    );
    handleCartAdd(
      context: context,
      ref: ref,
      result: result,
      item: item,
      restaurantId: widget.restaurantId,
      restaurantName: restaurantName,
      extraQuantity: _quantity - 1,
    );
    if (result == CartAddResult.added && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Added to cart')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuState = ref.watch(menuProvider(widget.restaurantId));
    final cart = ref.watch(cartControllerProvider);
    final isAdmin = ref.watch(
      authControllerProvider.select((auth) => auth.isAdmin),
    );

    MenuItem? item;
    for (final candidate in menuState.items) {
      if (candidate.id == widget.itemId) {
        item = candidate;
        break;
      }
    }
    // Effectively final copy: keeps promotion (including in the closures
    // below) without non-null assertions.
    final detailItem = item;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(AppSpacing.radiusXl),
                          bottomRight: Radius.circular(AppSpacing.radiusXl),
                        ),
                        child: _DetailHero(item: item),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x661C1411), Color(0x001C1411)],
                            stops: [0.0, 0.4],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      left: AppSpacing.md,
                      child: Material(
                        color: AppColors.surface,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          tooltip: 'Back',
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.ink,
                          ),
                          onPressed: _back,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item == null && menuState.initialLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 240, height: 30),
                        SizedBox(height: AppSpacing.lg),
                        SkeletonBox(width: 96, height: 22),
                        SizedBox(height: AppSpacing.xl),
                        SkeletonBox(height: 16),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(height: 16),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(width: 200, height: 16),
                      ],
                    ),
                  ),
                )
              else if (item == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Item not found',
                    message: 'This item is no longer on the menu, or the link is out of date.',
                    actionLabel: 'Back to menu',
                    onAction: _back,
                  ),
                )
              else
                SliverToBoxAdapter(child: _DetailBody(item: item)),
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          (detailItem != null &&
              detailItem.isAvailable &&
              !isAdmin &&
              !menuState.initialLoading)
          ? _AddBar(
              item: detailItem,
              quantity: _quantity,
              inCart: cart.line(detailItem.id)?.quantity ?? 0,
              onQuantityChanged: (value) => setState(() => _quantity = value),
              onAdd: () => _add(detailItem),
            )
          : null,
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.xl,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      child: Entrance(
        index: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!item.isAvailable)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWarm,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(color: AppColors.outlineSoft),
                ),
                child: const Text(
                  'Currently unavailable',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            Text(
              item.name,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            MoneyText(
              item.priceMinor,
              currency: item.currency,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                item.description!,
                style: text.bodyLarge?.copyWith(
                  color: AppColors.inkSoft,
                  height: 1.55,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom add bar: quantity stepper + gradient-weight CTA with the live
/// line total. Disabled (and the bar hidden) for unavailable items, admins
/// and while the menu is still resolving.
class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.item,
    required this.quantity,
    required this.inCart,
    required this.onQuantityChanged,
    required this.onAdd,
  });

  final MenuItem item;
  final int quantity;
  final int inCart;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // Line cap is 20 per contract — leave room for what's already in cart.
    final max = (20 - inCart).clamp(1, 20);
    final effectiveQty = quantity.clamp(1, max);
    final total = item.priceMinor * effectiveQty;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      // heightFactor: shrink-wrap vertically — Scaffold bounds
      // bottomNavigationBar by the screen height, and a bare Center would
      // greedily fill it (starving the body of all its height).
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Row(
            children: [
              QuantityStepper(
                quantity: effectiveQty,
                max: max,
                onIncrement: () => onQuantityChanged(effectiveQty + 1),
                onDecrement: () => onQuantityChanged(effectiveQty - 1),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: SizedBox(
                  height: AppSpacing.controlHeight,
                  child: FilledButton(
                    onPressed: onAdd,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'Add to cart',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        MoneyText(
                          total,
                          currency: item.currency,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.item});

  final MenuItem? item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    if (item == null) {
      return const ColoredBox(color: AppColors.charcoalSoft);
    }
    final asset = item.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _HeroFallback(),
      );
    }
    return const _HeroFallback();
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.charcoalSoft, AppColors.primaryDeep],
        ),
      ),
      child: const Icon(
        Icons.restaurant_rounded,
        size: 96,
        color: AppColors.onDarkSoft,
      ),
    );
  }
}
