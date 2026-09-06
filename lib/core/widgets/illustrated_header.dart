import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The visual anchor at the top of onboarding steps.
///
/// Drawn from shapes and an icon rather than shipped as artwork: it stays
/// sharp at every screen density, recolours itself for light and dark
/// instead of needing two sets of files, and adds nothing to the download
/// size — which matters when the release build is barely 21 MB. If you
/// later commission real illustrations, this is the one widget to swap.
class IllustratedHeader extends StatelessWidget {
  const IllustratedHeader({
    super.key,
    required this.icon,
    this.size = 116,
    this.accent,
  });

  final IconData icon;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.seed;

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Offset blobs give the composition some asymmetry, so it reads
          // as a considered graphic rather than an icon in a circle.
          Positioned(
            top: size * 0.06,
            right: size * 0.08,
            child: _blob(size * 0.30, tint.withValues(alpha: 0.20)),
          ),
          Positioned(
            bottom: size * 0.10,
            left: size * 0.04,
            child: _blob(size * 0.22, AppColors.accent.withValues(alpha: 0.24)),
          ),
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint, AppColors.seedDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.seedDark.withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, size: size * 0.30, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _blob(double d, Color color) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
