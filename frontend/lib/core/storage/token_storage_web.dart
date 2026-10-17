/// Web token storage: IN-MEMORY ONLY by design (assignment §7). The token
/// survives in-tab navigation via GoRouter but not a page reload — the user
/// simply signs in again. Browser storage is intentionally NOT used for
/// credentials of any kind.
library;

import 'token_storage.dart';

TokenStorage createTokenStorage() => InMemoryTokenStorage();
