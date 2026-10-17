/// Admin DTOs — verified against the Milestone 5 admin endpoints
/// (`GET /admin/orders`, `GET /admin/summary`). READ-ONLY surface: there
/// are no mutation endpoints by design.
library;

import '../../domain/order_status.dart';
import 'order_dto.dart';

class AdminOrderItem extends OrderSummary {
  const AdminOrderItem({
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
    required this.customerEmail,
  });

  /// Ordering customer's email — the only admin-only field.
  final String customerEmail;

  factory AdminOrderItem.fromJson(Map<String, dynamic> json) {
    final summary = OrderSummary.fromJson(json);
    return AdminOrderItem(
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
      customerEmail: json['customer_email'] as String,
    );
  }
}

class AdminSummary {
  const AdminSummary({
    required this.ordersByStatus,
    required this.pendingOutboxEvents,
    required this.retryBacklog,
    required this.quarantineRecords,
    required this.generatedAt,
  });

  /// Counts for every status key (0 included), straight from PostgreSQL.
  final Map<String, int> ordersByStatus;
  final int pendingOutboxEvents;
  final int retryBacklog;
  final int quarantineRecords;
  final DateTime generatedAt;

  int countFor(OrderStatus status) => ordersByStatus[status.apiValue] ?? 0;

  factory AdminSummary.fromJson(Map<String, dynamic> json) => AdminSummary(
        ordersByStatus: (json['orders_by_status'] as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value as int)),
        pendingOutboxEvents: json['pending_outbox_events'] as int,
        retryBacklog: json['retry_backlog'] as int,
        quarantineRecords: json['quarantine_records'] as int,
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}
