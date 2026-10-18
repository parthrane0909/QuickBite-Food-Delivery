/// Paginated list workhorse: infinite scroll near the end + footer loading
/// indicator + RefreshIndicator support. Screens pass their item builder and
/// an `onLoadMore` that is invoked at most once per trailing edge (the
/// controller's own loadingMore guard makes this idempotent).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class PaginatedListView<T> extends StatefulWidget {
  const PaginatedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    this.hasMore = false,
    this.loadingMore = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenPadding,
      vertical: AppSpacing.md,
    ),
    this.controller,
    this.empty,
    this.separatorBuilder,
    this.gridDelegate,
    this.header,
  });

  final List<T> items;
  final IndexedWidgetBuilder itemBuilder;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final bool hasMore;
  final bool loadingMore;
  final EdgeInsets padding;
  final ScrollController? controller;
  final Widget? empty;
  final IndexedWidgetBuilder? separatorBuilder;

  /// When set, items render in a responsive grid (desktop/tablet layouts)
  /// instead of rows; the load-more footer spans the full width beneath it.
  final SliverGridDelegate? gridDelegate;

  /// Optional widget scrolled ABOVE the items (hero band, section heading).
  /// It shares the same scroll view, so it scrolls away with the content.
  final Widget? header;

  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  ScrollController? _owned;

  ScrollController get _controller {
    final existing = widget.controller;
    if (existing != null) return existing;
    _owned ??= ScrollController();
    return _owned!;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.removeListener(_maybeLoadMore);
    _owned?.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!widget.hasMore || widget.loadingMore) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty && widget.empty != null) {
      return RefreshIndicator(onRefresh: widget.onRefresh, child: widget.empty!);
    }

    final grid = widget.gridDelegate;
    final separator =
        widget.separatorBuilder ??
        (BuildContext _, int _) => const SizedBox(height: AppSpacing.cardGap);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          if (widget.header != null)
            SliverToBoxAdapter(child: widget.header),
          SliverPadding(
            padding: widget.padding,
            sliver: grid != null
                ? SliverGrid(
                    gridDelegate: grid,
                    delegate: SliverChildBuilderDelegate(
                      widget.itemBuilder,
                      childCount: items.length,
                    ),
                  )
                : SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: separator,
                    itemBuilder: widget.itemBuilder,
                  ),
          ),
          if (widget.hasMore || widget.loadingMore)
            SliverToBoxAdapter(
              child: _Footer(
                loading: widget.loadingMore,
                hasMore: widget.hasMore,
                onRetry: widget.hasMore ? widget.onLoadMore : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loading, required this.hasMore, this.onRetry});

  final bool loading;
  final bool hasMore;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (!hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry == null ? null : () => onRetry!(),
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('Load more'),
        ),
      ),
    );
  }
}
