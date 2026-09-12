import 'package:flutter/services.dart';

import 'audio_gain.dart';
import 'bundled_voice_prompt_library.dart';
import 'device_audio_cache.dart';
import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const MethodChannelVoicePromptService();

bool isPlatformVoicePromptService(VoicePromptService service) =>
    service is MethodChannelVoicePromptService;

class MethodChannelVoicePromptService
    implements
        VoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  const MethodChannelVoicePromptService({
    MethodChannel channel = const MethodChannel('ailingo_voice_prompt'),
    BundledVoicePromptLibrary? library,
    Future<Uri?> Function(Uri)? audioFileResolver,
  }) : _channel = channel,
       _library = library,
       _audioFileResolver = audioFileResolver;

  final MethodChannel _channel;
  final BundledVoicePromptLibrary? _library;
  final Future<Uri?> Function(Uri)? _audioFileResolver;
  static final DeviceAudioCache _recordedAudioCache = DeviceAudioCache();
  // All instances of a native channel share one player. Stop/new speech must
  // also invalidate older asynchronous asset lookups across those instances.
  static final Map<String, int> _revisions = <String, int>{};
  int _nextRevision() =>
      _revisions[_channel.name] = (_revisions[_channel.name] ?? 0) + 1;

  @override
  Future<String?> beginMainTurn() async {
    try {
      return await _channel.invokeMethod<String>('beginMainTurn');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    try {
      await _channel.invokeMethod<void>('endMainTurn', <String, dynamic>{
        'reason': reason,
        'turnId': ?turnId,
      });
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // Turn cleanup is best effort during navigation cancellation.
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speak', text, locale: locale);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speakAndWait', text, locale: locale);
  }

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) async {
    await _invokeSpeak(
      'speakAndWait',
      text,
      locale: locale,
      forcePhoneSpeaker: true,
    );
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    await _invokeSpeak(
      'speakAndWait',
      text,
      locale: locale,
      forceMediaPlayback: true,
    );
  }

  Future<void> _invokeSpeak(
    String method,
    String text, {
    required String locale,
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    if (text.trim().isEmpty) {
      return;
    }
    final revision = _nextRevision();
    String? asset;
    String? filePath;
    try {
      final uri = await (_library ?? BundledVoicePromptLibrary.shared).uriFor(
        text,
        locale: locale,
      );
      if (_revisions[_channel.name] != revision) return;
      if (uri != null && uri.isScheme('asset')) {
        asset = uri.path.replaceFirst(RegExp(r'^/'), '');
      } else if (uri != null) {
        // A complete local download works with both native players and keeps
        // their existing H20 routing and completion callbacks intact.
        final local = await (_audioFileResolver ?? _recordedAudioCache.cache)(
          uri,
        );
        if (local != null && local.isScheme('file')) {
          filePath = local.toFilePath();
        }
      }
    } catch (_) {
      // Missing/corrupt optional packs keep the existing device voice usable.
    }
    if (_revisions[_channel.name] != revision) return;
    try {
      await _channel.invokeMethod<void>(method, <String, dynamic>{
        'text': text.trim(),
        'locale': locale,
        'gainDb': androidSpeechBoostDb,
        'forcePhoneSpeaker': forcePhoneSpeaker,
        'forceMediaPlayback': forceMediaPlayback,
        'assetPath': ?asset,
        'filePath': ?filePath,
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
    _nextRevision();
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
