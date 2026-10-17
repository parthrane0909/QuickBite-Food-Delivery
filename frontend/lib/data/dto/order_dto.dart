/// Order DTOs — verified field-for-field against the backend contract
/// (docs/api.md §Orders). Money is always integer minor units; totals are
/// server-authoritative and never accepted from the client.
library;

import '../../domain/order_status.dart';

class CheckoutItem {
  const CheckoutItem({required this.menuItemId, required this.quantity});

  final String menuItemId;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'menu_item_id': menuItemId,
        'quantity': quantity,
      };
}

class CheckoutAccepted {
  /// The 202 acceptance body — asynchronous acceptance, NOT payment or
  /// delivery completion (assignment: acknowledgement semantics).
  const CheckoutAccepted({
    required this.orderId,
    required this.status,
    required this.currency,
    required this.totalAmountMinor,
    required this.version,
    required this.message,
  });

  final String orderId;
  final OrderStatus status;
  final String currency;
  final int totalAmountMinor;
  final int version;
  final String message;

  factory CheckoutAccepted.fromJson(Map<String, dynamic> json) => CheckoutAccepted(
        orderId: json['order_id'] as String,
        status: OrderStatus.parse(json['status'] as String),
        currency: json['currency'] as String,
        totalAmountMinor: json['total_amount_minor'] as int,
        version: json['version'] as int,
        message: json['message'] as String,
      );
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.status,
    required this.currency,
    required this.totalAmountMinor,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.failureCode,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final OrderStatus status;
  final String currency;
  final int totalAmountMinor;
  final int version;
  final String? failureCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        restaurantName: json['restaurant_name'] as String,
        status: OrderStatus.parse(json['status'] as String),
        currency: json['currency'] as String,
        totalAmountMinor: json['total_amount_minor'] as int,
        version: json['version'] as int,
        failureCode: json['failure_code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class OrderLine {
  const OrderLine({
    required this.menuItemId,
    required this.itemName,
    required this.priceAmountMinor,
    required this.currency,
    required this.quantity,
    required this.lineTotalMinor,
  });

  final String menuItemId;
  final String itemName;
  final int priceAmountMinor;
  final String currency;
  final int quantity;
  final int lineTotalMinor;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        menuItemId: json['menu_item_id'] as String,
        itemName: json['item_name'] as String,
        priceAmountMinor: json['price_amount_minor'] as int,
        currency: json['currency'] as String,
        quantity: json['quantity'] as int,
        lineTotalMinor: json['line_total_minor'] as int,
      );
}

class OrderDetail extends OrderSummary {
  const OrderDetail({
    required super.id,
    required super.restaurantId,
    required super.restaurantName,
    required super.status,
    required super.currency,
    required super.totalAmountMinor,
    required super.version,
    required super.createdAt,
    required super.updatedAt,
    super.failureCode,
    required this.deliveryAddress,
    required this.items,
    this.failureReason,
    this.driverId,
  });

  final String deliveryAddress;
  final String? failureReason;
  final String? driverId;
  final List<OrderLine> items;

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final summary = OrderSummary.fromJson(json);
    return OrderDetail(
      id: summary.id,
      restaurantId: summary.restaurantId,
      restaurantName: summary.restaurantName,
      status: summary.status,
      currency: summary.currency,
      totalAmountMinor: summary.totalAmountMinor,
      version: summary.version,
      failureCode: summary.failureCode,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      deliveryAddress: json['delivery_address'] as String,
      failureReason: json['failure_reason'] as String?,
      driverId: json['driver_id'] as String?,
      items: (json['items'] as List<dynamic>)
          .map((raw) => OrderLine.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OrderHistoryEntry {
  const OrderHistoryEntry({
    required this.version,
    required this.status,
    required this.source,
    required this.changedAt,
    this.fromStatus,
    this.failureCode,
  });

  final int version;
  final OrderStatus status;
  final OrderStatus? fromStatus;
  final String? failureCode;

  /// Machine source that produced the transition ("checkout", "payment
  /// worker", ...). Presentation only.
  final String source;
  final DateTime changedAt;

  factory OrderHistoryEntry.fromJson(Map<String, dynamic> json) => OrderHistoryEntry(
        version: json['version'] as int,
        status: OrderStatus.parse(json['status'] as String),
        fromStatus: json['from_status'] == null
            ? null
            : OrderStatus.parse(json['from_status'] as String),
        failureCode: json['failure_code'] as String?,
        source: json['source'] as String,
        changedAt: DateTime.parse(json['changed_at'] as String),
      );
}
