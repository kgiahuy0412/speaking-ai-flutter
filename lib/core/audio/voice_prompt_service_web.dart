import 'dart:js_interop';

import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const WebVoicePromptService();

@JS('innotrikVoicePromptSpeak')
external void _speakPrompt(JSString text, JSString locale);

@JS('innotrikVoicePromptSpeakAndWait')
external JSPromise<JSString> _speakPromptAndWait(
  JSString text,
  JSString locale,
);

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
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }
    try {
      await _speakPromptAndWait(
        normalizedText.toJS,
        locale.toJS,
      ).toDart.timeout(const Duration(seconds: 20));
    } catch (_) {
      // Browser speech is supplementary. Stop a stalled utterance so the
      // lesson can continue instead of blocking forever on a WebKit edge case.
      _stopPrompt();
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
