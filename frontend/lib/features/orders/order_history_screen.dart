/// Order history (M5 §3): the signed-in customer's OWN orders from
/// `GET /orders` — paginated, optional server-side status filter, real
/// statuses from the backend state machine. Tap an order to open live
/// tracking. Customers only (admins are routed to the admin overview; the
/// API would answer 403 on this endpoint regardless).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/datetime.dart';
import '../../data/dto/order_dto.dart';
import '../../domain/order_status.dart';
import '../../state/orders_providers.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/paginated_list_view.dart';
import '../../ui/widgets/status_chip.dart';
import '../shell/app_shell.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  static const List<OrderStatus?> _filters = <OrderStatus?>[
    null,
    OrderStatus.pending,
    OrderStatus.paid,
    OrderStatus.confirmed,
    OrderStatus.driverAssigned,
    OrderStatus.paymentFailed,
    OrderStatus.failed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderListProvider);
    final controller = ref.read(orderListProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < AppShell.wideBreakpoint;
    // Icon-only logout below 480w keeps the title un-crowded (tooltip and
    // semantics carry the accessible name).

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order history'),
        actions: [
          if (narrow) LogoutButton(iconOnly: width < 480),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Server-side status filter (contract-supported `?status=`).
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final selected = state.filter == filter;
                return ChoiceChip(
                  label: Text(filter?.label ?? 'All'),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primary : AppColors.ink,
                  ),
                  onSelected: (_) => controller.setFilter(filter),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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

  final OrderListState state;
  final OrderListController controller;

  @override
  Widget build(BuildContext context) {
    if (state.initialLoading) {
      return const LoadingState(label: 'Loading your orders…');
    }

    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return ErrorState(error: error, onRetry: controller.refresh);
    }

    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: state.filter == null ? 'No orders yet' : 'No ${state.filter!.label.toLowerCase()} orders',
        message: state.filter == null
            ? 'Orders you place will appear here with live status updates.'
            : 'Try a different status filter.',
        actionLabel: 'Browse restaurants',
        onAction: () => context.go('/restaurants'),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.desktopMaxWidth),
        child: PaginatedListView<OrderSummary>(
          items: state.items,
          hasMore: state.hasMore,
          loadingMore: state.loadingMore,
          onRefresh: controller.refresh,
          onLoadMore: controller.loadMore,
          itemBuilder: (context, index) {
            final order = state.items[index];
            return _OrderCard(
              order: order,
              onTap: () => context.push('/orders/${order.id}'),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Order from ${order.restaurantName}, status ${order.status.label}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: text.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(formatDateTime(order.createdAt), style: text.bodySmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Order ${order.id}',
                        style: text.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(order.totalAmountMinor, currency: order.currency),
                    const SizedBox(height: AppSpacing.sm),
                    StatusChip(order.status, compact: true),
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
