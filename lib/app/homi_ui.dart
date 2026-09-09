import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shared visual language for HOMI's native Android and iOS surfaces.
///
/// These widgets intentionally keep the interface light: one soft surface per
/// section, consistent icon badges, compact status pills and a reusable voice
/// waveform instead of one-off card styling in every feature.
abstract final class HomiUi {
  static const pagePadding = EdgeInsets.symmetric(horizontal: 20);
  static const sectionGap = 24.0;
  static const itemGap = 12.0;
  static const surfaceRadius = 24.0;
  static const controlRadius = 18.0;
}

class HomiSurface extends StatelessWidget {
  const HomiSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.constraints,
    this.color,
    this.borderColor,
    this.radius = HomiUi.surfaceRadius,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BoxConstraints? constraints;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedColor =
        color ??
        (isDark
            ? theme.colorScheme.surfaceContainer
            : AppColors.surface.withValues(alpha: 0.97));
    final resolvedBorder =
        borderColor ??
        (isDark ? theme.colorScheme.outlineVariant : Colors.transparent);
    return Container(
      width: double.infinity,
      margin: margin,
      constraints: constraints,
      child: Material(
        color: resolvedColor,
        elevation: elevated ? 1 : 0,
        shadowColor: AppColors.primaryNavy.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: resolvedBorder),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class HomiSectionHeading extends StatelessWidget {
  const HomiSectionHeading({
    required this.title,
    this.icon,
    this.trailing,
    super.key,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stackTrailing =
            trailing != null &&
            (constraints.maxWidth < 300 || textScale >= 1.5);
        final heading = Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              HomiIconBadge(icon: icon!, size: 40, iconSize: 22),
              const SizedBox(width: 11),
            ],
            Expanded(child: titleWidget),
          ],
        );

        if (stackTrailing) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: heading),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}

class HomiIconBadge extends StatelessWidget {
  const HomiIconBadge({
    required this.icon,
    this.foregroundColor,
    this.backgroundColor,
    this.size = 44,
    this.iconSize = 24,
    super.key,
  });

  final IconData icon;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _darkAccent(
      theme,
      foregroundColor ?? theme.colorScheme.primary,
    );
    final background =
        backgroundColor ??
        (theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest
            : AppColors.lavender);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: foreground, size: iconSize),
    );
  }
}

class HomiStatusPill extends StatelessWidget {
  const HomiStatusPill({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = _darkAccent(theme, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: resolvedColor, size: 15),
            const SizedBox(width: 5),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: resolvedColor,
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _darkAccent(ThemeData theme, Color color) {
  if (theme.brightness != Brightness.dark) return color;
  if (color == AppColors.success || color == AppColors.mint) {
    return theme.colorScheme.tertiary;
  }
  if (color == AppColors.coral || color == AppColors.accentPink) {
    return theme.colorScheme.secondary;
  }
  if (color == AppColors.indigo || color == AppColors.primaryNavy) {
    return theme.colorScheme.primary;
  }
  if (color == AppColors.muted || color == AppColors.softNavy) {
    return theme.colorScheme.onSurfaceVariant;
  }
  return color;
}

class HomiWaveform extends StatefulWidget {
  const HomiWaveform({
    this.active = false,
    this.amplitude = 0,
    this.width = 220,
    this.height = 48,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final bool active;
  final double amplitude;
  final double width;
  final double height;
  final Color? color;
  final String? semanticLabel;

  @override
  State<HomiWaveform> createState() => _HomiWaveformState();
}

class _HomiWaveformState extends State<HomiWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  bool _reduceMotion = false;
  bool _tickerModeEnabled = true;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    if (reduceMotion != _reduceMotion ||
        tickerModeEnabled != _tickerModeEnabled) {
      _reduceMotion = reduceMotion;
      _tickerModeEnabled = tickerModeEnabled;
      _syncAnimation();
    } else if (widget.active && !_motionController.isAnimating) {
      _syncAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant HomiWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate = widget.active && !_reduceMotion && _tickerModeEnabled;
    if (shouldAnimate) {
      if (!_motionController.isAnimating) {
        _motionController.repeat();
      }
    } else {
      _motionController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final measuredAmplitude = widget.amplitude.clamp(0.0, 1.0);
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _motionController,
            builder: (context, _) {
              final phase = _motionController.value * math.pi * 2;
              return Row(
                children: List<Widget>.generate(_waveBarRatios.length, (index) {
                  final distance = (index - (_waveBarRatios.length ~/ 2)).abs();
                  final isPink = distance <= 2 || index % 6 == 1;
                  final barColor =
                      tint ??
                      (isPink
                          ? (isDark
                                ? Theme.of(context).colorScheme.secondary
                                : AppColors.accentPink)
                          : (isDark
                                ? Theme.of(context).colorScheme.tertiary
                                : AppColors.mint));
                  final baseRatio = _waveBarRatios[index];
                  final wavePosition = (index * 0.72) - phase;
                  final travelingWave = (math.sin(wavePosition) + 1) / 2;
                  final softRipple =
                      (math.sin((wavePosition * 1.65) + (phase * 0.35)) + 1) /
                      2;
                  final envelope = 0.28 + (baseRatio * 0.72);
                  final animatedRatio =
                      widget.active && !_reduceMotion && _tickerModeEnabled
                      ? 0.10 +
                            (envelope *
                                (0.34 +
                                    (travelingWave * 0.46) +
                                    (softRipple * 0.08))) +
                            (measuredAmplitude * envelope * 0.16)
                      : baseRatio;
                  final resolvedRatio = animatedRatio.clamp(0.12, 1.0);
                  return Expanded(
                    child: Align(
                      child: FractionallySizedBox(
                        widthFactor: index == _waveBarRatios.length ~/ 2
                            ? 0.82
                            : 0.58,
                        child: Container(
                          key: ValueKey<String>('homi-wave-bar-$index'),
                          height: widget.height * resolvedRatio,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}

const _waveBarRatios = <double>[
  0.12,
  0.21,
  0.32,
  0.46,
  0.28,
  0.56,
  0.37,
  0.66,
  0.44,
  0.79,
  1,
  0.71,
  0.49,
  0.68,
  0.40,
  0.56,
  0.35,
  0.46,
  0.31,
  0.21,
  0.12,
];
