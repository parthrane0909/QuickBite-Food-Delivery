/// Home / discovery (assignment §7 / M5 §3): REAL seeded restaurants from
/// PostgreSQL through FastAPI — pagination (infinite scroll + pull to
/// refresh), loading / empty / error states. Role-aware: a cart badge for
/// customers; admins get read-only browsing (checkout is unreachable for
/// them via the router).
///
/// UI rehaul v3: a photographic dark hero band (reference-led) carrying the
/// wordmark, the real session greeting and the cart — it scrolls away with
/// the content — then a shimmer skeleton shaped like the grid, and a
/// responsive restaurant grid (1 column on phones, 2–3 on tablet/desktop).
/// Every value shown comes from the API: no ratings, ETAs, fees, offers or
/// cuisine chips are invented (the contract has none).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/paginated_list_view.dart';
import 'widgets/restaurant_card.dart';

/// Grid breakpoints for the discovery grid (independent of the 900px
/// navigation-shell breakpoint so tablets get a grid with the bottom bar).
abstract final class _DiscoveryLayout {
  static const double gridFrom = 760; // 2 columns from here
  static const double threeColFrom = 1040; // 3 columns from here
}

const String _heroAsset = 'assets/food/rest_spice_route.jpg';

class RestaurantListScreen extends ConsumerWidget {
  const RestaurantListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(restaurantsProvider);
    final isAdmin = ref.watch(
      authControllerProvider.select((auth) => auth.isAdmin),
    );
    final cartCount = ref.watch(
      cartControllerProvider.select((cart) => cart.itemCount),
    );
    final controller = ref.read(restaurantsProvider.notifier);
    final session = ref.watch(authControllerProvider).session;
    final width = MediaQuery.sizeOf(context).width;

    final header = Column(
      children: [
        _HomeHeader(
          fullName: session?.user.fullName,
          isAdmin: isAdmin,
          cartCount: cartCount,
        ),
        const _SectionHeading(),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.desktopMaxWidth,
          ),
          child: _Body(
            state: state,
            controller: controller,
            width: width,
            header: header,
          ),
        ),
      ),
    );
  }
}

/// Photographic dark hero band — the reference's discovery header, carried by
/// the REAL session greeting (never a fabricated address or promo).
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.fullName,
    required this.isAdmin,
    required this.cartCount,
  });

  final String? fullName;
  final bool isAdmin;
  final int cartCount;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final name = (fullName ?? '').trim();
    if (name.isEmpty) return 'there';
    return name.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final topInset = MediaQuery.paddingOf(context).top;
    const radius = BorderRadius.vertical(
      bottom: Radius.circular(AppSpacing.radiusXl),
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.heroBand,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.32,
              child: Image.asset(
                _heroAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.heroFade),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              topInset + AppSpacing.md,
              AppSpacing.screenPadding,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/logo_mark.png',
                      width: 30,
                      height: 30,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.fastfood_rounded,
                        color: AppColors.onDark,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        'QuickBite',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.wordmark(
                          size: 20,
                          color: AppColors.onDark,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!isAdmin)
                      IconButton(
                        tooltip: 'Cart',
                        onPressed: () => context.push('/cart'),
                        color: AppColors.onDark,
                        icon: Badge(
                          isLabelVisible: cartCount > 0,
                          label: Text('$cartCount'),
                          backgroundColor: AppColors.primary,
                          child: const Icon(Icons.shopping_bag_outlined),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Entrance(
                  index: 0,
                  child: Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: text.labelLarge?.copyWith(
                            color: AppColors.primaryTint,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hi, $_firstName!',
                          style: text.headlineLarge?.copyWith(
                            color: AppColors.onDark,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'What would you like to eat today?',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.onDarkSoft,
                          ),
                        ),
                      ],
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

/// Section heading style (shared voice with the hero band).
TextStyle _sectionHeading(BuildContext context) =>
    Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ) ??
    const TextStyle();

class _SectionHeading extends StatelessWidget {
  const _SectionHeading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.xl,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'All restaurants',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sectionHeading(context),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Delivered fresh',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.controller,
    required this.width,
    required this.header,
  });

  final RestaurantsState state;
  final RestaurantsController controller;
  final double width;
  final Widget header;

  bool get _isGrid => width >= _DiscoveryLayout.gridFrom;
  bool get _isThreeCol => width >= _DiscoveryLayout.threeColFrom;

  SliverGridDelegate get _gridDelegate {
    if (_isThreeCol) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.cardGap,
        crossAxisSpacing: AppSpacing.cardGap,
        childAspectRatio: 1.15,
      );
    }
    return const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.cardGap,
      crossAxisSpacing: AppSpacing.cardGap,
      childAspectRatio: 1.25,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (state.initialLoading) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(
            child: _SkeletonBody(isGrid: _isGrid, isThreeCol: _isThreeCol),
          ),
        ],
      );
    }

    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(error: error, onRetry: controller.refresh),
          ),
        ],
      );
    }

    if (state.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.restaurant_menu_rounded,
              title: 'No restaurants yet',
              message:
                  'Once restaurants are seeded in QuickBite, they will appear here.',
              actionLabel: 'Refresh',
              onAction: controller.refresh,
            ),
          ),
        ],
      );
    }

    return PaginatedListView(
      header: header,
      items: state.items,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
      onRefresh: controller.refresh,
      onLoadMore: controller.loadMore,
      gridDelegate: _isGrid ? _gridDelegate : null,
      itemBuilder: (context, index) {
        final restaurant = state.items[index];
        return Entrance(
          index: index,
          child: RestaurantCard(
            restaurant: restaurant,
            height: _isGrid ? null : RestaurantCard.totalHeight,
            onTap: () =>
                context.push('/menu/${restaurant.id}', extra: restaurant),
          ),
        );
      },
    );
  }
}

/// Content-shaped loading placeholder: shimmer cards in the SAME layout the
/// data will land in (list on phones, grid on wide).
class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({required this.isGrid, required this.isThreeCol});

  final bool isGrid;
  final bool isThreeCol;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.md,
        ),
        child: isGrid
            ? GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isThreeCol ? 3 : 2,
                mainAxisSpacing: AppSpacing.cardGap,
                crossAxisSpacing: AppSpacing.cardGap,
                childAspectRatio: isThreeCol ? 1.15 : 1.25,
                children: List.filled(
                  isThreeCol ? 6 : 4,
                  const SkeletonRestaurantCard(),
                ),
              )
            // Scroll-safe: on short viewports the placeholder rows just
            // scroll like the real list will (never overflow).
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonRestaurantCard(),
                  SizedBox(height: AppSpacing.cardGap),
                  SkeletonRestaurantCard(),
                  SizedBox(height: AppSpacing.cardGap),
                  SkeletonRestaurantCard(),
                ],
              ),
      ),
    );
  }
}
