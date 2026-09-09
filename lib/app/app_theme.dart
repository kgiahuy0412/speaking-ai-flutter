import 'package:flutter/material.dart';

abstract final class AppColors {
  /// HOMI option 2 palette.
  ///
  /// Navy owns large actions and navigation. Pink is deliberately restricted
  /// to progress, selection and voice/recording emphasis. Mint and white carry
  /// the large surfaces so every feature keeps the same calm visual rhythm.
  static const primaryNavy = Color(0xFF0B2C66);
  static const deepNavy = Color(0xFF0F2257);
  static const softNavy = Color(0xFF7890AE);
  static const accentPink = Color(0xFFD90E5E);
  static const accentPinkSoft = Color(0xFFFFF0F5);
  static const mint = Color(0xFF16B995);
  static const mintSoft = Color(0xFFEBFCF6);
  static const mintWash = Color(0xFFF5FDFA);
  static const mintBorder = Color(0xFFD4F2E9);
  static const success = Color(0xFF129B68);
  static const successSoft = Color(0xFFEAF8F1);
  static const surface = Color(0xFFFFFEFD);
  static const muted = Color(0xFF68748A);

  /// Dark mode keeps option 2's navy, pink and mint identity without turning
  /// the children's illustrations fluorescent or placing them on pure black.
  static const darkCanvas = Color(0xFF07172F);
  static const darkSurface = Color(0xFF0B2146);
  static const darkSurfaceRaised = Color(0xFF123055);
  static const darkSurfaceStrong = Color(0xFF193B62);
  static const darkPrimary = Color(0xFFA9C7F5);
  static const darkPink = Color(0xFFFF79AA);
  static const darkMint = Color(0xFF71D8BE);
  static const darkText = Color(0xFFF7FBFF);
  static const darkMuted = Color(0xFFC2CEE0);
  static const darkOutline = Color(0xFF496383);

  // Compatibility aliases keep existing screens on the same semantic system.
  // New UI should prefer the role-based names above.
  static const ink = deepNavy;
  static const indigo = primaryNavy;
  static const indigoDark = deepNavy;
  static const periwinkle = softNavy;
  static const lavender = mintSoft;
  static const lavenderSoft = mintWash;
  static const lavenderBorder = mintBorder;
  static const coral = accentPink;
  static const coralSoft = accentPinkSoft;
  static const peach = Color(0xFFF28CB2);
}

ThemeData buildAppTheme() => _buildAppTheme(Brightness.light);

ThemeData buildDarkAppTheme() => _buildAppTheme(Brightness.dark);

ThemeData _buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final generatedColorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primaryNavy,
    brightness: brightness,
    surface: isDark ? AppColors.darkSurface : AppColors.surface,
  );
  final colorScheme = generatedColorScheme.copyWith(
    primary: isDark ? AppColors.darkPrimary : AppColors.primaryNavy,
    onPrimary: isDark ? const Color(0xFF071A3D) : Colors.white,
    primaryContainer: isDark ? const Color(0xFF173A70) : AppColors.primaryNavy,
    onPrimaryContainer: Colors.white,
    secondary: isDark ? AppColors.darkPink : AppColors.accentPink,
    secondaryContainer: isDark
        ? const Color(0xFF5B1231)
        : AppColors.accentPinkSoft,
    onSecondaryContainer: isDark
        ? const Color(0xFFFFD9E6)
        : AppColors.accentPink,
    tertiary: isDark ? AppColors.darkMint : AppColors.mint,
    tertiaryContainer: isDark ? const Color(0xFF124C42) : AppColors.mintSoft,
    onTertiaryContainer: isDark ? const Color(0xFFD4FFF3) : AppColors.deepNavy,
    error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFD92D20),
    onSurface: isDark ? AppColors.darkText : AppColors.deepNavy,
    onSurfaceVariant: isDark ? AppColors.darkMuted : AppColors.muted,
    outline: isDark ? AppColors.darkOutline : AppColors.mintBorder,
    outlineVariant: isDark ? const Color(0xFF2D486C) : AppColors.mintBorder,
    surfaceContainerLow: isDark
        ? const Color(0xFF0E294F)
        : const Color(0xFFFAFEFC),
    surfaceContainer: isDark ? AppColors.darkSurfaceRaised : AppColors.mintWash,
    surfaceContainerHighest: isDark
        ? AppColors.darkSurfaceStrong
        : AppColors.mintSoft,
  );
  final textColor = colorScheme.onSurface;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark ? AppColors.darkCanvas : AppColors.mintWash,
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
        backgroundColor: isDark ? colorScheme.primary : AppColors.primaryNavy,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : AppColors.softNavy,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.82),
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
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.primary,
      textColor: colorScheme.onSurface,
      subtitleTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? colorScheme.surfaceContainer : AppColors.mintWash,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.secondary, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? colorScheme.surfaceContainer
          : Colors.white.withValues(alpha: 0.84),
      selectedColor: isDark ? colorScheme.primaryContainer : AppColors.mintSoft,
      disabledColor: colorScheme.surfaceContainer.withValues(alpha: 0.6),
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: TextStyle(
        color: isDark ? colorScheme.onPrimaryContainer : AppColors.primaryNavy,
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w800,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.outlineVariant,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? (isDark ? colorScheme.secondary : AppColors.accentPink)
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: BorderSide(
        color: isDark ? colorScheme.outline : AppColors.softNavy,
        width: 1.7,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? (isDark ? colorScheme.secondary : AppColors.accentPink)
            : (isDark ? colorScheme.onSurfaceVariant : AppColors.deepNavy),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : colorScheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.success
            : colorScheme.surfaceContainerHighest,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: isDark
          ? colorScheme.surfaceContainerHighest
          : AppColors.mintSoft,
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : AppColors.mintSoft,
        foregroundColor: isDark ? colorScheme.primary : AppColors.primaryNavy,
        shape: const CircleBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      modalBackgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.secondary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
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
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
