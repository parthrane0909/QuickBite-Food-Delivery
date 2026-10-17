/// Infrastructure wiring: the single place where storage, networking and
/// repositories are constructed and handed to controllers. Screens never
/// create clients or repositories — they reach state through Riverpod.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../data/dto/auth_dto.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/order_repository.dart';
import 'auth_controller.dart';

/// Mutable holder of the live session — bridges auth state and networking
/// without a provider cycle (ApiClient reads the token through this).
class SessionStore {
  Session? current;
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage.platform(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final client = ApiClient(
    tokenProvider: () async => store.current?.accessToken,
    // Registered lazily (read at 401-time, not build-time) to avoid a
    // construction cycle with authControllerProvider.
    onUnauthorized: () => ref.read(authControllerProvider.notifier).handleUnauthorized(),
  );
  ref.onDispose(client.close);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);
