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

  // Futuristic Palette
  static const Color neonBlue = Color(0xFF00F2FF);
  static const Color neonPurple = Color(0xFFBC00FF);
  static const Color neonPink = Color(0xFFFF00E5);
  static const Color darkBg = Color(0xFF030303);
  static const Color cardBgDark = Color(0xFF0D0D0D);

  ThemeData get currentTheme {
    return isDarkMode ? darkTheme : lightTheme;
  }

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        primaryColor: neonBlue,
        colorScheme: const ColorScheme.dark(
          primary: neonBlue,
          secondary: neonPurple,
          surface: cardBgDark,
        ),
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.blueAccent,
        colorScheme: ColorScheme.light(
          primary: Colors.blueAccent,
          secondary: Colors.deepPurpleAccent,
          surface: Colors.grey.shade100,
        ),
      );

  ThemeMode get themeMode {
    if (_useSystemTheme) return ThemeMode.system;
    return _themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }
}
