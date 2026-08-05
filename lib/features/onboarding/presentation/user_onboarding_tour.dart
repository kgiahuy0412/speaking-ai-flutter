import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';

enum UserOnboardingStepKind { welcome, spotlight, complete }

class UserOnboardingStep {
  const UserOnboardingStep({
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
  });

  final UserOnboardingStepKind kind;
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;
}

class UserOnboardingTour extends StatefulWidget {
  const UserOnboardingTour({
    required this.steps,
    required this.currentIndex,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
    super.key,
  });

  final List<UserOnboardingStep> steps;
  final int currentIndex;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onSkip;

  @override
  State<UserOnboardingTour> createState() => _UserOnboardingTourState();
}

class _UserOnboardingTourState extends State<UserOnboardingTour>
    with WidgetsBindingObserver {
  Rect? _targetRect;

  UserOnboardingStep get _step => widget.steps[widget.currentIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleTargetMeasurement();
  }

  @override
  void didUpdateWidget(covariant UserOnboardingTour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.steps != widget.steps) {
      _targetRect = null;
      _scheduleTargetMeasurement();
    }
  }

  @override
  void didChangeMetrics() => _scheduleTargetMeasurement();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleTargetMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext = _step.targetKey?.currentContext;
      final targetBox = targetContext?.findRenderObject();
      final overlayBox = context.findRenderObject();
      if (targetBox is! RenderBox ||
          overlayBox is! RenderBox ||
          !targetBox.hasSize ||
          !overlayBox.hasSize) {
        if (_targetRect != null) {
          setState(() => _targetRect = null);
        }
        return;
      }
      final globalTopLeft = targetBox.localToGlobal(Offset.zero);
      final localTopLeft = overlayBox.globalToLocal(globalTopLeft);
      final measured = localTopLeft & targetBox.size;
      if (_targetRect != measured) {
        setState(() => _targetRect = measured);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final spotlightStep = _step.kind == UserOnboardingStepKind.spotlight;
    final targetRect = spotlightStep ? _targetRect : null;
    final previous = widget.onPrevious;

    return Material(
      key: const Key('user-onboarding-tour'),
      color: Colors.transparent,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: _semanticLabel,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                painter: _SpotlightPainter(
                  targetRect: targetRect,
                  overlayColor: Colors.black.withValues(
                    alpha: isDark ? 0.70 : 0.62,
                  ),
                  ringColor: theme.colorScheme.primary,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                child: Column(
                  children: <Widget>[
                    if (_step.kind != UserOnboardingStepKind.complete)
                      Align(
                        alignment: _skipAlignment(targetRect, mediaQuery.size),
                        child: TextButton(
                          key: const Key('user-onboarding-skip'),
                          onPressed: widget.onSkip,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.24,
                            ),
                            minimumSize: const Size(82, 46),
                          ),
                          child: Text(
                            context.tr('Bỏ qua', '跳过'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 46),
                    Expanded(
                      child: Align(
                        alignment: _cardAlignment(targetRect, mediaQuery.size),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AnimatedSwitcher(
                            duration: mediaQuery.disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            child: _TourCard(
                              key: ValueKey<int>(widget.currentIndex),
                              step: _step,
                              currentIndex: widget.currentIndex,
                              spotlightCount: _spotlightCount,
                              spotlightNumber: _spotlightNumber,
                              onPrevious: previous,
                              onNext: widget.onNext,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Alignment _cardAlignment(Rect? target, Size size) {
    if (target == null) {
      return Alignment.center;
    }
    final centerY = target.center.dy / math.max(1, size.height);
    return centerY > 0.54 ? Alignment.topCenter : Alignment.bottomCenter;
  }

  Alignment _skipAlignment(Rect? target, Size size) {
    if (target != null &&
        target.center.dx > size.width * 0.62 &&
        target.top < size.height * 0.22) {
      return Alignment.topLeft;
    }
    return Alignment.topRight;
  }

  int get _spotlightCount => widget.steps
      .where((step) => step.kind == UserOnboardingStepKind.spotlight)
      .length;

  int? get _spotlightNumber {
    if (_step.kind != UserOnboardingStepKind.spotlight) {
      return null;
    }
    return widget.steps
        .take(widget.currentIndex + 1)
        .where((step) => step.kind == UserOnboardingStepKind.spotlight)
        .length;
  }

  String get _semanticLabel {
    final number = _spotlightNumber;
    final prefix = number == null
        ? ''
        : '${context.tr('Bước', '步骤')} $number/$_spotlightCount. ';
    return '$prefix${_step.title}. ${_step.description}';
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.currentIndex,
    required this.spotlightCount,
    required this.spotlightNumber,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final UserOnboardingStep step;
  final int currentIndex;
  final int spotlightCount;
  final int? spotlightNumber;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isWelcome = step.kind == UserOnboardingStepKind.welcome;
    final isComplete = step.kind == UserOnboardingStepKind.complete;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.98)
            : const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? colorScheme.outline : const Color(0xFFDDE3FF),
          width: 1.4,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x52081235),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isWelcome || isComplete)
            Image.asset(
              isComplete ? MascotAssets.speak : MascotAssets.wave,
              width: 100,
              height: 100,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            )
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, color: colorScheme.primary, size: 30),
            ),
          const SizedBox(height: 12),
          if (spotlightNumber != null) ...<Widget>[
            Text(
              '${context.tr('BƯỚC', '步骤')} '
              '$spotlightNumber/$spotlightCount',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              if (onPrevious != null) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('user-onboarding-previous'),
                    onPressed: onPrevious,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(context.tr('Quay lại', '返回')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: onPrevious == null ? 1 : 2,
                child: FilledButton.icon(
                  key: const Key('user-onboarding-next'),
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    isComplete
                        ? Icons.mic_rounded
                        : isWelcome
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(
                    isComplete
                        ? context.tr('Thử nói ngay', '立即试说')
                        : isWelcome
                        ? context.tr('Bắt đầu', '开始')
                        : context.tr('Tiếp', '下一步'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.targetRect,
    required this.overlayColor,
    required this.ringColor,
  });

  final Rect? targetRect;
  final Color overlayColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Offset.zero & size);
    final target = targetRect;
    if (target == null) {
      canvas.drawPath(fullScreen, Paint()..color = overlayColor);
      return;
    }
    final inflated = target.inflate(10);
    final radius = math.min(30.0, inflated.shortestSide / 3);
    final spotlight = RRect.fromRectAndRadius(
      inflated,
      Radius.circular(math.max(14, radius)),
    );
    final mask = Path.combine(
      PathOperation.difference,
      fullScreen,
      Path()..addRRect(spotlight),
    );
    canvas.drawPath(mask, Paint()..color = overlayColor);
    canvas.drawRRect(
      spotlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      spotlight.inflate(4),
      Paint()
        ..color = ringColor.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.ringColor != ringColor;
}
