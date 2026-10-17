/// Admin dashboard state (READ-ONLY): aggregate summary + cross-customer
/// orders with server-side status filtering and pagination.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/dto/admin_dto.dart';
import '../domain/order_status.dart';
import 'providers.dart';

// -------------------------------- summary ---------------------------------

class AdminSummaryState {
  const AdminSummaryState({this.summary, this.loading = false, this.error});

  final AdminSummary? summary;
  final bool loading;
  final ApiException? error;

  bool get initialLoading => loading && summary == null;

  AdminSummaryState copyWith({
    AdminSummary? summary,
    bool? loading,
    ApiException? error,
    bool clearError = false,
  }) =>
      AdminSummaryState(
        summary: summary ?? this.summary,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AdminSummaryController extends Notifier<AdminSummaryState> {
  @override
  AdminSummaryState build() {
    // Riverpod 3: defer the first load one microtask — `state` cannot be
    // read while build() is still on the stack.
    Future.microtask(refresh);
    return const AdminSummaryState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final summary = await ref.read(adminRepositoryProvider).summary();
      if (!ref.mounted) return;
      state = state.copyWith(summary: summary, loading: false, clearError: true);
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: exc);
    }
  }
}

final adminSummaryProvider =
    NotifierProvider<AdminSummaryController, AdminSummaryState>(
  AdminSummaryController.new,
);

// ----------------------------- admin orders -------------------------------

class AdminOrdersState {
  const AdminOrdersState({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.filter,
    this.error,
  });

  final List<AdminOrderItem> items;
  final int page;
  final int total;
  final bool loading;
  final bool loadingMore;
  final OrderStatus? filter;
  final ApiException? error;

  bool get initialLoading => loading && items.isEmpty;
  bool get hasMore => items.length < total;
  bool get isEmpty => !loading && items.isEmpty && error == null;

  AdminOrdersState copyWith({
    List<AdminOrderItem>? items,
    int? page,
    int? total,
    bool? loading,
    bool? loadingMore,
    OrderStatus? filter,
    bool clearFilter = false,
    ApiException? error,
    bool clearError = false,
  }) =>
      AdminOrdersState(
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        filter: clearFilter ? null : (filter ?? this.filter),
        error: clearError ? null : (error ?? this.error),
      );
}

class AdminOrdersController extends Notifier<AdminOrdersState> {
  static const int pageSize = 20;

  @override
  AdminOrdersState build() {
    // Riverpod 3: defer the first load one microtask — `state` cannot be
    // read while build() is still on the stack.
    Future.microtask(refresh);
    return const AdminOrdersState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref.read(adminRepositoryProvider).orders(
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
      final next = await ref.read(adminRepositoryProvider).orders(
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

  Future<void> setFilter(OrderStatus? filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(
      filter: filter ?? OrderStatus.pending,
      clearFilter: filter == null,
    );
    await refresh();
  }
}

final adminOrdersProvider =
    NotifierProvider<AdminOrdersController, AdminOrdersState>(
  AdminOrdersController.new,
);
