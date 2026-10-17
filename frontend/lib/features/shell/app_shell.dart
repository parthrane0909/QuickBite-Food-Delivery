/// Responsive navigation shell: NavigationRail on wide viewports,
/// NavigationBar on phones — the SAME information architecture at every
/// size (assignment §8). Destinations are ROLE-AWARE:
///
///   customer: Restaurants, Orders
///   admin:    Admin overview (customer-only list actions are hidden)
///
/// Detail screens (menu/cart/checkout/tracking) are pushed on top of this
/// shell as full-screen routes with their own back navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../state/auth_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const double wideBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider.select((auth) => auth.isAdmin));
    final destinations = _destinations(isAdmin: isAdmin);
    final index = _indexForShell(isAdmin: isAdmin);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        if (wide) {
          return Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (destination) =>
                    shell.goBranch(_branchFor(destination, isAdmin: isAdmin)),
                extended: constraints.maxWidth >= 1280,
                minExtendedWidth: 200,
                backgroundColor: AppColors.surface,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryTint,
                    backgroundImage: AssetImage('assets/images/logo_mark.png'),
                  ),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: LogoutButton(iconOnly: true),
                ),
                destinations: _railDestinations(isAdmin: isAdmin),
              ),
              const VerticalDivider(width: 1, color: AppColors.outlineSoft),
              Expanded(child: shell),
            ],
          );
        }
        // The admin branch has a single destination: a NavigationBar would
        // assert (it requires >= 2), and there is nothing to switch between.
        // The dashboard's own app bar carries the logout action when narrow.
        if (isAdmin) return Scaffold(body: shell);
        return Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (destination) =>
                shell.goBranch(_branchFor(destination, isAdmin: isAdmin)),
            destinations: destinations,
          ),
        );
      },
    );
  }

  List<NavigationDestination> _destinations({required bool isAdmin}) => isAdmin
      ? const [
          NavigationDestination(
            selectedIcon: Icon(Icons.insights_rounded),
            icon: Icon(Icons.insights_outlined),
            label: 'Overview',
          ),
        ]
      : const [
          NavigationDestination(
            selectedIcon: Icon(Icons.restaurant_rounded),
            icon: Icon(Icons.restaurant_outlined),
            label: 'Restaurants',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.receipt_long_rounded),
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
        ];

  /// Same IA as the bar, in the rail's destination type.
  List<NavigationRailDestination> _railDestinations({required bool isAdmin}) =>
      _destinations(isAdmin: isAdmin)
          .map(
            (destination) => NavigationRailDestination(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: Text(destination.label),
            ),
          )
          .toList();

  /// Destination index (role-relative) for the current shell branch.
  int _indexForShell({required bool isAdmin}) {
    if (isAdmin) return shell.currentIndex == 2 ? 0 : 0;
    return shell.currentIndex.clamp(0, 1);
  }

  int _branchFor(int destinationIndex, {required bool isAdmin}) {
    if (isAdmin) return 2;
    return destinationIndex; // customer branches are 0 and 1
  }
}

/// Logout action reused by narrow-layout app bars (the rail hosts it on wide).
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key, this.iconOnly = false});

  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = 'Sign out';
    if (iconOnly) {
      return IconButton(
        tooltip: label,
        icon: const Icon(Icons.logout_rounded),
        onPressed: () => _signOut(context, ref),
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(label),
      onPressed: () => _signOut(context, ref),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to browse QuickBite.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      if (!context.mounted) return;
      // Route redirect sends the user to /login once auth clears.
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}
