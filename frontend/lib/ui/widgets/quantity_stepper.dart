/// Peach quantity stepper from the design reference: [−] qty [+].
/// Accessible (semantic labels + value announcement), respects server bounds
/// (1..20): at 1 the minus control removes the line (handled by caller via
/// [onRemoveBelowMin]), at max the plus control disables.
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.min = 1,
    this.max = 20,
    this.dense = false,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final int min;
  final int max;

  /// Smaller footprint for dense rows (menu list).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final canAdd = quantity < max;
    final size = dense ? 30.0 : 36.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            size: size,
            semanticLabel: 'Decrease quantity',
            onPressed: onDecrement,
          ),
          Semantics(
            label: 'Quantity $quantity',
            liveRegion: true,
            child: SizedBox(
              width: dense ? 28 : 34,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 14 : 15,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            size: size,
            semanticLabel: 'Increase quantity',
            onPressed: canAdd ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.size,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      child: IconButton(
        onPressed: onPressed,
        iconSize: denseIcon,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: Size(size, size),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon),
      ),
    );
  }

  double get denseIcon => size * 0.62;
}
