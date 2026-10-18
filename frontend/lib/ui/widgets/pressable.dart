/// Pressable — the shared interaction wrapper for every card/tile.
///
/// * mobile: press scales the card down slightly (tactile "button" feel)
/// * web: hover raises the card with a soft warm shadow, focus shows ring,
///   press scales like touch
/// * keyboard: Space/Enter activate when focused (via GestureDetector +
///   Semantics focus; Material's button semantics for buttons stay native)
///
/// Cards across the app wrap their content in this instead of hand-rolling
/// gesture/hover logic (single source of interaction truth).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.975,
    this.radius = AppSpacing.radiusLg,
    this.hoverShadow = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final double radius;

  /// Lift with [AppShadow.card] on pointer hover (web/desktop).
  final bool hoverShadow;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final lift = _hovered && _active && widget.hoverShadow && !_pressed;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return MouseRegion(
      cursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableActionDetector(
        enabled: _active,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_active) widget.onTap!();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _active ? widget.onTap : null,
          onLongPress: _active ? widget.onLongPress : null,
          onTapDown: _active && !reduce
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : AppMotion.fast,
            curve: AppMotion.easeOut,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: _focused
                  ? Border.all(color: AppColors.primary, width: 3)
                  : null,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: lift ? AppShadow.card : const [],
            ),
            child: AnimatedScale(
              scale: _pressed ? widget.scale : 1,
              duration: reduce ? Duration.zero : AppMotion.instant,
              curve: AppMotion.easeOut,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
