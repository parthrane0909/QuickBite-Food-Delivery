/// The signature coral pill button with a built-in loading state (design
/// reference: full-width rounded CTA). Every primary action in the app uses
/// this — consistent height, radius, disabled + busy semantics (assignment:
/// consistent buttons and loading states).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.leadingIcon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? leadingIcon;

  /// Width: full-bleed (default, per reference) or shrink-wrapped.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: expanded ? null : FilledButton.styleFrom(minimumSize: const Size(160, 54)),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.onPrimary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingIcon != null) ...[
                    Icon(leadingIcon, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}
