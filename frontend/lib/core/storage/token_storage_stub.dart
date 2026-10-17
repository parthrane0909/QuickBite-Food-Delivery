/// Fallback platform implementation (never selected when either
/// dart.library.io or dart.library.js_interop is available).
library;

import 'token_storage.dart';

TokenStorage createTokenStorage() => InMemoryTokenStorage();
