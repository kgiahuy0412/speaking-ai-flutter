import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ailingo_aiv0_ble_control');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('AIV0 native bridge is enabled on iOS', () async {
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );

    expect(control.status.phase, Aiv0BlePhase.idle);
    await control.dispose();
  });

  test('records Parent opening and refreshes the returned timeline', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (call.method == 'markParentDiagnosticsOpened') {
            return <Object?, Object?>{
              'phase': 'connected',
              'peripheralState': 'connected',
              'mainNotificationState': 'notifying',
              'diagnosticTimeline': <Object?>[
                <Object?, Object?>{
                  'stage': 'PARENT_SCREEN_OPENED',
                  'caller': 'Aiv0BleControlBridge.methodChannel',
                  'eventEpochMs': 1_787_900_045_000,
                },
              ],
            };
          }
          return null;
        });
    final control = MethodChannelAiv0BleControl(
      enabled: true,
      draftProtocolConfirmed: false,
    );

    await control.markParentDiagnosticsOpened();

    expect(methods, <String>['markParentDiagnosticsOpened']);
    expect(
      control.status.diagnosticTimeline.single.stage,
      'PARENT_SCREEN_OPENED',
    );
    await control.dispose();
  });
}
