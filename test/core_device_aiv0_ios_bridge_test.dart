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

  test(
    'serializes Flutter MAIN diagnostics into the native timeline',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final control = MethodChannelAiv0BleControl(
        enabled: true,
        draftProtocolConfirmed: false,
      );

      await Future.wait<void>(<Future<void>>[
        control.recordMainDiagnostic(
          stage: 'MAIN_DART_RECEIVED',
          values: const <String, Object?>{'sequence': 7},
        ),
        control.recordMainDiagnostic(
          stage: 'MAIN_DART_DISPATCH_COMPLETED',
          values: const <String, Object?>{'result': 'accepted'},
        ),
      ]);

      expect(calls.map((call) => call.method), <String>[
        'recordMainDiagnostic',
        'recordMainDiagnostic',
      ]);
      expect(
        (calls.first.arguments as Map<Object?, Object?>)['stage'],
        'MAIN_DART_RECEIVED',
      );
      expect(
        (calls.last.arguments as Map<Object?, Object?>)['stage'],
        'MAIN_DART_DISPATCH_COMPLETED',
      );
      await control.dispose();
    },
  );
}
