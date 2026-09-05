import 'package:flutter/material.dart';

/// Light-green brand palette shared by both themes.
/// Keep every color decision in this file — screens should never
/// hardcode a Color(...).
class AppColors {
  AppColors._();

  // Brand — light green family
  static const seed = Color(0xFF7CC576); // primary light green
  static const seedDark = Color(0xFF4E9950);
  static const accent = Color(0xFFE8A93B); // savings gold, for balances/CTAs
  static const danger = Color(0xFFE5484D);
  static const warning = Color(0xFFF0A93A);
  static const success = Color(0xFF43A047);

  // Light theme surfaces
  static const lightBackground = Color(0xFFF3F8F3);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightGlassTint = Color(0xFFFFFFFF);

  // Dark theme surfaces
  static const darkBackground = Color(0xFF0E1512);
  static const darkSurface = Color(0xFF16201B);
  static const darkGlassTint = Color(0xFFFFFFFF);

  static const lightGradient = [
    Color(0xFFE7F5E6),
    Color(0xFFF6FBF3),
    Color(0xFFEFF6EC),
  ];

  static const darkGradient = [
    Color(0xFF0B1410),
    Color(0xFF11201A),
    Color(0xFF0D1A15),
  ];
}
