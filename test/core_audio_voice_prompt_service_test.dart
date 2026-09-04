import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends the Vietnamese retry prompt through the native bridge', () async {
    const channel = MethodChannel('test_voice_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speak('Con đưa micro lại gần và nói rõ hơn nhé.');

    expect(receivedCall?.method, 'speak');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Con đưa micro lại gần và nói rõ hơn nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': false,
      'forceMediaPlayback': false,
    });
  });

  test(
    'waits for the wake acknowledgement through the native bridge',
    () async {
      const channel = MethodChannel('test_voice_prompt_wait');
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      const service = MethodChannelVoicePromptService(channel: channel);
      await service.speakAndWait('HOMI nghe đây.');

      expect(receivedCall?.method, 'speakAndWait');
      expect(receivedCall?.arguments, <String, dynamic>{
        'text': 'HOMI nghe đây.',
        'locale': 'vi-VN',
        'gainDb': 8.0,
        'forcePhoneSpeaker': false,
        'forceMediaPlayback': false,
      });
    },
  );

  test('marks listening coach speech for the phone speaker', () async {
    const channel = MethodChannel('test_phone_speaker_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speakAndWaitOnPhoneSpeaker('Nói theo cô nhé.');

    expect(receivedCall?.method, 'speakAndWait');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Nói theo cô nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': true,
      'forceMediaPlayback': false,
    });
  });

  test('marks lesson speech for selected H20 output', () async {
    const channel = MethodChannel('test_media_output_prompt');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.speakAndWaitOnSelectedMediaOutput('Con nói lại nhé.');

    expect(receivedCall?.method, 'speakAndWait');
    expect(receivedCall?.arguments, <String, dynamic>{
      'text': 'Con nói lại nhé.',
      'locale': 'vi-VN',
      'gainDb': 8.0,
      'forcePhoneSpeaker': false,
      'forceMediaPlayback': true,
    });
  });

  test('waits for the speech-ready cue through the native bridge', () async {
    const channel = MethodChannel('test_speech_ready_cue');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    await service.playSpeechReadyCue();

    expect(receivedCall?.method, 'playSpeechReadyCue');
    expect(receivedCall?.arguments, isNull);
  });

  test('brackets one MAIN turn through the native coordinator', () async {
    const channel = MethodChannel('test_main_turn_prompt');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'beginMainTurn') return 'ios-main-test';
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelVoicePromptService(channel: channel);
    expect(await service.beginMainTurn(), 'ios-main-test');
    await service.endMainTurn('test_complete', turnId: 'ios-main-test');

    expect(calls.map((call) => call.method), <String>[
      'beginMainTurn',
      'endMainTurn',
    ]);
    expect(calls.last.arguments, <String, dynamic>{
      'reason': 'test_complete',
      'turnId': 'ios-main-test',
    });
  });
}
