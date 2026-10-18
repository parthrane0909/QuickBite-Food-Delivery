/// Entrance animations — content settles in instead of popping.
///
/// [Entrance] fades + slides a single child after a delay derived from its
/// list index ([StaggeredEntrance] convenience), giving grids and lists a
/// deliberate cascade. Motion is subtle by design (short travel, ease-out)
/// and fully disabled under `MediaQuery.disableAnimations` (reduced motion).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.step = AppMotion.staggerStep,
    this.travel = 14,
    this.duration = AppMotion.slow,
    this.curve = AppMotion.emphasized,
  });

  final Widget child;

  /// Position in a cascade; delay = index * step (capped at 600ms).
  final int index;
  final Duration step;
  final double travel;
  final Duration duration;
  final Curve curve;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited lookups (reduced-motion) are only legal here, not in
    // initState; guard so dependency changes never restart the cascade.
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    var delay = widget.step * widget.index;
    if (delay > const Duration(milliseconds: 600)) {
      delay = const Duration(milliseconds: 600);
    }
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.travel / 100),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Wraps children of a scrollable with individual [Entrance] cascades.
/// Children must be laid out by the caller (Column/GridView children.map).
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          Entrance(index: i, child: children[i]),
      ],
    );
  }
}

/// A one-shot fade for whole screens settling in (splash -> content).
class ScreenFade extends StatelessWidget {
  const ScreenFade({super.key, required this.child, this.duration = AppMotion.hero});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: child,
      ),
      child: child,
    );
  }
}

/// Convenience: primary-colored pulsing dot used in live status headers.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.color = AppColors.success, this.size = 8});

  final Color color;
  final double size;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
