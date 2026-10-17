/// Shared pagination envelope — mirrors the backend contract exactly:
/// `{items, page, page_size, total}` with `page_size <= 100` (422 above).
library;

class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    return Paged<T>(
      items: (json['items'] as List<dynamic>)
          .map((raw) => itemFromJson(raw as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
      total: json['total'] as int,
    );
  }

  /// True when the server reports more rows beyond what we hold.
  bool get hasMore => items.length < total;

  Paged<T> appended(Paged<T> next) => Paged<T>(
        items: [...items, ...next.items],
        page: next.page,
        pageSize: next.pageSize,
        total: next.total,
      );
}
