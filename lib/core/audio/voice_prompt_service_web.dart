import 'dart:js_interop';

import 'bundled_voice_prompt_library.dart';
import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const WebVoicePromptService();

bool isPlatformVoicePromptService(VoicePromptService service) =>
    service is WebVoicePromptService;

@JS('innotrikVoicePromptSpeak')
external void _speakPrompt(JSString text, JSString locale, JSString? audioUrl);

@JS('innotrikVoicePromptSpeakAndWait')
external JSPromise<JSString> _speakPromptAndWait(
  JSString text,
  JSString locale,
  JSString? audioUrl,
);

@JS('innotrikVoicePromptStop')
external void _stopPrompt();

@JS('innotrikSpeechReadyCue')
external void _playSpeechReadyCue();

class WebVoicePromptService
    implements
        VoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService {
  const WebVoicePromptService();
  static int _revision = 0;

  Future<String?> _audioUrl(String text, String locale) async {
    try {
      final uri = await BundledVoicePromptLibrary.shared.uriFor(
        text,
        locale: locale,
      );
      return uri?.isScheme('https') == true ? uri.toString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    if (text.trim().isEmpty) {
      return;
    }
    final revision = ++_revision;
    _stopPrompt();
    final url = await _audioUrl(text, locale);
    if (revision != _revision) return;
    _speakPrompt(text.trim().toJS, locale.toJS, url?.toJS);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }
    final revision = ++_revision;
    _stopPrompt();
    final url = await _audioUrl(normalizedText, locale);
    if (revision != _revision) return;
    try {
      await _speakPromptAndWait(
        normalizedText.toJS,
        locale.toJS,
        url?.toJS,
      ).toDart.timeout(const Duration(seconds: 45));
    } catch (_) {
      // Browser speech is supplementary. Stop a stalled utterance so the
      // lesson can continue instead of blocking forever on a WebKit edge case.
      if (revision == _revision) _stopPrompt();
    }
  }

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWait(text, locale: locale);

  @override
  Future<void> playSpeechReadyCue() async {
    _playSpeechReadyCue();
    // Keep the microphone closed until the tone and a short anti-echo gap end.
    await Future<void>.delayed(const Duration(milliseconds: 260));
  }

  @override
  Future<void> stop() async {
    ++_revision;
    _stopPrompt();
  }

  @override
  Future<void> dispose() => stop();
}
