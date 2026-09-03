import 'package:ai_speaking_flutter_app/core/pwa/pwa_install_gate.dart';
import 'package:ai_speaking_flutter_app/core/pwa/pwa_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the four-step iOS web guide inside an in-app browser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: PwaInstallGate(
          runtimeState: PwaRuntimeState(
            installRequired: true,
            inAppBrowser: true,
          ),
          child: Text('MAIN_APP'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pwa-install-guide')), findsOneWidget);
    expect(find.text('Cài HOMI lên iPhone'), findsOneWidget);
    expect(
      find.text('Chọn “Mở bằng Safari” trong trình duyệt hiện tại.'),
      findsOneWidget,
    );
    for (var step = 1; step <= 4; step += 1) {
      expect(find.byKey(ValueKey('pwa-install-step-$step')), findsOneWidget);
    }
    expect(find.text('MAIN_APP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows the three Safari steps when the page is already in Safari',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PwaInstallGate(
            runtimeState: PwaRuntimeState(
              installRequired: true,
              inAppBrowser: false,
            ),
            child: Text('MAIN_APP'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('pwa-install-guide')), findsOneWidget);
      expect(
        find.text('Chọn “Mở bằng Safari” trong trình duyệt hiện tại.'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pwa-install-step-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-install-step-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-install-step-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-install-step-4')), findsNothing);
      expect(find.text('MAIN_APP'), findsNothing);
    },
  );

  testWidgets('opens the app directly outside uninstalled iOS web', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PwaInstallGate(
          runtimeState: PwaRuntimeState(
            installRequired: false,
            inAppBrowser: false,
          ),
          child: Text('MAIN_APP'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pwa-install-guide')), findsNothing);
    expect(find.text('MAIN_APP'), findsOneWidget);
  });
}
