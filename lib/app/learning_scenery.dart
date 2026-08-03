import 'package:flutter/material.dart';

import 'mascot_assets.dart';

const learningSceneryAsset = MascotAssets.scenery;

/// Shared visual frame for the communication and listening journeys.
///
/// The image stays fixed while each screen keeps its own scrolling and state.
class LearningScenery extends StatelessWidget {
  const LearningScenery({
    required this.child,
    this.imageAlignment = Alignment.topCenter,
    this.overlayOpacity = 0.08,
    super.key,
  });

  final Widget child;
  final Alignment imageAlignment;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          learningSceneryAsset,
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
                  Colors.white.withValues(alpha: overlayOpacity),
                  Colors.transparent,
                  const Color(0xFFFFFDF7).withValues(alpha: 0.08),
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
  Color color = const Color(0xF7FFFDF8),
  Color borderColor = const Color(0x66FFFFFF),
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: 1.4),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x24142451),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
  );
}
