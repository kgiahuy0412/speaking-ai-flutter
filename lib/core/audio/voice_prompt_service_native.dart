import 'package:flutter/services.dart';

import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const MethodChannelVoicePromptService();

class MethodChannelVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  const MethodChannelVoicePromptService({
    MethodChannel channel = const MethodChannel('ailingo_voice_prompt'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speak', text, locale: locale);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speakAndWait', text, locale: locale);
  }

  Future<void> _invokeSpeak(
    String method,
    String text, {
    required String locale,
  }) async {
    if (text.trim().isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, <String, dynamic>{
        'text': text.trim(),
        'locale': locale,
      });
    } on MissingPluginException {
      // The prompt is supplementary. The visible message remains available on
      // platforms where the native bridge has not been implemented yet.
    } on PlatformException {
      // A device may not have a Vietnamese TTS voice installed. Do not turn a
      // recognition retry into another user-facing error.
    }
  }

  @override
  Future<void> playSpeechReadyCue() async {
    try {
      await _channel.invokeMethod<void>('playSpeechReadyCue');
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // A missing audio route must not prevent the child from speaking.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // Best effort only.
    }
  }

  @override
  Future<void> dispose() => stop();
}
