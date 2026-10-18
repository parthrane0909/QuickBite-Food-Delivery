/// Live order tracking (M5 §3): authoritative status from
/// `GET /orders/{id}` + full status history + persisted notifications.
///
/// Polling contract (assignment §13):
///   - ~2s while THIS screen is visible, the session is valid and the order
///     is not terminal;
///   - STOPS on dispose, on terminal states (DRIVER_ASSIGNED /
///     PAYMENT_FAILED / FAILED) and when auth ends;
///   - backs off after consecutive network errors (2s -> 4s -> ... -> 30s);
///   - pauses when the app is backgrounded and refreshes immediately on
///     resume;
///   - RabbitMQ-down after acceptance still shows PENDING (never a fake
///     payment failure) — status text ALWAYS comes from the server.
///
/// On wide viewports the same content adapts into a two-column layout.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/datetime.dart';
import '../../data/dto/notification_dto.dart';
import '../../domain/order_status.dart';
import '../../state/auth_controller.dart';
import '../../state/orders_providers.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/motion/shimmer.dart';
import '../../ui/widgets/app_banner.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/section_header.dart';
import '../../ui/widgets/status_chip.dart';

const Duration _basePollInterval = Duration(seconds: 2);
const Duration _maxPollInterval = Duration(seconds: 30);

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      // Fresh authoritative fetch on return to foreground, then resume the
      // normal cadence (backoff resets on success inside the controller).
      _timer?.cancel();
      _refreshThenReschedule();
    } else {
      // Backgrounded: stop polling entirely (assignment §13).
      _timer?.cancel();
    }
  }

  bool get _canPoll {
    if (!mounted) return false;
    if (_lifecycle != AppLifecycleState.resumed) return false;
    final auth = ref.read(authControllerProvider);
    if (!auth.isSignedIn) return false;
    final watch = ref.read(orderWatchProvider(widget.orderId));
    if (watch.isTerminal) return false;
    return true;
  }

  Duration get _currentInterval {
    final errors = ref
        .read(orderWatchProvider(widget.orderId))
        .consecutiveErrors;
    if (errors <= 0) return _basePollInterval;
    final backoffMs =
        _basePollInterval.inMilliseconds * (1 << math.min(errors, 4));
    return Duration(
      milliseconds: math.min(backoffMs, _maxPollInterval.inMilliseconds),
    );
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!_canPoll) return;
    final interval = _currentInterval;
    _timer = Timer(interval, _refreshThenReschedule);
  }

  Future<void> _refreshThenReschedule() async {
    await ref.read(orderWatchProvider(widget.orderId).notifier).refresh();
    if (!mounted) return;
    _scheduleNext();
  }

  Future<void> _manualRefresh() async {
    _timer?.cancel();
    await ref.read(orderWatchProvider(widget.orderId).notifier).refresh();
    if (mounted) _scheduleNext();
  }

  /// Explicit exit for a full-screen route: the acceptance screen reaches
  /// tracking with `go()` (no push stack) and a deep-link reload starts with
  /// an empty stack — without this the user would be stranded with no way to
  /// the order history. Falls back to the history branch (admins are then
  /// redirected to /admin by the router).
  Widget _backButton() => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/orders');
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final watch = ref.watch(orderWatchProvider(widget.orderId));
    final text = Theme.of(context).textTheme;

    // Auth loss while visible: the router will redirect; kill the timer now.
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.isSignedIn) _timer?.cancel();
      // A restored sign-in (e.g. re-login in another tab) resumes polling.
      if (next.isSignedIn && previous?.isSignedIn != true && _timer == null) {
        _scheduleNext();
      }
    });

    if (watch.initialLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: const Text('Order details'),
        ),
        body: const Shimmer(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 120, radius: AppSpacing.radiusLg),
                SizedBox(height: AppSpacing.cardGap),
                SkeletonBox(height: 220, radius: AppSpacing.radiusLg),
                SizedBox(height: AppSpacing.cardGap),
                SkeletonBox(height: 180, radius: AppSpacing.radiusLg),
              ],
            ),
          ),
        ),
      );
    }

    final order = watch.order;
    final error = watch.refreshError;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: const Text('Order details'),
        ),
        body: error == null
            ? const LoadingState()
            : ErrorState(error: error, onRetry: _manualRefresh),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final statusCard = Entrance(
      index: 0,
      child: _StatusCard(watch: watch, onRefresh: _manualRefresh),
    );
    final timelineCard = Entrance(index: 1, child: _TimelineCard(watch: watch));
    final detailsCard = Entrance(index: 2, child: _DetailsCard(watch: watch));
    final notificationsCard = Entrance(
      index: 3,
      child: _NotificationsCard(
        watch: watch,
        onLoadMore: () => ref
            .read(orderWatchProvider(widget.orderId).notifier)
            .loadMoreNotifications(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(),
        title: const Text('Order details'),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: _manualRefresh,
            icon: watch.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _manualRefresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.desktopMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                if (error != null) ...[
                  AppBanner(
                    kind: AppBannerKind.warning,
                    message:
                        'Connection trouble — showing the last known state. ${error.message}',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            statusCard,
                            const SizedBox(height: AppSpacing.cardGap),
                            timelineCard,
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.cardGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            detailsCard,
                            const SizedBox(height: AppSpacing.cardGap),
                            notificationsCard,
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      statusCard,
                      const SizedBox(height: AppSpacing.cardGap),
                      timelineCard,
                      const SizedBox(height: AppSpacing.cardGap),
                      detailsCard,
                      const SizedBox(height: AppSpacing.cardGap),
                      notificationsCard,
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Polling every ${_basePollInterval.inSeconds}s while you watch this '
                  'screen — paused when the app is in the background or the order '
                  'reaches a final state.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------- status -----------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.watch, required this.onRefresh});

  final OrderWatchState watch;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final order = watch.order;
    if (order == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.restaurantName,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusChip(order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Order ${order.id}',
              style: text.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            if (watch.lastRefreshAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  if (!watch.isTerminal) ...[
                    const LivePulse(color: AppColors.primary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    'Updated ${formatTime(watch.lastRefreshAt!.toLocal())}',
                    style: text.labelSmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _ProgressTrack(status: order.status),
            const SizedBox(height: AppSpacing.md),
            if (order.status.isSuccess)
              const AppBanner(
                kind: AppBannerKind.success,
                icon: Icons.two_wheeler_rounded,
                message:
                    'A driver has been assigned — this is the final state '
                    'of the QuickBite delivery flow.',
              )
            else if (order.status.isFailure)
              AppBanner(
                kind: AppBannerKind.danger,
                message:
                    order.failureReason ??
                    'This order failed${order.failureCode != null ? ' (${order.failureCode})' : ''}.',
              )
            else if (!watch.isTerminal)
              AppBanner(
                kind: AppBannerKind.info,
                message:
                    'Processing — we will update this screen automatically.',
              ),
            if (order.status.isTerminal && !order.status.isSuccess) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Report issue (contact support)'),
                onPressed: null, // intentionally disabled: no support backend
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------ timeline ----------------------------------

/// Compact horizontal progress track mirroring the REAL state machine
/// (PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED). Failure terminals stop the
/// track at the stage that failed; no step is ever invented (the contract has
/// no DELIVERED state and no GPS tracking).
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.status});

  final OrderStatus status;

  static const List<(String, String)> _steps = [
    ('Placed', 'PENDING'),
    ('Paid', 'PAID'),
    ('Confirmed', 'CONFIRMED'),
    ('Driver', 'DRIVER_ASSIGNED'),
  ];

  int get _current => switch (status) {
    OrderStatus.pending => 0,
    OrderStatus.paid => 1,
    OrderStatus.confirmed => 2,
    OrderStatus.driverAssigned => 3,
    // Failures report the stage that failed: payment, or confirmation.
    OrderStatus.paymentFailed => 1,
    OrderStatus.failed => 2,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = status.isFailure;
    final current = _current;
    final accent = failed ? AppColors.danger : AppColors.primary;

    return Semantics(
      container: true,
      label:
          'Order progress: ${_steps[current].$1} of ${_steps.length}'
          '${failed ? ', failed' : ''}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 3,
                            color: i > 0 && i <= current
                                ? accent
                                : AppColors.outlineSoft,
                          ),
                        ),
                        _Dot(
                          reached: i < current || (i == current && failed),
                          current: i == current && !failed,
                          failed: failed && i == current,
                          upcoming: i > current,
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: i < current
                                ? accent
                                : AppColors.outlineSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _steps[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: text.labelSmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: i == current
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: i == current
                            ? accent
                            : (i < current ? AppColors.ink : AppColors.inkFaint),
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
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.reached,
    required this.current,
    required this.failed,
    required this.upcoming,
  });

  final bool reached;
  final bool current;
  final bool failed;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? AppColors.danger
        : (upcoming ? AppColors.outlineSoft : AppColors.primary);
    final size = current || failed ? 22.0 : 18.0;
    return SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: (reached || failed || current)
                ? color
                : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: (reached || failed || current)
              ? Icon(
                  failed ? Icons.close_rounded : Icons.check_rounded,
                  size: 12,
                  color: AppColors.onPrimary,
                )
              : null,
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.watch});

  final OrderWatchState watch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final history = watch.history;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status history',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (history.isEmpty)
              Text('No transitions recorded yet.', style: text.bodySmall)
            else
              for (var i = 0; i < history.length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: i == history.length - 1
                                ? AppColors.primary
                                : AppColors.primaryTint,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        if (i != history.length - 1)
                          Container(
                            width: 2,
                            height: 44,
                            color: AppColors.outlineSoft,
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: i == history.length - 1 ? 0 : AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    history[i].status.label,
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  'v${history[i].version}',
                                  style: text.labelSmall,
                                ),
                              ],
                            ),
                            Text(
                              formatDateTime(history[i].changedAt),
                              style: text.bodySmall,
                            ),
                            if (history[i].failureCode != null)
                              Text(
                                'Reason: ${history[i].failureCode}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              'Source: ${history[i].source}',
                              style: text.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------- details ----------------------------------

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.watch});

  final OrderWatchState watch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final order = watch.order;
    if (order == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order summary',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final line in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity} × ${line.itemName}',
                        style: text.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    MoneyText(
                      line.lineTotalMinor,
                      currency: line.currency,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order total',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                MoneyText(
                  order.totalAmountMinor,
                  currency: order.currency,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Delivery address', style: text.labelMedium),
            const SizedBox(height: 2),
            Text(order.deliveryAddress, style: text.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            Text('Placed', style: text.labelMedium),
            const SizedBox(height: 2),
            Text(formatDateTime(order.createdAt), style: text.bodyMedium),
            if (order.driverId != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.two_wheeler_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your driver',
                            style: text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            order.driverId!,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (order.failureReason != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppBanner(
                kind: AppBannerKind.danger,
                message: order.failureReason!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------- notifications --------------------------------

IconData _notificationIcon(String type) => switch (type) {
  'order.created' => Icons.receipt_long_rounded,
  'payment.captured' => Icons.payments_rounded,
  'payment.failed' => Icons.credit_card_off_rounded,
  'restaurant.confirmed' => Icons.task_alt_rounded,
  'restaurant.rejected' => Icons.cancel_outlined,
  'driver.assigned' => Icons.two_wheeler_rounded,
  'notification.failed' => Icons.notifications_off_outlined,
  _ => Icons.notifications_outlined,
};

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.watch, required this.onLoadMore});

  final OrderWatchState watch;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final feed = watch.notifications;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Notifications'),
            if (feed == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (feed.items.isEmpty)
              Text(
                'No notifications for this order yet — they appear as the '
                'order progresses.',
                style: text.bodySmall,
              )
            else
              for (var i = 0; i < feed.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Container(
                    padding: i == 0
                        ? const EdgeInsets.all(AppSpacing.sm)
                        : EdgeInsets.zero,
                    decoration: i == 0
                        ? BoxDecoration(
                            color: AppColors.surfaceWarm,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(color: AppColors.outlineSoft),
                          )
                        : null,
                    child: _NotificationRow(
                      entry: feed.items[i],
                      latest: i == 0,
                    ),
                  ),
                ),
            if (feed != null && feed.hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    'Load more (${feed.total - feed.items.length} more)',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One persisted notification. The newest entry is visually emphasised
/// (tinted card + "Latest" tag) so the most recent server event reads first.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.entry, required this.latest});

  final NotificationEntry entry;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: entry.isFailure
                ? AppColors.dangerTint
                : AppColors.primaryTint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _notificationIcon(entry.type),
            size: 17,
            color: entry.isFailure ? AppColors.danger : AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.message, style: text.bodyMedium),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${_typeLabel(entry.type)} · ${formatRelative(entry.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall,
                    ),
                  ),
                  if (latest) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                      ),
                      child: const Text(
                        'Latest',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (entry.type == 'notification.failed') ...[
                const SizedBox(height: 4),
                Text(
                  'Notification delivery failed — your ORDER is '
                  'unaffected.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.info,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _typeLabel(String type) => switch (type) {
  'order.created' => 'Order created',
  'payment.captured' => 'Payment captured',
  'payment.failed' => 'Payment failed',
  'restaurant.confirmed' => 'Restaurant confirmed',
  'restaurant.rejected' => 'Restaurant rejected',
  'driver.assigned' => 'Driver assigned',
  'notification.failed' => 'Notification issue',
  _ => type,
};
