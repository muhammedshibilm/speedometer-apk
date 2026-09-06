import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'themeMode'; // 'system', 'light', 'dark'
  static const String _systemThemeKey = 'useSystemTheme';
  static const String _speedLimitKey = 'speedLimit';
  static const String _soundAlertKey = 'soundAlert';
  static const String _vibrationAlertKey = 'vibrationAlert';
  late Box _settingsBox;

  bool _useSystemTheme = true; // Default: follow system
  String _themeMode = 'system'; // 'system', 'light', 'dark'
  bool _systemIsDark = true;
  
  double _speedLimit = 80.0;
  bool _enableSoundAlert = true;
  bool _enableVibrationAlert = true;

  bool get useSystemTheme => _useSystemTheme;
  double get speedLimit => _speedLimit;
  bool get enableSoundAlert => _enableSoundAlert;
  bool get enableVibrationAlert => _enableVibrationAlert;
  
  String get alertMode {
    if (_enableSoundAlert && _enableVibrationAlert) return 'Both';
    if (_enableSoundAlert) return 'Sound Only';
    if (_enableVibrationAlert) return 'Vibration Only';
    return 'None';
  }
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
    _speedLimit = _settingsBox.get(_speedLimitKey, defaultValue: 80.0);
    _enableSoundAlert = _settingsBox.get(_soundAlertKey, defaultValue: true);
    _enableVibrationAlert = _settingsBox.get(_vibrationAlertKey, defaultValue: true);
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

  void setThemeModeString(String mode) {
    if (mode == 'system') {
      _useSystemTheme = true;
      _settingsBox.put(_systemThemeKey, true);
    } else {
      _useSystemTheme = false;
      _themeMode = mode;
      _settingsBox.put(_systemThemeKey, false);
      _settingsBox.put(_themeKey, mode);
    }
    notifyListeners();
  }

  void setSpeedLimit(double limit) {
    _speedLimit = limit;
    _settingsBox.put(_speedLimitKey, _speedLimit);
    notifyListeners();
  }

  void setSoundAlert(bool enabled) {
    _enableSoundAlert = enabled;
    _settingsBox.put(_soundAlertKey, _enableSoundAlert);
    notifyListeners();
  }

  void setVibrationAlert(bool enabled) {
    _enableVibrationAlert = enabled;
    _settingsBox.put(_vibrationAlertKey, _enableVibrationAlert);
    notifyListeners();
  }

  void setAlertMode(String mode) {
    switch (mode) {
      case 'Both':
        _enableSoundAlert = true;
        _enableVibrationAlert = true;
        break;
      case 'Sound Only':
        _enableSoundAlert = true;
        _enableVibrationAlert = false;
        break;
      case 'Vibration Only':
        _enableSoundAlert = false;
        _enableVibrationAlert = true;
        break;
      case 'None':
      default:
        _enableSoundAlert = false;
        _enableVibrationAlert = false;
        break;
    }
    _settingsBox.put(_soundAlertKey, _enableSoundAlert);
    _settingsBox.put(_vibrationAlertKey, _enableVibrationAlert);
    notifyListeners();
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
