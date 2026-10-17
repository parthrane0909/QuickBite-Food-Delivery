/// Root widget: theme + navigation wiring.
///
/// The router is a Riverpod provider (role-aware redirects react to auth
/// state); MaterialApp.router consumes it via `ref.watch` so the widget tree
/// always holds the current GoRouter instance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class QuickBiteApp extends ConsumerWidget {
  const QuickBiteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppConfig.validate();
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'QuickBite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
