/// Typed API failures. Every error the UI can receive funnels into one of
/// these shapes so screens never parse raw HTTP/JSON themselves.
library;

/// Server or transport failure with the backend's error-envelope fields.
///
/// - Server errors carry the parsed `{code, message, details, request_id}`
///   envelope (docs/api.md).
/// - Transport failures use synthetic [code]s: `timeout` (no response within
///   [AppConfig.apiTimeout] — the outcome is UNCERTAIN, retrying with the
///   same idempotency key is safe) and `network_error` (connection refused/
///   DNS/offline — also uncertain for in-flight POSTs).
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
    this.requestId,
  });

  /// Machine-readable code: server envelope code or a transport synthetic.
  final String code;

  /// Human-readable explanation, safe to show in error states.
  final String message;

  /// HTTP status, or null when no response arrived (transport failure).
  final int? statusCode;

  final Map<String, dynamic>? details;

  /// Backend request id for support/debugging (never a secret).
  final String? requestId;

  bool get isTimeout => code == 'timeout';
  bool get isNetwork => code == 'network_error';

  /// No usable response — the request MAY or MAY NOT have been applied.
  bool get isUncertainOutcome => statusCode == null;

  /// The session is gone (missing/expired/invalid token).
  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}
