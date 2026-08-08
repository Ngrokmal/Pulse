enum AppThemeModePref { system, light, dark }

AppThemeModePref appThemeModePrefFromString(String? value) {
  switch (value) {
    case 'light':
      return AppThemeModePref.light;
    case 'dark':
      return AppThemeModePref.dark;
    default:
      return AppThemeModePref.system;
  }
}

String appThemeModePrefToString(AppThemeModePref value) {
  switch (value) {
    case AppThemeModePref.light:
      return 'light';
    case AppThemeModePref.dark:
      return 'dark';
    case AppThemeModePref.system:
      return 'system';
  }
}
