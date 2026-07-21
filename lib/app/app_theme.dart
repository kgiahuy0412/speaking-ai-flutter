import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF142451);
  static const indigo = Color(0xFF3D4DD6);
  static const indigoDark = Color(0xFF27389D);
  static const periwinkle = Color(0xFF8A91EA);
  static const lavender = Color(0xFFF2F1FF);
  static const lavenderSoft = Color(0xFFF8F7FF);
  static const lavenderBorder = Color(0xFFE1E1FF);
  static const coral = Color(0xFFF36B5F);
  static const coralSoft = Color(0xFFFFF1EE);
  static const peach = Color(0xFFFFA489);
  static const success = Color(0xFF23A05A);
  static const successSoft = Color(0xFFF0FBF5);
  static const surface = Color(0xFFFFFDF9);
  static const muted = Color(0xFF66718C);
}

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.indigo,
        brightness: Brightness.light,
        surface: AppColors.surface,
      ).copyWith(
        primary: AppColors.indigo,
        onPrimary: Colors.white,
        secondary: AppColors.coral,
        error: const Color(0xFFD92D20),
        onSurface: AppColors.ink,
        outline: AppColors.lavenderBorder,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.ink,
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 27,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: AppColors.lavenderBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: AppColors.lavender,
        foregroundColor: AppColors.indigoDark,
        shape: const CircleBorder(),
      ),
    ),
  );
}
