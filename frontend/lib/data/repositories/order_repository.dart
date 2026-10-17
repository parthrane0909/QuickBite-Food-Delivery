/// Order repository: idempotent checkout plus owner-scoped reads (list,
/// detail, history, notifications). The Idempotency-Key travels per-call so
/// the checkout controller owns key lifecycle end-to-end.
library;

import '../dto/notification_dto.dart';
import '../dto/order_dto.dart';
import '../dto/paged.dart';
import '../../core/network/api_client.dart';

class OrderRepository {
  const OrderRepository(this._client);

  final ApiClient _client;

  /// POST /orders — 202 acceptance or ApiException (409 conflict, 4xx
  /// definite rejection, timeout/network = UNCERTAIN outcome).
  Future<CheckoutAccepted> checkout({
    required String idempotencyKey,
    required String restaurantId,
    required String deliveryAddress,
    required List<CheckoutItem> items,
  }) async {
    final json = await _client.post(
      'orders',
      headers: {'Idempotency-Key': idempotencyKey},
      body: {
        'restaurant_id': restaurantId,
        'delivery_address': deliveryAddress,
        'items': items.map((item) => item.toJson()).toList(),
      },
    );
    return CheckoutAccepted.fromJson(json);
  }

  Future<Paged<OrderSummary>> myOrders({
    int page = 1,
    int pageSize = 20,
    OrderStatusFilter? status,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '$pageSize'};
    if (status != null) query['status'] = status;
    final json = await _client.get('orders', query: query);
    return Paged.fromJson(json, OrderSummary.fromJson);
  }

  Future<OrderDetail> order(String orderId) async {
    final json = await _client.get('orders/$orderId');
    return OrderDetail.fromJson(json);
  }

  /// Full status timeline. The state machine bounds a history at seven
  /// entries (single page in practice); pagination is followed defensively.
  Future<List<OrderHistoryEntry>> history(String orderId) async {
    final entries = <OrderHistoryEntry>[];
    var page = 1;
    while (true) {
      final json = await _client.get(
        'orders/$orderId/history',
        query: {'page': '$page', 'page_size': '100'},
      );
      final paged = Paged.fromJson(json, OrderHistoryEntry.fromJson);
      entries.addAll(paged.items);
      if (!paged.hasMore || paged.items.isEmpty) return entries;
      page += 1;
    }
  }

  Future<Paged<NotificationEntry>> notifications(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final json = await _client.get(
      'orders/$orderId/notifications',
      query: {'page': '$page', 'page_size': '$pageSize'},
    );
    return Paged.fromJson(json, NotificationEntry.fromJson);
  }
}

/// `status` query value (the server's literal status strings).
typedef OrderStatusFilter = String;
