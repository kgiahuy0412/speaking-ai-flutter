import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/app/startup_splash_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the logo for one second before entering the app', () {
    expect(appStartupMinimumDuration, const Duration(seconds: 1));
  });

  testWidgets('shows only the app logo without loading UI', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: StartupSplashScreen()));
    await tester.pump();

    expect(find.byKey(const ValueKey('startup-app-icon')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: StartupSplashScreen()));
    await tester.pump();

    expect(find.byKey(const ValueKey('startup-app-icon')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares the bundled listening catalog preload', (tester) async {
    final firstRepository = AssetListeningContentRepository();
    final secondRepository = AssetListeningContentRepository();

    final firstLoad = firstRepository.load();
    final secondLoad = secondRepository.load();

    expect(identical(firstLoad, secondLoad), isTrue);
    final catalog = await firstLoad;
    expect(catalog.groups, isNotEmpty);
  });
}
