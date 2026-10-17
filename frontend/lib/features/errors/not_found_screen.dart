/// Simple unknown-route screen (GoRouter errorBuilder) with a way home.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 64, color: AppColors.primary),
              const SizedBox(height: AppSpacing.lg),
              Text("We couldn't find that page", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                location,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => context.go('/'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
                child: const Text('Back to QuickBite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
