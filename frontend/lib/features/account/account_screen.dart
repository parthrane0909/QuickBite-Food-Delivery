/// Account tab (new in the UI rehaul) — the signed-in user's identity and
/// session controls in one honest place.
///
/// * name / email / role come from the server session (`GET /me` payload);
///   nothing here is fabricated
/// * quick links back to the two customer tabs
/// * the labelled **Sign out** action (same confirm flow as the rail button)
///
/// Responsive: single centered column, max-width on desktop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dto/auth_dto.dart';
import '../../state/auth_controller.dart';
import '../../ui/motion/entrance.dart';
import '../shell/app_shell.dart' show confirmSignOut;

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth.session?.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Entrance(index: 0, child: _IdentityCard(user: user)),
              const SizedBox(height: AppSpacing.xl),
              Entrance(
                index: 1,
                child: _TabLink(
                  icon: Icons.restaurant_rounded,
                  title: 'Restaurants',
                  subtitle: 'Browse the catalogue and order again',
                  onTap: () => context.go('/restaurants'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Entrance(
                index: 2,
                child: _TabLink(
                  icon: Icons.receipt_long_rounded,
                  title: 'Order history',
                  subtitle: 'Review and track your orders',
                  onTap: () => context.go('/orders'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Entrance(
                index: 3,
                child: SizedBox(
                  width: double.infinity,
                  height: AppSpacing.controlHeight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dangerTint,
                      foregroundColor: AppColors.danger,
                    ),
                    onPressed: () => confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  'Signed in on this device until you sign out.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final UserSummary? user;

  String get _initial {
    final name = user?.fullName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String get _roleLabel {
    final role = user?.role ?? 'customer';
    return role == 'admin' ? 'Administrator' : 'Customer';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = user?.role == 'admin';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initial,
              style: const TextStyle(
                color: AppColors.onPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName.isNotEmpty == true
                      ? user!.fullName
                      : 'QuickBite user',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isAdmin ? AppColors.infoTint : AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    _roleLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isAdmin ? AppColors.info : AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLink extends StatelessWidget {
  const _TabLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            boxShadow: AppShadow.card,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
