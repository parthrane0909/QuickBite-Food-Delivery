/// Catalog state: the restaurant list (paginated) and per-restaurant menus
/// (paginated exactly per the contract — page/page_size only). Riverpod 3
/// family style: constructor argument instead of the removed
/// FamilyNotifier.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/dto/catalog_dto.dart';
import 'providers.dart';

// ------------------------------ restaurants -------------------------------

class RestaurantsState {
  const RestaurantsState({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.search = '',
    this.selectedCuisine,
  });

  final List<Restaurant> items;
  final int page;
  final int total;
  final bool loading;
  final bool loadingMore;
  final ApiException? error;
  final String search;
  final String? selectedCuisine;

  bool get initialLoading => loading && items.isEmpty;
  bool get hasMore => items.length < total;
  bool get isEmpty => !loading && items.isEmpty && error == null;

  RestaurantsState copyWith({
    List<Restaurant>? items,
    int? page,
    int? total,
    bool? loading,
    bool? loadingMore,
    ApiException? error,
    bool clearError = false,
    String? search,
    String? selectedCuisine,
    bool clearCuisine = false,
  }) => RestaurantsState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    search: search ?? this.search,
    selectedCuisine: clearCuisine
        ? null
        : (selectedCuisine ?? this.selectedCuisine),
  );
}

class RestaurantsController extends Notifier<RestaurantsState> {
  static const int pageSize = 20;
  int _requestGeneration = 0;

  @override
  RestaurantsState build() {
    // Riverpod 3: `state` is not readable while build() is still running, so
    // the first load is deferred one microtask (it touches state immediately).
    Future.microtask(refresh);
    return const RestaurantsState(loading: true);
  }

  Future<void> refresh({String? search, String? cuisine}) async {
    final generation = ++_requestGeneration;
    final query = search ?? state.search;
    final selectedCuisine = cuisine ?? state.selectedCuisine;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .restaurants(
            page: 1,
            pageSize: pageSize,
            search: query,
            cuisine: selectedCuisine,
          );
      if (!ref.mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        items: page.items,
        page: 1,
        total: page.total,
        search: query,
        selectedCuisine: selectedCuisine,
        loading: false,
        clearError: true,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted || generation != _requestGeneration) return;
      state = state.copyWith(loading: false, error: exc);
    }
  }

  Future<void> search(String query) async {
    if (query.trim() == state.search) return;
    state = state.copyWith(
      items: const [],
      page: 0,
      total: 0,
      search: query.trim(),
    );
    await refresh(search: query.trim());
  }

  Future<void> filterByCuisine(String? cuisine) async {
    if (cuisine == state.selectedCuisine) return;
    state = state.copyWith(
      items: const [],
      page: 0,
      total: 0,
      selectedCuisine: cuisine,
      clearCuisine: cuisine == null,
    );
    await refresh(cuisine: cuisine);
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    final generation = _requestGeneration;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final next = await ref
          .read(catalogRepositoryProvider)
          .restaurants(
            page: state.page + 1,
            pageSize: pageSize,
            search: state.search,
            cuisine: state.selectedCuisine,
          );
      if (!ref.mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        items: [...state.items, ...next.items],
        page: next.page,
        total: next.total,
        loadingMore: false,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted || generation != _requestGeneration) return;
      state = state.copyWith(loadingMore: false, error: exc);
    }
  }

  /// Best-effort lookup for deep links (single-restaurant endpoint does not
  /// exist; the contract lists restaurants with pagination).
  Future<Restaurant?> byId(String id) async {
    for (final restaurant in state.items) {
      if (restaurant.id == id) return restaurant;
    }
    var page = 1;
    while (page <= 50) {
      final paged = await ref
          .read(catalogRepositoryProvider)
          .restaurants(page: page, pageSize: 100);
      for (final restaurant in paged.items) {
        if (restaurant.id == id) return restaurant;
      }
      if (!paged.hasMore) return null;
      page += 1;
    }
    return null;
  }
}

final cuisineListProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(catalogRepositoryProvider).cuisines(),
);

final restaurantsProvider =
    NotifierProvider<RestaurantsController, RestaurantsState>(
      RestaurantsController.new,
    );

// --------------------------------- menus ----------------------------------

class MenuState {
  const MenuState({
    required this.restaurantId,
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final String restaurantId;
  final List<MenuItem> items;
  final int page;
  final int total;
  final bool loading;
  final bool loadingMore;
  final ApiException? error;

  bool get initialLoading => loading && items.isEmpty;
  bool get hasMore => items.length < total;
  bool get isEmpty => !loading && items.isEmpty && error == null;

  MenuState copyWith({
    List<MenuItem>? items,
    int? page,
    int? total,
    bool? loading,
    bool? loadingMore,
    ApiException? error,
    bool clearError = false,
  }) => MenuState(
    restaurantId: restaurantId,
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}

class MenuController extends Notifier<MenuState> {
  MenuController(this.restaurantId)
    : _initial = MenuState(restaurantId: restaurantId);

  final String restaurantId;
  final MenuState _initial;

  static const int pageSize = 20;

  @override
  MenuState build() {
    // Riverpod 3: defer the first load one microtask — `state` cannot be
    // read while build() is still on the stack.
    Future.microtask(refresh);
    return _initial.copyWith(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .menu(restaurantId, page: 1, pageSize: pageSize);
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
          .read(catalogRepositoryProvider)
          .menu(restaurantId, page: state.page + 1, pageSize: pageSize);
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
}

final menuProvider = NotifierProvider.family<MenuController, MenuState, String>(
  MenuController.new,
);
