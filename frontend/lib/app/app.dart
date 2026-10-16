import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget: theme + navigation wiring.
class QuickBiteApp extends StatelessWidget {
  const QuickBiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppConfig.validate();
    return MaterialApp.router(
      title: 'QuickBite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
