/// Thin info/warning banner used for global messages: session expired,
/// pending checkout attempt, offline notes. Non-dismissable by default —
/// these carry state the user must see.
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum AppBannerKind { info, warning, danger, success }

class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.kind = AppBannerKind.info,
    this.icon,
    this.onAction,
    this.actionLabel,
  });

  final String message;
  final AppBannerKind kind;
  final IconData? icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  ({Color background, Color foreground}) get _palette => switch (kind) {
        AppBannerKind.info => (background: AppColors.infoTint, foreground: AppColors.info),
        AppBannerKind.warning => (
            background: AppColors.warningTint,
            foreground: AppColors.warning
          ),
        AppBannerKind.danger => (background: AppColors.dangerTint, foreground: AppColors.danger),
        AppBannerKind.success => (
            background: AppColors.successTint,
            foreground: AppColors.success
          ),
      };

  IconData get _icon => icon ?? switch (kind) {
        AppBannerKind.info => Icons.info_outline_rounded,
        AppBannerKind.warning => Icons.warning_amber_rounded,
        AppBannerKind.danger => Icons.error_outline_rounded,
        AppBannerKind.success => Icons.check_circle_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return Semantics(
      container: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: palette.foreground.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 20, color: palette.foreground),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: palette.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: palette.foreground,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
