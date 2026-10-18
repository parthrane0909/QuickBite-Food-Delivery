/// Route transition suite — deliberate page pushes instead of platform
/// defaults. Detail screens rise into place with a short fade+slide;
/// full-screen moments (welcome, acknowledgement) can opt into a calmer
/// crossfade. All durations come from [AppMotion].
///
/// Wired in `router.dart` via `pageBuilder` — the shell's tab switches keep
/// GoRouter's instant swap (tabs must never slide).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_colors.dart';

/// Push: content rises from below with a quick fade (the app's default).
CustomTransitionPage<T> fadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
  Offset begin = const Offset(0, 0.05),
  Duration duration = AppMotion.base,
}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: AppMotion.fast,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );

/// Calm crossfade for onboarding-style moments (no directional motion).
CustomTransitionPage<T> fadePage<T>({
  required LocalKey key,
  required Widget child,
  Duration duration = AppMotion.hero,
}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: AppMotion.base,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: AppMotion.easeOut,
          reverseCurve: AppMotion.easeOut,
        ),
        child: child,
      ),
    );

/// Rise-up presentation (item detail, filters) — feels like a sheet.
CustomTransitionPage<T> risePage<T>({
  required LocalKey key,
  required Widget child,
  Duration duration = AppMotion.slow,
}) =>
    CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: AppMotion.fast,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.easeOut,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
