import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'themeMode'; // 'system', 'light', 'dark'
  static const String _systemThemeKey = 'useSystemTheme';
  late Box _settingsBox;
  
  bool _useSystemTheme = true; // Default: follow system
  String _themeMode = 'system'; // 'system', 'light', 'dark'
  bool _systemIsDark = true;

  bool get useSystemTheme => _useSystemTheme;
  bool get isDarkMode {
    if (_useSystemTheme) {
      return _systemIsDark;
    }
    return _themeMode == 'dark';
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    _settingsBox = await Hive.openBox('settings');
    _useSystemTheme = _settingsBox.get(_systemThemeKey, defaultValue: true);
    _themeMode = _settingsBox.get(_themeKey, defaultValue: 'system');
    notifyListeners();
  }

  /// Update system theme (called when system theme changes)
  void updateSystemTheme(bool isDark) {
    _systemIsDark = isDark;
    if (_useSystemTheme) {
      notifyListeners();
    }
  }

  /// Toggle between system theme and manual mode
  void toggleUseSystemTheme() {
    _useSystemTheme = !_useSystemTheme;
    _settingsBox.put(_systemThemeKey, _useSystemTheme);
    notifyListeners();
  }

  /// Manually set theme (only when not using system theme)
  void setTheme(String mode) {
    if (!_useSystemTheme) {
      _themeMode = mode; // 'light' or 'dark'
      _settingsBox.put(_themeKey, _themeMode);
      notifyListeners();
    }
  }

  ThemeMode get themeMode {
    if (_useSystemTheme) {
      return ThemeMode.system;
    }
    return _themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }
}
