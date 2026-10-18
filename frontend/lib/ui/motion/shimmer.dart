/// Shimmer skeletons — hand-rolled (no extra packages) with a warm-tinted
/// base and a soft white sweep. [Shimmer] wraps any subtree of skeleton
/// primitives; every screen's loading state uses these instead of a bare
/// spinner, so content-shaped placeholders appear where data will land.
///
/// Respects `MediaQuery.disableAnimations` (reduced motion -> static).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  static const _base = Color(0xFFEDE4DB); // warm skeleton grey
  static const _highlight = Color(0xFFFDF9F4);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.5;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (-1.0 + 2.4 * _controller.value);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [_base, _highlight, _base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A plain skeleton block — grey rounded rectangle tinted by [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppSpacing.radiusSm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE4DB),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Circular skeleton (avatars, icon wells).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: AppSpacing.radiusPill);
}

/// Image-shaped skeleton (cards, heroes).
class SkeletonImage extends SkeletonBox {
  const SkeletonImage({
    super.key,
    super.width,
    super.height = 160,
    super.radius = AppSpacing.radiusLg,
  });
}

/// Restaurant-card-shaped skeleton for the discovery grid.
class SkeletonRestaurantCard extends StatelessWidget {
  const SkeletonRestaurantCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonBox(height: 128, radius: AppSpacing.radiusLg),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(width: 148, height: 15),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: 210, height: 12),
      ],
    );
  }
}

/// Menu-tile-shaped skeleton (image, title, price).
class SkeletonDishTile extends StatelessWidget {
  const SkeletonDishTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonBox(height: 118, radius: AppSpacing.radiusLg),
        SizedBox(height: AppSpacing.sm + 2),
        SkeletonBox(width: 120, height: 13),
        SizedBox(height: AppSpacing.xs + 2),
        SkeletonBox(width: 72, height: 12),
      ],
    );
  }
}

/// List-row skeleton (order history, notifications, admin orders).
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key, this.leading = 56});

  final double leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: leading, height: leading, radius: AppSpacing.radiusMd),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 180, height: 14),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 240, height: 12),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 96, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
