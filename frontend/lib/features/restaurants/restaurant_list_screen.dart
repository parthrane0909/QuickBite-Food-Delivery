import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/layout/adaptive_layout.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/async_state_view.dart';
import 'widgets/food_category_card.dart';
import 'widgets/restaurant_card.dart';

class RestaurantListScreen extends ConsumerStatefulWidget {
  const RestaurantListScreen({super.key});
  @override
  ConsumerState<RestaurantListScreen> createState() =>
      _RestaurantListScreenState();
}

class _RestaurantListScreenState extends ConsumerState<RestaurantListScreen> {
  final _scroll = ScrollController();
  final _cuisineScroll = ScrollController();
  final _restaurantsKey = GlobalKey();
  final _search = TextEditingController();
  final _cuisineKeys = <String, GlobalKey>{};
  Timer? _searchDebounce;
  Timer? _categoryAutoTimer;
  bool _categoryAutoScheduled = false;
  bool _categoryAutoPaused = false;
  @override
  void dispose() {
    _scroll.dispose();
    _cuisineScroll.dispose();
    _searchDebounce?.cancel();
    _categoryAutoTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleCategoryAutoScroll(int cuisineCount) {
    if (_categoryAutoScheduled || _categoryAutoPaused || cuisineCount < 4) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) return;
    _categoryAutoScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cuisineScroll.hasClients || _categoryAutoPaused) {
        return;
      }
      // A single tiny nudge hints that the rail scrolls, while keeping the
      // selected leading card almost fully visible. Any touch cancels it.
      _categoryAutoTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || !_cuisineScroll.hasClients || _categoryAutoPaused) {
          return;
        }
        final position = _cuisineScroll.position;
        position.animateTo(
          (position.pixels + 18).clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  void _pauseCategoryAutoScroll() {
    _categoryAutoPaused = true;
    _categoryAutoTimer?.cancel();
  }

  void _explore() {
    final target = _restaurantsKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.base,
        alignment: 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(restaurantsProvider);
    final controller = ref.read(restaurantsProvider.notifier);
    final cuisineAsync = ref.watch(cuisineListProvider);
    final fallbackCuisines =
        state.items
            .map((restaurant) => restaurant.cuisine)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final cuisines = cuisineAsync.when(
      data: (values) => values,
      error: (_, _) => fallbackCuisines,
      loading: () => fallbackCuisines,
    );
    _scheduleCategoryAutoScroll(cuisines.length);
    final auth = ref.watch(authControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: ContentFrame(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 700;
            final large = MediaQuery.textScalerOf(context).scale(14) > 18;
            final cardWidth = (box.maxWidth * .72).clamp(240.0, 320.0);
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 350),
                            () => controller.search(value),
                          );
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search restaurants',
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    controller.search('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (state.search.isNotEmpty && state.items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggestions',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final restaurant in state.items.take(5))
                                  ActionChip(
                                    label: Text(restaurant.name),
                                    onPressed: () => context.push(
                                      '/menu/${restaurant.id}',
                                      extra: restaurant,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _DiscoveryHero(
                      wide: wide,
                      name:
                          auth.session?.user.fullName.split(' ').first ??
                          'there',
                      onExplore: _explore,
                      onCart: auth.isAdmin ? null : () => context.push('/cart'),
                      count: cart.itemCount,
                    ),
                  ),
                  if (state.items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Listener(
                        onPointerDown: (_) => _pauseCategoryAutoScroll(),
                        child: SizedBox(
                          height: 104,
                          child: SingleChildScrollView(
                            controller: _cuisineScroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Padding(
                                  key: _cuisineKeys.putIfAbsent(
                                    'All cuisines',
                                    GlobalKey.new,
                                  ),
                                  padding: const EdgeInsets.only(right: 9),
                                  child: FoodCategoryCard(
                                    label: 'All',
                                    asset:
                                        'assets/food/family_north_indian.jpg',
                                    selected: state.selectedCuisine == null,
                                    onTap: () =>
                                        controller.filterByCuisine(null),
                                  ),
                                ),
                                for (final cuisine in cuisines)
                                  Builder(
                                    builder: (context) {
                                      final key = _cuisineKeys.putIfAbsent(
                                        cuisine,
                                        GlobalKey.new,
                                      );
                                      return Padding(
                                        key: key,
                                        padding: const EdgeInsets.only(
                                          right: 9,
                                        ),
                                        child: FoodCategoryCard(
                                          label: cuisine,
                                          asset: cuisineImageAsset(cuisine),
                                          selected:
                                              state.selectedCuisine == cuisine,
                                          onTap: () async {
                                            await controller.filterByCuisine(
                                              state.selectedCuisine == cuisine
                                                  ? null
                                                  : cuisine,
                                            );
                                            if (!context.mounted) return;
                                            final target = key.currentContext;
                                            if (target == null) return;
                                            Scrollable.ensureVisible(
                                              target,
                                              alignment: 0.02,
                                              duration:
                                                  MediaQuery.disableAnimationsOf(
                                                    context,
                                                  )
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 280,
                                                    ),
                                              curve: Curves.easeOutCubic,
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Find your next favourite.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -.6,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Real kitchens. Something for every craving.',
                                  style: TextStyle(
                                    color: AppColors.inkSoft,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      key: _restaurantsKey,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Explore restaurants',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (!state.initialLoading && state.error == null)
                            Text(
                              '${state.total} kitchens',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (state.initialLoading)
                    SliverToBoxAdapter(
                      child: Shimmer(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: wide
                              ? Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    for (var i = 0; i < 4; i++)
                                      SizedBox(
                                        width: (box.maxWidth - 56) / 2,
                                        child: const SkeletonRestaurantCard(),
                                      ),
                                  ],
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: cardWidth,
                                        child: const SkeletonRestaurantCard(),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: cardWidth,
                                        child: const SkeletonRestaurantCard(),
                                      ),
                                    ],
                                  ),
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
                        icon: Icons.restaurant_menu,
                        title: 'No restaurants yet',
                        message: 'Check back for your next great bite.',
                        actionLabel: 'Refresh',
                        onAction: controller.refresh,
                      ),
                    )
                  else if (!wide && !large)
                    SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < state.items.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: i == state.items.length - 1 ? 0 : 12,
                                ),
                                child: SizedBox(
                                  width: cardWidth,
                                  child: Entrance(
                                    index: i,
                                    child: RestaurantCard(
                                      restaurant: state.items[i],
                                      onTap: () => context.push(
                                        '/menu/${state.items[i].id}',
                                        extra: state.items[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverToBoxAdapter(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (var i = 0; i < state.items.length; i++)
                              SizedBox(
                                width: wide
                                    ? (box.maxWidth - 56) / 2
                                    : box.maxWidth - 40,
                                child: Entrance(
                                  index: i,
                                  child: RestaurantCard(
                                    restaurant: state.items[i],
                                    onTap: () => context.push(
                                      '/menu/${state.items[i].id}',
                                      extra: state.items[i],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (state.hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({
    required this.name,
    required this.wide,
    required this.onExplore,
    required this.onCart,
    required this.count,
  });
  final String name;
  final bool wide;
  final VoidCallback onExplore;
  final VoidCallback? onCart;
  final int count;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: .23,
              child: Image.asset(
                'assets/food/rest_sweet_crumb.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xDD101010),
                    Color(0x88101010),
                    Color(0xDD101010),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: wide ? 32 : -90,
            top: 74,
            child: ExcludeSemantics(
              child: Transform.rotate(
                angle: -.18,
                child: Image.asset(
                  'assets/food/hero_burger.png',
                  width: wide ? 320 : 180,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 12,
              20,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.restaurant_rounded,
                      color: AppColors.brandRed,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'QuickBite',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -.8,
                        ),
                      ),
                    ),
                    if (onCart != null)
                      IconButton(
                        tooltip: 'Cart',
                        onPressed: onCart,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                        ),
                        icon: Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          child: const Icon(Icons.shopping_bag_outlined),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'HEY ${name.toUpperCase()}, WHAT’S COOKING?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Big cravings.\nGreat kitchens.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: wide ? 44 : 36,
                    height: 1.04,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Good food starts with a great choice.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: onExplore,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size(210, 48),
                    ),
                    label: const Text('Explore the kitchens'),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
