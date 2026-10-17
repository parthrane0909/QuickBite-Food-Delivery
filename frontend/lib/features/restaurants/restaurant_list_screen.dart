/// Restaurant browsing (assignment §7 / M5 §3): REAL seeded restaurants from
/// PostgreSQL through FastAPI — pagination (infinite scroll + pull to
/// refresh), loading / empty / error states. Role-aware app bar: cart badge
/// for customers; admins get read-only browsing (checkout is unreachable
/// for them via the router).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_providers.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/paginated_list_view.dart';
import '../shell/app_shell.dart';
import 'widgets/restaurant_card.dart';

class RestaurantListScreen extends ConsumerWidget {
  const RestaurantListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(restaurantsProvider);
    final isAdmin = ref.watch(authControllerProvider.select((auth) => auth.isAdmin));
    final cartCount = ref.watch(cartControllerProvider.select((cart) => cart.itemCount));
    final controller = ref.read(restaurantsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < AppShell.wideBreakpoint;
    // On phone-width app bars the labeled logout crowds the title out; the
    // icon-only variant keeps both reachable (tooltip + semantics carry the
    // accessible name).
    final compactActions = width < 480;

    return Scaffold(
      appBar: AppBar(
        // Flexible title text: on narrow phones the action buttons leave the
        // title slot little room, and the Row must never overflow.
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo_mark.png',
              width: 30,
              height: 30,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.fastfood_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Flexible(
              child: Text('QuickBite', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (!isAdmin) ...[
            IconButton(
              tooltip: 'Cart',
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: cartCount > 0,
                label: Text('$cartCount'),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
          ],
          if (narrow) LogoutButton(iconOnly: compactActions),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              0,
            ),
            child: Text('All restaurants', style: text.headlineSmall),
          ),
          Expanded(
            child: _Body(state: state, controller: controller),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.controller});

  final RestaurantsState state;
  final RestaurantsController controller;

  @override
  Widget build(BuildContext context) {
    if (state.initialLoading) return const LoadingState(label: 'Loading restaurants…');

    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return ErrorState(error: error, onRetry: controller.refresh);
    }

    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.restaurant_menu_rounded,
        title: 'No restaurants yet',
        message: 'Once restaurants are seeded in QuickBite, they will appear here.',
        actionLabel: 'Refresh',
        onAction: controller.refresh,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.desktopMaxWidth),
        child: PaginatedListView(
          items: state.items,
          hasMore: state.hasMore,
          loadingMore: state.loadingMore,
          onRefresh: controller.refresh,
          onLoadMore: controller.loadMore,
          itemBuilder: (context, index) {
            final restaurant = state.items[index];
            return RestaurantCard(
              restaurant: restaurant,
              onTap: () => context.push('/menu/${restaurant.id}', extra: restaurant),
            );
          },
        ),
      ),
    );
  }
}
