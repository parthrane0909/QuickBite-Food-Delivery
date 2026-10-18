/// Application router (GoRouter 18): role-aware redirects, auth guard, and
/// responsive shell wiring.
///
/// Route map:
///   /                     -> splash (session restore) -> role home
///   /welcome              -> signed-out landing page
///   /login                -> sign-in
///   [shell branches]      /restaurants (0), /orders (1), /admin (2),
///                         /account (3) — customer tabs are Home/Orders/
///                         Account; admin uses branch 2 only
///   full-screen pushes    /menu/:id, /menu/:id/item/:itemId, /cart,
///                         /checkout, /orders/:id/accepted, /orders/:id
///
/// Auth redirects re-run whenever [authControllerProvider] changes (bridged
/// through a refresh [Listenable]), so sign-in, sign-out and server-side
/// token expiry navigate immediately — including stopping deep protected
/// polling (the target screen simply unmounts).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_screen.dart';
import '../features/account/image_credits_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/admin/admin_management_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/errors/not_found_screen.dart';
import '../features/menu/item_detail_screen.dart';
import '../features/menu/restaurant_menu_screen.dart';
import '../features/orders/order_ack_screen.dart';
import '../features/orders/order_history_screen.dart';
import '../features/orders/order_tracking_screen.dart';
import '../features/restaurants/restaurant_list_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../state/auth_controller.dart';
import '../data/dto/catalog_dto.dart';
import 'transitions.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

String? _redirect(Ref ref, GoRouterState state) {
  final auth = ref.read(authControllerProvider);
  final path = state.matchedLocation;

  // Do not mount protected API consumers before session restoration finishes.
  // A cold browser deep link must retain its destination through sign-in.
  if (auth.phase == AuthPhase.restoring) {
    if (path == '/' || path == '/welcome' || path == '/login') return null;
    return '/?next=${Uri.encodeComponent(state.uri.toString())}';
  }

  if (!auth.isSignedIn) {
    if (path == '/login') return null;
    if (path == '/welcome') return null; // signed-out landing page
    if (path == '/' || path.isEmpty) {
      final next = state.uri.queryParameters['next'];
      return next == null
          ? '/welcome'
          : '/login?next=${Uri.encodeComponent(next)}';
    }
    // Deep links skip the landing page and go straight to sign-in with a
    // return target (preserved ?next= behaviour).
    return '/login?next=${Uri.encodeComponent(path)}';
  }

  // Signed in.
  if (path == '/' || path.isEmpty) {
    final next = state.uri.queryParameters['next'];
    if (next != null && next.startsWith('/') && !next.startsWith('//')) {
      return next;
    }
    return auth.isAdmin ? '/admin' : '/restaurants';
  }
  if (path == '/welcome') return auth.isAdmin ? '/admin' : '/restaurants';
  if (path == '/login') {
    final next = state.uri.queryParameters['next'];
    if (next != null && next.startsWith('/') && !next.startsWith('//')) {
      return next;
    }
    return auth.isAdmin ? '/admin' : '/restaurants';
  }
  if (path.startsWith('/admin') && !auth.isAdmin) return '/restaurants';
  // Admin tokens may shop as their own identity. The order API scopes every
  // read and checkout to this token subject; management remains admin-guarded.
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Menu/item/cart pushes must expose a reloadable browser destination.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    errorBuilder: (context, state) =>
        NotFoundScreen(location: state.matchedLocation),
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) =>
            fadePage<void>(key: state.pageKey, child: const WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            fadePage<void>(key: state.pageKey, child: const LoginScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/restaurants',
                builder: (context, state) => const RestaurantListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                builder: (context, state) => const OrderHistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/admin/restaurants',
        builder: (context, state) =>
            const AdminManagementScreen(section: AdminSection.restaurants),
      ),
      GoRoute(
        path: '/admin/restaurants/:id/menu',
        builder: (context, state) => AdminManagementScreen(
          section: AdminSection.menu,
          restaurantId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/admin/customers',
        builder: (context, state) =>
            const AdminManagementScreen(section: AdminSection.customers),
      ),
      GoRoute(
        path: '/admin/drivers',
        builder: (context, state) =>
            const AdminManagementScreen(section: AdminSection.drivers),
      ),
      GoRoute(
        path: '/admin/orders/:id',
        builder: (context, state) =>
            AdminOrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/image-credits',
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          child: const ImageCreditsScreen(),
        ),
      ),
      GoRoute(
        path: '/menu/:id/item/:itemId',
        pageBuilder: (context, state) => risePage<void>(
          key: state.pageKey,
          child: ItemDetailScreen(
            restaurantId: state.pathParameters['id']!,
            itemId: state.pathParameters['itemId']!,
            restaurant: state.extra is Restaurant
                ? state.extra as Restaurant
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/menu/:id',
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          child: RestaurantMenuScreen(
            restaurantId: state.pathParameters['id']!,
            restaurant: state.extra is Restaurant
                ? state.extra as Restaurant
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/cart',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, child: const CartScreen()),
      ),
      GoRoute(
        path: '/checkout',
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          child: const CheckoutScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/:id/accepted',
        pageBuilder: (context, state) => fadePage<void>(
          key: state.pageKey,
          child: OrderAckScreen(orderId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/orders/:id',
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          child: OrderTrackingScreen(orderId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
});
