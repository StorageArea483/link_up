import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color primaryBlue = Color(
    0xFF6BB2FF,
  ); // Clean light blue, modern & friendly
  static const Color background = Color(
    0xFFF7F9FC,
  ); // Pale green/white background

  static const Color surface = Color(0xFFFFFFFF);
  static const Color iconBackground = Color(0xFFEAF2FF);
  static const Color divider = Color(0xFFE9EEF5);

  static const Color inputBorder = Color(0xFFDDE6F3);
  static const Color shadow = Color(0x14000000);
  static const Color onlineGreen = Color(0xFF34C759);
  static const Color offlineGrey = Color(0xFFB0B7C3);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A); // Nearly black
  static const Color textSecondary = Color(0xFF757575); // Grey
  static const Color textFooter = Color(0xFFAAAAAA); // Light Grey

  static const Color linkBlue = Color(0xFF2F80ED);

  // UI Colors
  static const Color white = Colors.white;
}

class AppTextStyles {
  static const TextStyle title = TextStyle(
    fontSize: 28, // Adjusted for visual match
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 1.2,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.linkBlue,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle footer = TextStyle(
    fontSize: 12,
    color: AppColors.textFooter,
    height: 1.5,
  );

  static const TextStyle footerLink = TextStyle(
    fontSize: 12,
    color: AppColors.textFooter,
    decoration: TextDecoration.underline,
    height: 1.5,
  );
}
