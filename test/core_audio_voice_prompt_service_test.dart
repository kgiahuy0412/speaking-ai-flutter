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
    });
  });
}
