import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundLearningEvent.fromRaw', () {
    test('maps a native interruption without losing its reason', () {
      final event = BackgroundLearningEvent.fromRaw(<Object?, Object?>{
        'type': 'background.interrupted',
        'reason': 'audio_focus_loss',
      });

      expect(event.type, BackgroundLearningEventType.interrupted);
      expect(event.reason, 'audio_focus_loss');
    });

    test('maps a resumable native audio session event', () {
      final event = BackgroundLearningEvent.fromRaw(<Object?, Object?>{
        'type': 'background.resumable',
        'reason': 'audio_session_interruption_ended',
      });

      expect(event.type, BackgroundLearningEventType.resumable);
      expect(event.reason, 'audio_session_interruption_ended');
    });

    test('treats stopped and malformed payloads as stopped', () {
      expect(
        BackgroundLearningEvent.fromRaw(<String, String>{
          'type': 'background.stopped',
        }).type,
        BackgroundLearningEventType.stopped,
      );
      expect(
        BackgroundLearningEvent.fromRaw('invalid').type,
        BackgroundLearningEventType.stopped,
      );
    });
  });

  test('forwards the active lesson wake state to Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('test_background_learning');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    final session = MethodChannelBackgroundLearningSession(
      methodChannel: channel,
    );
    await session.setActiveLearning(true);
    await session.setActiveLearning(false);

    expect(calls.map((call) => call.method), <String>[
      'setActiveLearning',
      'setActiveLearning',
    ]);
    expect(calls.first.arguments, <String, bool>{'active': true});
    expect(calls.last.arguments, <String, bool>{'active': false});
  });

  test(
    'requests parent-visible H20 companion association on Android',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('test_background_companion');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return <Object?, Object?>{
          'supported': true,
          'associated': true,
          'deviceId': 'AA:BB:CC:DD:EE:FF',
        };
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });

      final associated = await MethodChannelBackgroundLearningSession(
        methodChannel: channel,
      ).associateH20Companion('AA:BB:CC:DD:EE:FF');

      expect(associated, isTrue);
      expect(captured?.method, 'companion.associate');
      expect(captured?.arguments, <String, Object?>{
        'deviceId': 'AA:BB:CC:DD:EE:FF',
      });
    },
  );
}
