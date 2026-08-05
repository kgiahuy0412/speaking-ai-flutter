import 'package:ai_speaking_flutter_app/app/startup_splash_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the branded startup state and progress', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StartupSplashScreen(
          status: 'Đang chuẩn bị dữ liệu cần thiết...',
          progress: 0.55,
          version: '1.0.3',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('INNOTRIK'), findsOneWidget);
    expect(find.text('Cùng con nói tiếng Anh mỗi ngày'), findsOneWidget);
    expect(find.text('Đang chuẩn bị dữ liệu cần thiết...'), findsOneWidget);
    expect(find.text('v1.0.3'), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-app-icon')), findsOneWidget);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('startup-progress')),
    );
    expect(progress.value, 0.55);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains readable on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StartupSplashScreen(
          status: 'Sẵn sàng!',
          progress: 1,
          version: '1.0.3',
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('startup-ready')), findsOneWidget);
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
