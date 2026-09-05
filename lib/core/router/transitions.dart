import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// One consistent transition for every full-screen push in the app: a
/// gentle slide-up-and-fade. Used via `pageBuilder:` instead of `builder:`
/// on GoRoute so navigating between screens feels like a single considered
/// system rather than the platform default per-route.
CustomTransitionPage<void> fadeThroughPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
