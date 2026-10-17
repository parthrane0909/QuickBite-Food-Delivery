/// The authoritative order state machine, mirrored EXACTLY from the backend
/// contract (docs/api.md §Orders). Flutter never invents states — every
/// status shown comes from the server and parses into one of these values.
///
/// Successful terminal state for this assignment: DRIVER_ASSIGNED.
/// Failure terminals: PAYMENT_FAILED, FAILED. There is deliberately NO
/// DELIVERED state and no GPS tracking (assignment §5).
library;

enum OrderStatus {
  pending('PENDING'),
  paid('PAID'),
  confirmed('CONFIRMED'),
  driverAssigned('DRIVER_ASSIGNED'),
  paymentFailed('PAYMENT_FAILED'),
  failed('FAILED');

  const OrderStatus(this.apiValue);

  /// Value exchanged with the API (e.g. "DRIVER_ASSIGNED").
  final String apiValue;

  static const Set<String> _values = {
    'PENDING',
    'PAID',
    'CONFIRMED',
    'DRIVER_ASSIGNED',
    'PAYMENT_FAILED',
    'FAILED',
  };

  /// Strict parse: the server contract guarantees one of the six values;
  /// anything else is a contract violation and must fail loudly in debug.
  static OrderStatus parse(String raw) {
    if (!_values.contains(raw)) {
      throw FormatException('Unknown order status from server: "$raw"');
    }
    return values.firstWhere((status) => status.apiValue == raw);
  }

  /// No further transitions will occur (polling can stop).
  bool get isTerminal =>
      this == OrderStatus.driverAssigned ||
      this == OrderStatus.paymentFailed ||
      this == OrderStatus.failed;

  /// Business failure (payment or restaurant/delivery rejection).
  bool get isFailure => this == OrderStatus.paymentFailed || this == OrderStatus.failed;

  /// Assignment success end-state.
  bool get isSuccess => this == OrderStatus.driverAssigned;

  /// Human-readable label (display typography, not API text).
  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.paid => 'Paid',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.driverAssigned => 'Driver assigned',
        OrderStatus.paymentFailed => 'Payment failed',
        OrderStatus.failed => 'Failed',
      };
}
