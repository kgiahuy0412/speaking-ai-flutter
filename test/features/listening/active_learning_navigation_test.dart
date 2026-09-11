import 'package:ai_speaking_flutter_app/core/navigation/active_learning_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses an immediate route while Android is paused', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final observer = _RouteObserver();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    pushForActiveLearning<void>(
      pageContext,
      (_) => const Scaffold(body: Text('next lesson')),
    );
    await tester.pump();

    expect(observer.lastPushed, isA<PageRouteBuilder<void>>());
    expect(find.text('next lesson'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('uses an immediate route while iOS is paused', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final observer = _RouteObserver();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    pushForActiveLearning<void>(
      pageContext,
      (_) => const Scaffold(body: Text('iOS background lesson')),
    );
    await tester.pump();

    expect(observer.lastPushed, isA<PageRouteBuilder<void>>());
    expect(
      (observer.lastPushed! as PageRouteBuilder<void>).transitionDuration,
      Duration.zero,
    );
    expect(find.text('iOS background lesson'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('replaces an iOS lesson route while the screen is locked', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final observer = _RouteObserver();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('lesson intro'));
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    pushReplacementForActiveLearning<void, void>(
      pageContext,
      (_) => const Scaffold(body: Text('lesson practice')),
    );
    await tester.pump();

    expect(observer.lastPushed, isA<PageRouteBuilder<void>>());
    expect(
      (observer.lastPushed! as PageRouteBuilder<void>).transitionDuration,
      Duration.zero,
    );
    expect(find.text('lesson practice'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keeps Material route transitions in the foreground', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final observer = _RouteObserver();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    pushForActiveLearning<void>(
      pageContext,
      (_) => const Scaffold(body: Text('next lesson')),
    );
    await tester.pump();

    expect(observer.lastPushed, isA<MaterialPageRoute<void>>());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keeps a custom transition only in the foreground', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final observer = _RouteObserver();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    pushForActiveLearning<void>(
      pageContext,
      (_) => const Scaffold(body: Text('custom lesson')),
      foregroundTransitionDuration: const Duration(milliseconds: 260),
      foregroundTransitionsBuilder:
          (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
    );
    await tester.pump();

    final foregroundRoute = observer.lastPushed as PageRouteBuilder<void>;
    expect(
      foregroundRoute.transitionDuration,
      const Duration(milliseconds: 260),
    );

    await tester.pumpAndSettle();
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    pushForActiveLearning<void>(
      pageContext,
      (_) => const Scaffold(body: Text('background lesson')),
      foregroundTransitionDuration: const Duration(milliseconds: 260),
      foregroundTransitionsBuilder:
          (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
    );
    await tester.pump();

    final backgroundRoute = observer.lastPushed as PageRouteBuilder<void>;
    expect(backgroundRoute.transitionDuration, Duration.zero);
    expect(find.text('background lesson'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    lastPushed = newRoute;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
