import 'dart:async';

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
        (isDark ? theme.colorScheme.surfaceContainer : const Color(0xF8FFFDF9));
    final resolvedBorder =
        borderColor ??
        (isDark ? theme.colorScheme.outlineVariant : const Color(0xB8E7E8F5));
    return Container(
      width: double.infinity,
      margin: margin,
      constraints: constraints,
      child: Material(
        color: resolvedColor,
        elevation: elevated ? 2 : 0,
        shadowColor: const Color(0x24142451),
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
    final title = Text(
      this.title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          HomiIconBadge(icon: icon!, size: 40, iconSize: 22),
          const SizedBox(width: 11),
        ],
        Expanded(child: title),
        if (trailing != null) ...<Widget>[const SizedBox(width: 10), trailing!],
      ],
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
    final foreground = foregroundColor ?? theme.colorScheme.primary;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class HomiWaveform extends StatefulWidget {
  const HomiWaveform({
    this.active = false,
    this.width = 220,
    this.height = 48,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final bool active;
  final double width;
  final double height;
  final Color? color;
  final String? semanticLabel;

  @override
  State<HomiWaveform> createState() => _HomiWaveformState();
}

class _HomiWaveformState extends State<HomiWaveform> {
  Timer? _timer;
  bool _expanded = true;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      _syncAnimation();
    } else if (_timer == null && widget.active) {
      _syncAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant HomiWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    _timer?.cancel();
    _timer = null;
    _expanded = true;
    if (widget.active && !_reduceMotion) {
      _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
        if (mounted) setState(() => _expanded = !_expanded);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color;
    final Widget image = tint != null
        ? SizedBox(
            width: widget.width,
            height: widget.height,
            child: FittedBox(
              fit: BoxFit.fill,
              child: Icon(Icons.graphic_eq_rounded, color: tint, size: 56),
            ),
          )
        : Image.asset(
            'assets/images/home-waveform.png',
            width: widget.width,
            height: widget.height,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          );
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: widget.active ? 0.76 : 1,
            end: widget.active && !_reduceMotion ? (_expanded ? 1 : 0.76) : 1,
          ),
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          builder: (context, scale, child) => Opacity(
            opacity: widget.active ? 0.82 + ((scale - 0.76) * 0.75) : 1,
            child: Transform.scale(
              alignment: Alignment.center,
              scaleY: scale,
              child: child,
            ),
          ),
          child: image,
        ),
      ),
    );
  }
}
