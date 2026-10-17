/// Compile-time API base URL configuration (assignment §7).
///
/// The ONLY place the backend address is decided, injected once at build
/// time:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
///
/// Defaults to the host-loopback address that works for Android emulator
/// targets and Linux desktop runs; browser builds must pass an explicit
/// host-reachable URL (docs/platforms.md). Never contains secrets — only a
/// public HTTP address.
library;

abstract final class AppConfig {
  /// Base URL including the /api/v1 prefix, no trailing slash.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Single request timeout for every API call (assignment: timeout + safe
  /// recovery). Checkout treats a timeout as an UNCERTAIN outcome and keeps
  /// the idempotency key (see checkout_controller.dart).
  static const Duration apiTimeout = Duration(seconds: 15);

  static void validate() {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      throw StateError(
        'Invalid API_BASE_URL "$apiBaseUrl". Pass a full absolute URL, e.g. '
        '--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1',
      );
    }
  }
}
