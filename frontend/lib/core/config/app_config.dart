/// Compile-time public configuration. No secrets are ever embedded here;
/// values are injected with `--dart-define=API_BASE_URL=...` at build time.
class AppConfig {
  AppConfig._();

  /// Public API base URL. Defaults to the local Compose backend so the app
  /// runs out of the box during development.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static bool get _looksLikeBaseUrl {
    final uri = Uri.tryParse(apiBaseUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Fails fast on boot if the injected base URL is malformed.
  static void validate() {
    if (!_looksLikeBaseUrl) {
      throw StateError(
        'Invalid API_BASE_URL "$apiBaseUrl": expected an absolute http(s) URL.',
      );
    }
  }
}
