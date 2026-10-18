/// SuccessBurst — the order-accepted confirmation moment: a spring-scaled
/// coral disc, a check path that draws itself, and one soft expanding ring.
/// Used on the acknowledgement screen (and reusable for any future
/// success moment). No confetti, no excess — one deliberate flourish.
///
/// Respects reduced-motion (renders the finished state instantly).
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class SuccessBurst extends StatefulWidget {
  const SuccessBurst({super.key, this.size = 108, this.color = AppColors.primary});

  final double size;
  final Color color;

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // Disc springs in first; check draws across the middle third; ring
    // expands and fades through the tail.
    final disc = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.4, curve: AppMotion.spring),
    );
    final check = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.7, curve: AppMotion.easeOut),
    );
    final ring = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: AppMotion.easeOut),
    );

    return Semantics(
      image: true,
      label: 'Success',
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Expanding halo ring.
                if (!_controller.isCompleted)
                  Transform.scale(
                    scale: 1 + 0.55 * ring.value,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.color.withValues(
                            alpha: 0.45 * (1 - ring.value),
                          ),
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                // Coral disc.
                Transform.scale(
                  scale: disc.value,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppShadow.cta,
                    ),
                  ),
                ),
                // Drawn check.
                CustomPaint(
                  size: Size(size * 0.5, size * 0.5),
                  painter: _CheckPainter(
                    progress: check.value,
                    color: AppColors.onPrimary,
                    strokeWidth: size * 0.075,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.84, size.height * 0.28);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;
    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
