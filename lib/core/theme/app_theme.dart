import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.backgroundBottom,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryAccent,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBackground,
        hintStyle: AppTypography.body,
        prefixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppTypography.button,
          minimumSize: const Size.fromHeight(54),
        ),
      ),
      // UI-polish pass (presentation-layer only): previously undefined —
      // chat/group screens already read Theme.of(context).textTheme.bodySmall
      // for the typing-indicator label and relied on Flutter's default dark
      // text theme. Defining it explicitly keeps that label visually
      // consistent with AppTypography instead of an unrelated default.
      textTheme: const TextTheme(
        bodySmall: AppTypography.caption,
        titleMedium: AppTypography.title,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: AppTypography.body.copyWith(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.input),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }

  static ThemeData get lightTheme {
    return darkTheme.copyWith(
      brightness: Brightness.light,
      colorScheme: darkTheme.colorScheme.copyWith(brightness: Brightness.light),
    );
  }
}
