import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appThemeModeKey = 'innotrik.app-theme-mode.v1';

class AppThemeModeStore {
  const AppThemeModeStore();

  Future<ThemeMode> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedValue = preferences.getString(_appThemeModeKey);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == storedValue,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_appThemeModeKey, mode.name);
  }
}
