/// Bearer-token persistence abstraction (assignment: platform-compatible
/// storage; mobile = secure storage, web = in-memory).
///
/// Web deliberately keeps tokens in MEMORY ONLY: requiring sign-in again
/// after a reload is acceptable per the assignment, and browser storage
/// must not be presented as mobile-grade secure storage. Passwords are
/// never stored anywhere.
library;

import 'token_storage_stub.dart'
    if (dart.library.js_interop) 'token_storage_web.dart'
    if (dart.library.io) 'token_storage_io.dart' as impl;

abstract class TokenStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();

  /// Platform implementation: secure storage on IO platforms (Android/iOS/
  /// desktop), in-memory on web.
  factory TokenStorage.platform() => impl.createTokenStorage();
}

/// Test/preview double — pure memory, identical on every platform.
class InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}
