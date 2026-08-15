import 'dart:js_interop';

import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const WebVoicePromptService();

@JS('innotrikVoicePromptSpeak')
external void _speakPrompt(JSString text, JSString locale);

@JS('innotrikVoicePromptStop')
external void _stopPrompt();

@JS('innotrikSpeechReadyCue')
external void _playSpeechReadyCue();

class WebVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  const WebVoicePromptService();

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    if (text.trim().isEmpty) {
      return;
    }
    _speakPrompt(text.trim().toJS, locale.toJS);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await speak(text, locale: locale);
    if (text.trim().isNotEmpty) {
      await Future<void>.delayed(
        Duration(milliseconds: 450 + (text.trim().length * 55)),
      );
    }
  }

  @override
  Future<void> playSpeechReadyCue() async {
    _playSpeechReadyCue();
    // Keep the microphone closed until the tone and a short anti-echo gap end.
    await Future<void>.delayed(const Duration(milliseconds: 260));
  }

  @override
  Future<void> stop() async => _stopPrompt();

  @override
  Future<void> dispose() => stop();
}
