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

ThemeData buildAppTheme() => _buildAppTheme(Brightness.light);

ThemeData buildDarkAppTheme() => _buildAppTheme(Brightness.dark);

ThemeData _buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final generatedColorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.indigo,
    brightness: brightness,
    surface: isDark ? const Color(0xFF171F3B) : AppColors.surface,
  );
  final colorScheme = generatedColorScheme.copyWith(
    primary: isDark ? const Color(0xFFAEB5FF) : AppColors.indigo,
    onPrimary: isDark ? const Color(0xFF17205A) : Colors.white,
    secondary: isDark ? const Color(0xFFFFA99E) : AppColors.coral,
    error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFD92D20),
    onSurface: isDark ? const Color(0xFFF4F5FF) : AppColors.ink,
    outline: isDark ? const Color(0xFF596184) : AppColors.lavenderBorder,
    surfaceContainer: isDark
        ? const Color(0xFF20294B)
        : generatedColorScheme.surfaceContainer,
    surfaceContainerHighest: isDark
        ? const Color(0xFF2B355A)
        : generatedColorScheme.surfaceContainerHighest,
  );
  final textColor = colorScheme.onSurface;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF0E1630)
        : AppColors.surface,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      displaySmall: TextStyle(
        color: textColor,
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontSize: 27,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: textColor,
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: textColor,
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: const TextStyle(
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
        side: BorderSide(color: colorScheme.outline),
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
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : AppColors.lavender,
        foregroundColor: isDark ? colorScheme.primary : AppColors.indigoDark,
        shape: const CircleBorder(),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      modalBackgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.surfaceContainer,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colorScheme.outline)),
      ),
    ),
  );
}
