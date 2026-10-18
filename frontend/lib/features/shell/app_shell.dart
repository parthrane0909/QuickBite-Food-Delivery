/// Responsive navigation shell: NavigationRail on wide viewports,
/// NavigationBar on phones — the SAME information architecture at every
/// size (assignment §8). Destinations are ROLE-AWARE:
///
///   customer: Home (discovery), Orders, Account
///   admin:    Admin overview (customer-only list actions are hidden)
///
/// Detail screens (menu/cart/checkout/tracking) are pushed on top of this
/// shell as full-screen routes with their own back navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;
import '../../state/auth_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const double wideBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(
      authControllerProvider.select((auth) => auth.isAdmin),
    );
    final destinations = _destinations(isAdmin: isAdmin);
    final index = _indexForShell(isAdmin: isAdmin);
    void navigate(int destination) {
      final cartDestination = isAdmin ? 2 : 1;
      if (destination == cartDestination) {
        context.push('/cart');
        return;
      }
      shell.goBranch(_branchFor(destination, isAdmin: isAdmin));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        if (wide) {
          return Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: navigate,
                extended: constraints.maxWidth >= 1280,
                minExtendedWidth: 200,
                backgroundColor: AppColors.surface,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primaryTint,
                        backgroundImage: AssetImage(
                          'assets/images/logo_mark.png',
                        ),
                      ),
                      if (constraints.maxWidth >= 1280) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'QuickBite',
                          style: AppTypography.wordmark(size: 15),
                        ),
                      ],
                    ],
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
        return Scaffold(
          body: shell,
          bottomNavigationBar: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: navigate,
                destinations: destinations,
              ),
            ),
          ),
        );
      },
    );
  }

  List<NavigationDestination> _destinations({required bool isAdmin}) => [
    if (isAdmin)
      const NavigationDestination(
        selectedIcon: Icon(Icons.insights_rounded),
        icon: Icon(Icons.insights_outlined),
        label: 'Admin',
      ),
    const NavigationDestination(
      selectedIcon: Icon(Icons.home_rounded),
      icon: Icon(Icons.home_outlined),
      label: 'Home',
    ),
    const NavigationDestination(
      icon: CircleAvatar(
        radius: 23,
        backgroundColor: AppColors.primary,
        child: Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 23),
      ),
      label: 'Cart',
    ),
    const NavigationDestination(
      selectedIcon: Icon(Icons.receipt_long_rounded),
      icon: Icon(Icons.receipt_long_outlined),
      label: 'Orders',
    ),
    const NavigationDestination(
      selectedIcon: Icon(Icons.person_rounded),
      icon: Icon(Icons.person_outline_rounded),
      label: 'Account',
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
    if (isAdmin) {
      return switch (shell.currentIndex) {
        2 => 0,
        1 => 3,
        3 => 4,
        _ => 1,
      };
    }
    return switch (shell.currentIndex) {
      1 => 2,
      3 => 3,
      _ => 0,
    };
  }

  /// Shell branch for a tapped destination.
  ///
  /// Branch table: 0 = /restaurants, 1 = /orders, 2 = /admin, 3 = /account.
  int _branchFor(int destinationIndex, {required bool isAdmin}) {
    if (isAdmin) {
      return switch (destinationIndex) {
        0 => 2,
        1 => 0,
        3 => 1,
        _ => 3,
      };
    }
    return switch (destinationIndex) {
      0 => 0,
      1 => 0,
      2 => 1,
      _ => 3,
    };
  }
}

/// Shared sign-out confirmation — used by the rail's [LogoutButton] and the
/// Account screen so the destructive action always asks first.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'You will need to sign in again to browse QuickBite.',
      ),
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
    // Route redirect reacts to the auth change (a protected path would land
    // on /login?next=…); an EXPLICIT sign-out should end on the signed-out
    // landing page instead — token-expiry 401s still land on the login
    // banner by design.
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go('/welcome');
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
        onPressed: () => confirmSignOut(context, ref),
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(label),
      onPressed: () => confirmSignOut(context, ref),
    );
  }
}
