import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isActiveLearningAppBackground() {
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      (lifecycle == AppLifecycleState.inactive ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.paused);
}

Route<T> _activeLearningRoute<T extends Object?>(
  WidgetBuilder builder, {
  required bool mobileBackground,
  RouteSettings? settings,
  Duration? foregroundTransitionDuration,
  Duration? foregroundReverseTransitionDuration,
  RouteTransitionsBuilder? foregroundTransitionsBuilder,
}) {
  if (!mobileBackground) {
    if (foregroundTransitionsBuilder != null) {
      return PageRouteBuilder<T>(
        settings: settings,
        transitionDuration:
            foregroundTransitionDuration ?? const Duration(milliseconds: 300),
        reverseTransitionDuration:
            foregroundReverseTransitionDuration ??
            foregroundTransitionDuration ??
            const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: foregroundTransitionsBuilder,
      );
    }
    return MaterialPageRoute<T>(builder: builder, settings: settings);
  }

  // A MaterialPageRoute waits for display vsync to advance its transition.
  // Android and iOS both pause normal rendering while hidden/locked, leaving
  // the next lesson screen unbuilt until the user returns. A zero-duration
  // route plus one warm frame installs the next audio-owned flow immediately.
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

/// Pushes the next lesson route while preserving normal Material transitions
/// in the foreground and allowing the route to initialise in Android/iOS
/// background learning mode.
Future<T?> pushForActiveLearning<T extends Object?>(
  BuildContext context,
  WidgetBuilder builder, {
  RouteSettings? settings,
  Duration? foregroundTransitionDuration,
  Duration? foregroundReverseTransitionDuration,
  RouteTransitionsBuilder? foregroundTransitionsBuilder,
}) {
  final binding = WidgetsBinding.instance;
  final mobileBackground = isActiveLearningAppBackground();
  final navigation = Navigator.of(context).push<T>(
    _activeLearningRoute<T>(
      builder,
      mobileBackground: mobileBackground,
      settings: settings,
      foregroundTransitionDuration: foregroundTransitionDuration,
      foregroundReverseTransitionDuration: foregroundReverseTransitionDuration,
      foregroundTransitionsBuilder: foregroundTransitionsBuilder,
    ),
  );
  if (mobileBackground) {
    binding.scheduleWarmUpFrame();
  }
  return navigation;
}

/// Replaces the current lesson route with the same background-safe behaviour
/// as [pushForActiveLearning].
Future<T?>
pushReplacementForActiveLearning<T extends Object?, TO extends Object?>(
  BuildContext context,
  WidgetBuilder builder, {
  TO? result,
  RouteSettings? settings,
}) {
  final binding = WidgetsBinding.instance;
  final mobileBackground = isActiveLearningAppBackground();
  final navigation = Navigator.of(context).pushReplacement<T, TO>(
    _activeLearningRoute<T>(
      builder,
      mobileBackground: mobileBackground,
      settings: settings,
    ),
    result: result,
  );
  if (mobileBackground) {
    binding.scheduleWarmUpFrame();
  }
  return navigation;
}
