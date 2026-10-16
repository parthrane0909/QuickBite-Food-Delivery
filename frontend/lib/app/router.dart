import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Application router.
///
/// Milestone 1 provides the shell: a home route and a proper unknown-route
/// page. Feature routes (catalog, cart, checkout, tracking, admin) and
/// auth/admin redirects are added milestone-by-milestone.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'home',
      builder: (BuildContext context, GoRouterState state) =>
          const _HomePlaceholder(),
    ),
  ],
  errorBuilder: (BuildContext context, GoRouterState state) =>
      _NotFoundPage(path: state.uri.toString()),
);

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickBite')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'QuickBite',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Foundation scaffold — screens arrive with later milestones.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('No route for $path', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.goNamed('home'),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
