/// Read-only admin dashboard (M5 §7): aggregate counts from
/// `GET /admin/summary` + cross-customer orders from `GET /admin/orders`
/// (paginated, server-side status filter). NO mutations exist client-side or
/// server-side by design; tapping an order opens the same tracking screen
/// (the order endpoint allows owner-or-admin reads).
///
/// Counting semantics (from docs/api.md):
///   orders_by_status        — every status key, zeros included
///   pending_outbox_events   — outbox rows not yet confirmed published
///   retry_backlog           — retry jobs still scheduled (state PENDING)
///   quarantine_records      — terminally failed deliveries on record
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/datetime.dart';
import '../../data/dto/admin_dto.dart';
import '../../domain/order_status.dart';
import '../../state/admin_providers.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/status_chip.dart';
import '../shell/app_shell.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

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
    final summary = ref.watch(adminSummaryProvider);
    final orders = ref.watch(adminOrdersProvider);
    final ordersController = ref.read(adminOrdersProvider.notifier);
    final summaryController = ref.read(adminSummaryProvider.notifier);
    final narrow = MediaQuery.sizeOf(context).width < AppShell.wideBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh data',
            onPressed: () {
              summaryController.refresh();
              ordersController.refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (narrow)
            LogoutButton(iconOnly: MediaQuery.sizeOf(context).width < 480),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.desktopMaxWidth,
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                summaryController.refresh(),
                ordersController.refresh(),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                _SummarySection(
                  state: summary,
                  onRetry: summaryController.refresh,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Orders (all customers)',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Read-only: tap an order to follow its real status.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final filter = _filters[index];
                      final selected = orders.filter == filter;
                      return ChoiceChip(
                        label: Text(filter?.label ?? 'All'),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          // White on the coral selection pill (chipTheme's
                          // selectedColor) — coral-on-coral was invisible.
                          color: selected ? AppColors.onPrimary : AppColors.ink,
                        ),
                        onSelected: (_) => ordersController.setFilter(filter),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _OrdersSection(state: orders, controller: ordersController),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------- summary ----------------------------------

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.state, required this.onRetry});

  final AdminSummaryState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (state.initialLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 22),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 72, radius: AppSpacing.radiusLg),
              SizedBox(height: AppSpacing.md),
              SkeletonBox(height: 72, radius: AppSpacing.radiusLg),
            ],
          ),
        ),
      );
    }
    final error = state.error;
    if (error != null && state.summary == null) {
      return ErrorState(error: error, onRetry: onRetry, compact: true);
    }
    final summary = state.summary;
    if (summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Summary',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceWarm,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(color: AppColors.outlineSoft),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Read-only',
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'As of ${formatDateTime(summary.generatedAt)}',
          style: text.labelSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        // Responsive stat grid: cards fill the row evenly (1–4 per row)
        // instead of leaving a ragged fixed-width tail.
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppSpacing.md;
            final columns = (constraints.maxWidth / 190).floor().clamp(1, 4);
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final status in OrderStatus.values)
                  _StatCard(
                    width: cardWidth,
                    label: status.label,
                    value: '${summary.countFor(status)}',
                    tint: status.isFailure
                        ? AppColors.dangerTint
                        : status.isSuccess
                        ? AppColors.successTint
                        : AppColors.surfaceWarm,
                    valueColor: status.isFailure
                        ? AppColors.danger
                        : status.isSuccess
                        ? AppColors.success
                        : AppColors.ink,
                  ),
                _StatCard(
                  width: cardWidth,
                  label: 'Pending outbox events',
                  value: '${summary.pendingOutboxEvents}',
                  subtitle: 'not yet published',
                  tint: AppColors.infoTint,
                  valueColor: AppColors.info,
                ),
                _StatCard(
                  width: cardWidth,
                  label: 'Retry backlog',
                  value: '${summary.retryBacklog}',
                  subtitle: 'scheduled retries',
                  tint: AppColors.warningTint,
                  valueColor: AppColors.warning,
                ),
                _StatCard(
                  width: cardWidth,
                  label: 'Quarantine records',
                  value: '${summary.quarantineRecords}',
                  subtitle: 'failed deliveries',
                  tint: AppColors.dangerTint,
                  valueColor: AppColors.danger,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Counts come straight from PostgreSQL. Outbox = events not yet '
          'confirmed published; retry backlog = scheduled attempts neither '
          'published nor exhausted; quarantine = terminally failed '
          'deliveries. This dashboard is read-only.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.tint,
    required this.valueColor,
    this.subtitle,
    this.width = 168,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color tint;
  final Color valueColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: text.labelMedium, maxLines: 2),
              if (subtitle != null) Text(subtitle!, style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------- admin orders --------------------------------

/// Rendered INSIDE the dashboard's outer scroll view (no nested ListView —
/// the parent already scrolls and owns the RefreshIndicator). Pagination
/// still follows the contract: a footer action fetches the next page.
class _OrdersSection extends StatelessWidget {
  const _OrdersSection({required this.state, required this.controller});

  final AdminOrdersState state;
  final AdminOrdersController controller;

  @override
  Widget build(BuildContext context) {
    if (state.initialLoading) {
      return const Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonListTile(),
            SizedBox(height: AppSpacing.cardGap),
            SkeletonListTile(),
            SizedBox(height: AppSpacing.cardGap),
            SkeletonListTile(),
          ],
        ),
      );
    }

    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return ErrorState(error: error, onRetry: controller.refresh);
    }
    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No orders match',
        message: state.filter == null
            ? 'No orders exist yet.'
            : 'No orders with status ${state.filter!.label}.',
        actionLabel: 'Refresh',
        onAction: controller.refresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < state.items.length; i++) ...[
          Entrance(
            index: i,
            child: _AdminOrderCard(
              order: state.items[i],
              onTap: () => context.push('/orders/${state.items[i].id}'),
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
        ],
        if (state.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (state.hasMore)
          Center(
            child: TextButton.icon(
              onPressed: controller.loadMore,
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({required this.order, required this.onTap});

  final AdminOrderItem order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      child: Semantics(
        button: true,
        label:
            'Order by ${order.customerEmail} from ${order.restaurantName}, '
            'status ${order.status.label}',
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            boxShadow: AppShadow.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerEmail,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.restaurantName,
                      style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${formatDateTime(order.createdAt)} · v${order.version}'
                      '${order.failureCode != null ? ' · ${order.failureCode}' : ''}',
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    order.totalAmountMinor,
                    currency: order.currency,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  StatusChip(order.status, compact: true),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
