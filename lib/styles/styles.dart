import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color primaryBlue = Color(
    0xFF6BB2FF,
  ); // Clean light blue, modern & friendly
  static const Color background = Color(
    0xFFF3F8F2,
  ); // Pale green/white background

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A); // Nearly black
  static const Color textSecondary = Color(0xFF757575); // Grey
  static const Color textFooter = Color(0xFFAAAAAA); // Light Grey

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

  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
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
