/// Order state: the customer's paginated history, plus a per-order watcher
/// (detail + status timeline + notifications) whose refresh cadence is
/// driven by the tracking screen's polling loop (2s while active, stopped
/// on dispose/background/terminal/expiry — assignment §13).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/dto/notification_dto.dart';
import '../data/dto/order_dto.dart';
import '../domain/order_status.dart';
import 'auth_controller.dart';
import 'providers.dart';

// ------------------------------ order history -----------------------------

class OrderListState {
  const OrderListState({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.filter,
    this.error,
  });

  final List<OrderSummary> items;
  final int page;
  final int total;
  final bool loading;
  final bool loadingMore;

  /// Optional exact-status filter (`?status=`), server-applied.
  final OrderStatus? filter;
  final ApiException? error;

  bool get initialLoading => loading && items.isEmpty;
  bool get hasMore => items.length < total;
  bool get isEmpty => !loading && items.isEmpty && error == null;

  OrderListState copyWith({
    List<OrderSummary>? items,
    int? page,
    int? total,
    bool? loading,
    bool? loadingMore,
    OrderStatus? filter,
    bool clearFilter = false,
    ApiException? error,
    bool clearError = false,
  }) => OrderListState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    filter: clearFilter ? null : (filter ?? this.filter),
    error: clearError ? null : (error ?? this.error),
  );
}

class OrderListController extends Notifier<OrderListState> {
  static const int pageSize = 20;

  @override
  OrderListState build() {
    // Riverpod 3: defer the first load one microtask — `state` cannot be
    // read while build() is still on the stack.
    Future.microtask(refresh);
    return const OrderListState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref
          .read(orderRepositoryProvider)
          .myOrders(
            page: 1,
            pageSize: pageSize,
            status: state.filter?.apiValue,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        items: page.items,
        page: 1,
        total: page.total,
        loading: false,
        clearError: true,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: exc);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final next = await ref
          .read(orderRepositoryProvider)
          .myOrders(
            page: state.page + 1,
            pageSize: pageSize,
            status: state.filter?.apiValue,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        items: [...state.items, ...next.items],
        page: next.page,
        total: next.total,
        loadingMore: false,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingMore: false, error: exc);
    }
  }

  /// Server-side status filter (assignment: only where the contract
  /// supports it — it does, on GET /orders).
  Future<void> setFilter(OrderStatus? filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(
      filter: filter ?? OrderStatus.pending,
      clearFilter: filter == null,
    );
    await refresh();
  }
}

final orderListProvider = NotifierProvider<OrderListController, OrderListState>(
  OrderListController.new,
);

// --------------------------- per-order watcher ----------------------------

class OrderWatchState {
  const OrderWatchState({
    required this.orderId,
    this.order,
    this.history = const [],
    this.notifications,
    this.refreshing = false,
    this.firstLoad = true,
    this.refreshError,
    this.consecutiveErrors = 0,
    this.lastRefreshAt,
  });

  final String orderId;
  final OrderDetail? order;
  final List<OrderHistoryEntry> history;

  /// Null until the first successful load; then a live paginated snapshot.
  final PagedNotifications? notifications;
  final bool refreshing;
  final bool firstLoad;
  final ApiException? refreshError;

  /// For polling backoff (assignment: back off after network errors).
  final int consecutiveErrors;
  final DateTime? lastRefreshAt;

  bool get initialLoading => firstLoad && order == null && refreshing;
  bool get hasOrder => order != null;
  bool get isTerminal => order?.status.isTerminal ?? false;

  OrderWatchState copyWith({
    OrderDetail? order,
    List<OrderHistoryEntry>? history,
    PagedNotifications? notifications,
    bool? refreshing,
    bool? firstLoad,
    ApiException? refreshError,
    bool clearError = false,
    int? consecutiveErrors,
    DateTime? lastRefreshAt,
  }) => OrderWatchState(
    orderId: orderId,
    order: order ?? this.order,
    history: history ?? this.history,
    notifications: notifications ?? this.notifications,
    refreshing: refreshing ?? this.refreshing,
    firstLoad: firstLoad ?? this.firstLoad,
    refreshError: clearError ? null : (refreshError ?? this.refreshError),
    consecutiveErrors: consecutiveErrors ?? this.consecutiveErrors,
    lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
  );
}

/// Notification page wrapper keeps `Paged` generic-free here.
class PagedNotifications {
  const PagedNotifications({
    required this.items,
    required this.page,
    required this.total,
  });

  final List<NotificationEntry> items;
  final int page;
  final int total;

  bool get hasMore => items.length < total;

  PagedNotifications appended(List<NotificationEntry> more) =>
      PagedNotifications(
        items: [...items, ...more],
        page: page + 1,
        total: total,
      );
}

class OrderWatchController extends Notifier<OrderWatchState> {
  OrderWatchController(this.orderId)
    : _initial = OrderWatchState(orderId: orderId, refreshing: true);

  final String orderId;
  final OrderWatchState _initial;

  bool _inFlight = false;

  @override
  OrderWatchState build() {
    // Riverpod 3: defer the first load one microtask — `state` cannot be
    // read while build() is still on the stack.
    Future.microtask(refresh);
    return _initial;
  }

  /// Reload order detail + timeline (+ notifications on first load).
  /// Concurrency-safe: overlapping poll ticks collapse into one request.
  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    if (state.order != null) {
      state = state.copyWith(refreshing: true);
    }
    try {
      final repo = ref.read(orderRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      if (!auth.isSignedIn) {
        _inFlight = false;
        return;
      }
      final detail = await repo.order(orderId);
      final history = await repo.history(orderId);
      final page = await repo.notifications(orderId, page: 1, pageSize: 20);
      final previous =
          state.notifications?.items ?? const <NotificationEntry>[];
      final firstPageIds = page.items.map((entry) => entry.id).toSet();
      final older = previous.where((entry) => !firstPageIds.contains(entry.id));
      final notifications = PagedNotifications(
        items: [...page.items, ...older],
        page: state.notifications?.page ?? page.page,
        total: page.total,
      );
      if (!ref.mounted) {
        _inFlight = false;
        return;
      }
      state = state.copyWith(
        order: detail,
        history: history,
        notifications: notifications,
        refreshing: false,
        firstLoad: false,
        clearError: true,
        consecutiveErrors: 0,
        lastRefreshAt: DateTime.now(),
      );
    } on ApiException catch (exc) {
      if (!ref.mounted) {
        _inFlight = false;
        return;
      }
      if (exc.isUnauthorized) {
        // Session ended: stop the watcher; the router will redirect.
        state = state.copyWith(
          refreshing: false,
          firstLoad: false,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          refreshing: false,
          firstLoad: false,
          refreshError: exc,
          consecutiveErrors: state.consecutiveErrors + 1,
          lastRefreshAt: DateTime.now(),
        );
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> loadMoreNotifications() async {
    final current = state.notifications;
    if (current == null || !current.hasMore) return;
    try {
      final page = await ref
          .read(orderRepositoryProvider)
          .notifications(orderId, page: current.page + 1, pageSize: 20);
      if (!ref.mounted) return;
      state = state.copyWith(
        notifications: current.appended(page.items),
        clearError: true,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      state = state.copyWith(refreshError: exc);
    }
  }
}

final orderWatchProvider =
    NotifierProvider.family<OrderWatchController, OrderWatchState, String>(
      OrderWatchController.new,
    );
