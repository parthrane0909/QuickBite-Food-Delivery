/// Persisted in-app notification DTO (`GET /orders/{id}/notifications`).
/// The server's `message` is the authoritative readable text; the client
/// only maps `type` to an icon for presentation. Notification failures are
/// NEVER business-order failures (assignment §9).
library;

class NotificationEntry {
  const NotificationEntry({
    required this.id,
    required this.seq,
    required this.orderId,
    required this.type,
    required this.message,
    required this.createdAt,
    this.orderVersion,
  });

  final String id;
  final int seq;
  final String orderId;

  /// Event type that produced it, e.g. "order.created", "payment.failed".
  final String type;
  final String message;
  final int? orderVersion;
  final DateTime createdAt;

  bool get isFailure =>
      type == 'payment.failed' ||
      type == 'restaurant.rejected' ||
      type == 'notification.failed';

  factory NotificationEntry.fromJson(Map<String, dynamic> json) => NotificationEntry(
        id: json['id'] as String,
        seq: json['seq'] as int,
        orderId: json['order_id'] as String,
        type: json['type'] as String,
        message: json['message'] as String,
        orderVersion: json['order_version'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
