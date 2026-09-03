import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retries a transient iOS HFP route-unavailable transition', () async {
    const methodChannel = MethodChannel('test_hfp_route_recovery');
    const eventChannel = EventChannel('test_hfp_route_recovery/events');
    const eventMethodChannel = MethodChannel('test_hfp_route_recovery/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'old-h20-uid',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'startAudioRoute':
          startCalls += 1;
          if (startCalls == 1) {
            throw PlatformException(
              code: 'HFP_ROUTE_UNAVAILABLE',
              message: 'HFP input is still returning after media playback.',
            );
          }
          return <String, dynamic>{
            'phase': 'recording',
            'deviceId': 'new-h20-uid',
            'deviceName': 'H20',
            'routeActive': true,
          };
        case 'stopAudioRoute':
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    await control.startAudioRoute();

    expect(startCalls, 2);
    expect(control.status.routeActive, isTrue);
    expect(control.status.deviceId, 'new-h20-uid');
  });

  test('stop invalidates a pending route retry', () async {
    const methodChannel = MethodChannel('test_hfp_route_cancel');
    const eventChannel = EventChannel('test_hfp_route_cancel/events');
    const eventMethodChannel = MethodChannel('test_hfp_route_cancel/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    var stopCalls = 0;
    messenger.setMockMethodCallHandler(eventMethodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return <String, dynamic>{
            'phase': 'ready',
            'deviceId': 'h20',
            'deviceName': 'H20',
            'routeActive': false,
          };
        case 'startAudioRoute':
          startCalls += 1;
          throw PlatformException(
            code: 'HFP_ROUTE_UNAVAILABLE',
            message: 'Route is settling.',
          );
        case 'stopAudioRoute':
          stopCalls += 1;
          return null;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(eventMethodChannel, null);
    });
    final control = MethodChannelHfpAudioControl(
      enabled: true,
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    addTearDown(control.dispose);

    final pendingStart = control.startAudioRoute();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await control.stopAudioRoute();
    await pendingStart.timeout(const Duration(milliseconds: 400));

    expect(startCalls, 1);
    expect(stopCalls, 1);
  });
}
