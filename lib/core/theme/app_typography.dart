import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();
  static const TextStyle title = TextStyle(fontSize: 28.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 0.5);
  static const TextStyle body = TextStyle(fontSize: 14.0, color: AppColors.textSecondary);
  static const TextStyle button = TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary);
  static const TextStyle caption = TextStyle(fontSize: 13.0, color: AppColors.textSecondary);
}
