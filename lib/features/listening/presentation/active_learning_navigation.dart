import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool _isAndroidBackground() {
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  return !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      (lifecycle == AppLifecycleState.inactive ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.paused);
}

Route<T> _activeLearningRoute<T extends Object?>(
  WidgetBuilder builder, {
  required bool androidBackground,
  RouteSettings? settings,
  Duration? foregroundTransitionDuration,
  Duration? foregroundReverseTransitionDuration,
  RouteTransitionsBuilder? foregroundTransitionsBuilder,
}) {
  if (!androidBackground) {
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

  // A MaterialPageRoute waits for Android's display vsync to advance its
  // transition. Vsync is paused while the phone UI is hidden/locked, leaving
  // the next lesson screen unbuilt until the user returns to the app. A
  // zero-duration route lets one warm frame install and initialise the screen.
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

/// Pushes the next lesson route while preserving normal Material transitions
/// in the foreground and allowing the route to initialise in Android's
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
  final androidBackground = _isAndroidBackground();
  final navigation = Navigator.of(context).push<T>(
    _activeLearningRoute<T>(
      builder,
      androidBackground: androidBackground,
      settings: settings,
      foregroundTransitionDuration: foregroundTransitionDuration,
      foregroundReverseTransitionDuration: foregroundReverseTransitionDuration,
      foregroundTransitionsBuilder: foregroundTransitionsBuilder,
    ),
  );
  if (androidBackground) {
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
  final androidBackground = _isAndroidBackground();
  final navigation = Navigator.of(context).pushReplacement<T, TO>(
    _activeLearningRoute<T>(
      builder,
      androidBackground: androidBackground,
      settings: settings,
    ),
    result: result,
  );
  if (androidBackground) {
    binding.scheduleWarmUpFrame();
  }
  return navigation;
}
