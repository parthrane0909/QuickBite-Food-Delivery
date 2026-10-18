import 'package:flutter/material.dart';

abstract final class AdaptiveLayout {
  static const desktop = 900.0;
  static const maxContent = 1160.0;
  static const gutter = 16.0;
  static const gap = 12.0;

  static int menuColumns(BuildContext context, double width) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    if (width < 350 || largeText) return width >= 700 ? 2 : 1;
    if (width >= 1050) return 4;
    if (width >= 700) return 3;
    return 2;
  }
}

class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AdaptiveLayout.maxContent,
  });
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
