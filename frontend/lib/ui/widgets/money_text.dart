/// Styled money text — integer minor units in, formatted currency out.
/// Always displays the SERVER-provided currency (never a hardcoded one).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/money.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.minor, {
    super.key,
    required this.currency,
    this.style,
    this.semanticsLabel = true,
    this.overflow,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final bool semanticsLabel;

  /// Lets tight layouts (narrow screens) ellipsize instead of overflowing.
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final formatted = formatMinor(minor, currency);
    return Semantics(
      label: semanticsLabel ? 'Amount $formatted' : null,
      excludeSemantics: semanticsLabel,
      child: Text(
        formatted,
        overflow: overflow,
        style: style ??
            const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.ink,
            ),
      ),
    );
  }
}
