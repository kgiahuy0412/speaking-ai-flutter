import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'mascot_assets.dart';

const learningSceneryAsset = MascotAssets.scenery;

/// Shared visual frame for the communication and listening journeys.
///
/// The image stays fixed while each screen keeps its own scrolling and state.
class LearningScenery extends StatelessWidget {
  const LearningScenery({
    required this.child,
    this.assetPath = learningSceneryAsset,
    this.imageAlignment = Alignment.topCenter,
    this.overlayOpacity = 0.08,
    super.key,
  });

  final Widget child;
  final String assetPath;
  final Alignment imageAlignment;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: imageAlignment,
          filterQuality: FilterQuality.high,
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  if (isDark)
                    AppColors.darkCanvas.withValues(alpha: 0.82)
                  else
                    Colors.white.withValues(alpha: overlayOpacity),
                  if (isDark)
                    AppColors.darkSurface.withValues(alpha: 0.76)
                  else
                    Colors.white.withValues(alpha: overlayOpacity * 0.55),
                  if (isDark)
                    AppColors.darkCanvas.withValues(alpha: 0.92)
                  else
                    Colors.white.withValues(alpha: overlayOpacity * 0.35),
                ],
                stops: const <double>[0, 0.48, 1],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

BoxDecoration scenicPanelDecoration({
  double radius = 28,
  Color color = const Color(0xFAFFFEFD),
  Color borderColor = AppColors.mintBorder,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: 1.4),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: AppColors.primaryNavy.withValues(alpha: 0.09),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
