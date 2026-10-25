import 'package:flutter/material.dart';

class AppThemeController {
  AppThemeController._privateConstructor();
  static final AppThemeController instance = AppThemeController._privateConstructor();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    if (themeMode.value != mode) {
      themeMode.value = mode;
    }
  }
}
