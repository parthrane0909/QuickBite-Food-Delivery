/// Secure-token storage for IO platforms (Android, iOS, desktop) using
/// flutter_secure_storage: Android Keystore-backed encrypted storage,
/// iOS Keychain, macOS Keychain, Linux libsecret, Windows DPAPI.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

const String _tokenKey = 'quickbite.access_token';

TokenStorage createTokenStorage() => _SecureTokenStorage();

class _SecureTokenStorage implements TokenStorage {
  // Library defaults: platform-encrypted storage on every IO target
  // (EncryptedSharedPreferences on modern Android).
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) => _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
