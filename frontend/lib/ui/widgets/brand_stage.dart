import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../motion/entrance.dart';

/// Original radial shapes, never extracted from the third-party reference.
class BrandStage extends StatelessWidget {
  const BrandStage({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: ColoredBox(
      color: AppColors.brandRed,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(child: CustomPaint(painter: _Rays())),
          ),
          child,
        ],
      ),
    ),
  );
}

class _Rays extends CustomPainter {
  const _Rays();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .52);
    final radius = size.longestSide * 1.5;
    final paint = Paint()
      ..color = const Color(0xFFFF4930).withValues(alpha: .38);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        )
        ..lineTo(
          center.dx + math.cos(angle + .17) * radius,
          center.dy + math.sin(angle + .17) * radius,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Rays oldDelegate) => false;
}

class BurgerHero extends StatelessWidget {
  const BurgerHero({super.key});
  @override
  Widget build(BuildContext context) => Entrance(
    index: 1,
    travel: 8,
    duration: AppMotion.hero,
    child: Image.asset(
      'assets/food/hero_burger.png',
      fit: BoxFit.contain,
      cacheWidth: 1200,
      semanticLabel: 'A cheeseburger with fresh lettuce',
      errorBuilder: (_, _, _) =>
          const Icon(Icons.fastfood_rounded, size: 100, color: Colors.white),
    ),
  );
}
