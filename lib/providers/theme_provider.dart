import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class ThemeNotifier extends Notifier<AppThemeOption> {
  static const _key = 'theme_id';

  @override
  AppThemeOption build() {
    _load();
    return appThemes.first;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id != null) {
      state = appThemeById(id);
    }
  }

  Future<void> setTheme(String id) async {
    state = appThemeById(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, AppThemeOption>(
  ThemeNotifier.new,
);
