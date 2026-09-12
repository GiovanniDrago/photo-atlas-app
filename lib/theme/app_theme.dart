import 'package:flutter/material.dart';

class AppThemeOption {
  final String id;
  final String name;
  final Color seedColor;
  final Brightness brightness;

  const AppThemeOption({
    required this.id,
    required this.name,
    required this.seedColor,
    required this.brightness,
  });
}

const List<AppThemeOption> appThemes = [
  AppThemeOption(
    id: 'atlas_light',
    name: 'Atlas Light',
    seedColor: Color(0xFF00696B),
    brightness: Brightness.light,
  ),
  AppThemeOption(
    id: 'ocean_light',
    name: 'Ocean Light',
    seedColor: Color(0xFF2A5C8A),
    brightness: Brightness.light,
  ),
  AppThemeOption(
    id: 'atlas_dark',
    name: 'Atlas Dark',
    seedColor: Color(0xFF4DD8DA),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    id: 'forest_dark',
    name: 'Forest Dark',
    seedColor: Color(0xFF7BD08A),
    brightness: Brightness.dark,
  ),
];

AppThemeOption appThemeById(String id) {
  return appThemes.firstWhere(
    (theme) => theme.id == id,
    orElse: () => appThemes.first,
  );
}

ThemeData buildAppTheme(AppThemeOption option) {
  final scheme = ColorScheme.fromSeed(
    seedColor: option.seedColor,
    brightness: option.brightness,
  );
  final isDark = option.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
    ),
    cardTheme: CardThemeData(
      elevation: isDark ? 1 : 2,
      color: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.secondaryContainer,
      backgroundColor: scheme.surfaceContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
    ),
  );
}
