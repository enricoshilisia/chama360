import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Frosted-glass card: blurred backdrop + translucent gradient + hairline
/// border. Use this instead of a plain Card wherever the "glassmorphic"
/// look is wanted (auth screens, stat tiles, sheets).
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 24,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark ? AppColors.darkGlassTint : AppColors.lightGlassTint;
    // Dark mode gets away with a faint white wash because it's translucent
    // white over a dark backdrop — real contrast either way. Light mode
    // doing the same thing is near-white over near-white: the card
    // disappears. So light mode instead leans toward a near-solid white
    // fill (still gently tinted top-to-bottom for the glass feel) with a
    // dark hairline border and a real shadow, the way a card should read.
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 1.2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [tint.withValues(alpha: 0.10), tint.withValues(alpha: 0.04)]
                  : [tint.withValues(alpha: 0.92), tint.withValues(alpha: 0.82)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Full-screen soft green gradient backdrop, swaps automatically with
/// light/dark brightness. Wrap screens that should feel "glassy" in this.
class GradientBackdrop extends StatelessWidget {
  const GradientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.darkGradient : AppColors.lightGradient;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
            ),
          ),
        ),
        // Soft decorative blobs for depth behind the glass panels.
        Positioned(
          top: -80,
          right: -60,
          child: _blob(context, 220, AppColors.seed.withValues(alpha: isDark ? 0.18 : 0.35)),
        ),
        Positioned(
          bottom: -100,
          left: -70,
          child: _blob(context, 260, AppColors.accent.withValues(alpha: isDark ? 0.12 : 0.22)),
        ),
        child,
      ],
    );
  }

  Widget _blob(BuildContext context, double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
