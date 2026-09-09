import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark HOMI palette keeps primary reading combinations accessible', () {
    final theme = buildDarkAppTheme();
    final colors = theme.colorScheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.darkCanvas);
    expect(
      _contrast(colors.onSurface, colors.surface),
      greaterThanOrEqualTo(7),
    );
    expect(
      _contrast(colors.onSurfaceVariant, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(colors.onPrimary, colors.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(colors.onTertiaryContainer, colors.tertiaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
