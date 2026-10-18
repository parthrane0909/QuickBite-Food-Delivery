/// Item detail (NEW in the UI rehaul) — the dish's own page, the reference
/// template's core pattern: full-bleed photo hero, name, authoritative
/// server price, full description, availability, and a sticky quantity
/// stepper + "Add to cart" bar.
///
/// Data rules: the item is resolved from the REAL menu contract payload
/// (`menuProvider`) — nothing is invented. Unknown ids (stale deep links)
/// render an honest not-found state with a way back. Server caps are
/// respected: the stepper maxes out at the remaining line headroom (20),
/// caps/conflicts route through the shared [handleCartAdd] helper.
///
/// UI rehaul v3: the body is filled with real content instead of trailing
/// whitespace — an availability/restaurant meta row, the full description, the
/// contract's own quantity cap and (when the kitchen has them) a horizontal
/// "More from `<restaurant>`" strip drawn from the same menu payload.
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
  Restaurant? _restaurant;

  @override
  void initState() {
    super.initState();
    _restaurant = widget.restaurant;
    if (_restaurant == null) _resolveRestaurant();
  }

  /// Deep links arrive without the route extra — resolve the real restaurant
  /// (name, asset, open state) from the paginated catalog instead of guessing.
  Future<void> _resolveRestaurant() async {
    try {
      final found = await ref
          .read(restaurantsProvider.notifier)
          .byId(widget.restaurantId);
      if (mounted && _restaurant == null) setState(() => _restaurant = found);
    } catch (_) {
      // Header/cart fall back to the anonymous restaurant label.
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/menu/${widget.restaurantId}');
    }
  }

  void _openSibling(MenuItem item) {
    context.push(
      '/menu/${widget.restaurantId}/item/${item.id}',
      extra: _restaurant ?? widget.restaurant,
    );
  }

  void _add(MenuItem item) {
    final cart = ref.read(cartControllerProvider.notifier);
    final restaurant = _restaurant ?? widget.restaurant;
    final restaurantName = restaurant?.name ?? '';
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
    final siblings = menuState.items
        .where((candidate) => candidate.id != widget.itemId)
        .toList(growable: false);
    final restaurant = _restaurant ?? widget.restaurant;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Hero(item: item, onBack: _back)),
              if (item == null && menuState.initialLoading)
                const SliverToBoxAdapter(child: _BodySkeleton())
              else if (item == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Item not found',
                    message:
                        'This item is no longer on the menu, or the link is out of date.',
                    actionLabel: 'Back to menu',
                    onAction: _back,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: _DetailBody(
                    item: item,
                    restaurantName: restaurant?.name,
                    siblings: siblings,
                    siblingCurrency: item.currency,
                    onOpenSibling: _openSibling,
                  ),
                ),
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

/// Photographic hero with the back affordance and the real availability state
/// overlaid (so the body can lead with the dish itself).
class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.onBack});

  final MenuItem? item;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final unavailable = item != null && !item!.isAvailable;
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
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
                  colors: [
                    Color(0x661C1411),
                    Color(0x001C1411),
                    Color(0x801C1411),
                  ],
                  stops: [0.0, 0.45, 1.0],
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
                onPressed: onBack,
              ),
            ),
          ),
          if (unavailable)
            Positioned(
              left: AppSpacing.lg,
              bottom: AppSpacing.lg,
              right: AppSpacing.lg,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    boxShadow: AppShadow.card,
                  ),
                  child: const Text(
                    'Currently unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BodySkeleton extends StatelessWidget {
  const _BodySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 240, height: 30),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(width: 96, height: 22),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox(height: 68),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 16),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 16),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 200, height: 16),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.item,
    required this.restaurantName,
    required this.siblings,
    required this.siblingCurrency,
    required this.onOpenSibling,
  });

  final MenuItem item;
  final String? restaurantName;
  final List<MenuItem> siblings;
  final String siblingCurrency;
  final ValueChanged<MenuItem> onOpenSibling;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final description = item.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.xl,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Entrance(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                MoneyText(
                  item.priceMinor,
                  currency: item.currency,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Entrance(
            index: 1,
            child: Row(
              children: [
                Expanded(
                  child: _MetaTile(
                    icon: item.isAvailable
                        ? Icons.check_circle_outline_rounded
                        : Icons.hourglass_empty_rounded,
                    label: 'Availability',
                    value: item.isAvailable ? 'Available' : 'Unavailable',
                    emphasis: item.isAvailable,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _MetaTile(
                    icon: Icons.storefront_outlined,
                    label: 'Kitchen',
                    value: restaurantName ?? 'This restaurant',
                  ),
                ),
              ],
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            Entrance(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('About this dish'),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    description,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Entrance(
            index: 3,
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Quantities are capped at 20 per line.',
                    style: text.bodySmall?.copyWith(color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
          ),
          if (siblings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            Entrance(
              index: 4,
              child: _SectionLabel(
                restaurantName == null
                    ? 'More from this kitchen'
                    : 'More from $restaurantName',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Entrance(
              index: 5,
              child: SizedBox(
                height: 196,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: siblings.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) => _SiblingCard(
                    item: siblings[index],
                    currency: siblingCurrency,
                    onTap: () => onOpenSibling(siblings[index]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = emphasis ? AppColors.success : AppColors.inkSoft;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: emphasis ? AppColors.success : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SiblingCard extends StatelessWidget {
  const _SiblingCard({
    required this.item,
    required this.currency,
    required this.onTap,
  });

  final MenuItem item;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      radius: AppSpacing.radiusMd,
      child: Semantics(
        button: true,
        label: '${item.name}, opens details',
        child: Container(
          width: 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            boxShadow: AppShadow.card,
          ),
          child: Opacity(
            opacity: item.isAvailable ? 1 : 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 11,
                  child: FoodImage(
                    itemId: item.id,
                    assetName: item.imageAsset,
                    expand: true,
                    rounded: false,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MoneyText(
                        item.priceMinor,
                        currency: currency,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
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
