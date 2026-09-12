import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/device_connection_feedback_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows HOMI progress while BLE is connecting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceConnectionFeedbackOverlay(
          stage: DeviceConnectionFeedbackStage.connecting,
        ),
      ),
    );

    expect(find.text('Đang kết nối thiết bị'), findsOneWidget);
    expect(find.byKey(const Key('device-connection-progress')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shows a distinct short success state after BLE connects', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceConnectionFeedbackOverlay(
          stage: DeviceConnectionFeedbackStage.connected,
        ),
      ),
    );

    expect(find.text('Đã kết nối thiết bị'), findsOneWidget);
    expect(
      find.byKey(const Key('device-connection-success-icon')),
      findsOneWidget,
    );
    expect(find.textContaining('nút MAIN'), findsOneWidget);
  });
}
