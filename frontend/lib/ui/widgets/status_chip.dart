/// Order status chip — server status -> accessible colored badge.
/// Failure states read as failure even in grayscale (icon + text, not color
/// alone), and the label comes from the domain enum (never invented text).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../domain/order_status.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.compact = false});

  final OrderStatus status;
  final bool compact;

  Color get _background => switch (status) {
        OrderStatus.pending => AppColors.warningTint,
        OrderStatus.paid => AppColors.successTint,
        OrderStatus.confirmed => AppColors.infoTint,
        OrderStatus.driverAssigned => AppColors.successTint,
        OrderStatus.paymentFailed => AppColors.dangerTint,
        OrderStatus.failed => AppColors.dangerTint,
      };

  Color get _foreground => switch (status) {
        OrderStatus.pending => AppColors.warning,
        OrderStatus.paid => AppColors.success,
        OrderStatus.confirmed => AppColors.info,
        OrderStatus.driverAssigned => AppColors.success,
        OrderStatus.paymentFailed => AppColors.danger,
        OrderStatus.failed => AppColors.danger,
      };

  IconData get _icon => switch (status) {
        OrderStatus.pending => Icons.hourglass_top_rounded,
        OrderStatus.paid => Icons.payments_rounded,
        OrderStatus.confirmed => Icons.task_alt_rounded,
        OrderStatus.driverAssigned => Icons.two_wheeler_rounded,
        OrderStatus.paymentFailed => Icons.credit_card_off_rounded,
        OrderStatus.failed => Icons.cancel_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: _foreground,
      fontWeight: FontWeight.w700,
      fontSize: compact ? 11.5 : 13,
    );
    return Semantics(
      label: 'Order status: ${status.label}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: _foreground.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: compact ? 13 : 15, color: _foreground),
            SizedBox(width: compact ? 4 : 6),
            Text(status.label, style: labelStyle),
          ],
        ),
      ),
    );
  }
}
