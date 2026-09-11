import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/audio/voice_prompt_service.dart';
import 'homi_audio_library.dart';
import 'lesson_media_service.dart';

/// Platform TTS passed by a parent is a fallback, including instances retained
/// across hot reload. Only custom services remain complete output overrides.
/// Recorded services are rebound to each screen's media route.
VoicePromptService createLessonVoicePromptService({
  required LessonMediaService mediaService,
  VoicePromptService? override,
  int? age,
}) {
  if (override != null &&
      override is! RecordedLessonVoicePromptService &&
      !isPlatformVoicePromptService(override)) {
    return override;
  }
  final recorded = override is RecordedLessonVoicePromptService
      ? override
      : null;
  return RecordedLessonVoicePromptService(
    mediaService: mediaService,
    fallback: recorded?.fallback ?? override ?? createVoicePromptService(),
    ownsFallback: override == null,
    age: age ?? recorded?.age,
    library: recorded?._library,
  );
}

Future<void> speakRecordedLessonPrompt(
  VoicePromptService service,
  String text, {
  String locale = 'vi-VN',
  String? audioId,
  String? feedbackState,
}) => service is RecordedLessonVoicePromptService
    ? service.speakRecordedAndWait(
        text,
        locale: locale,
        audioId: audioId,
        feedbackState: feedbackState,
      )
    : service.speakAndWait(text, locale: locale);

/// Plays bundled speech at its authored speed and awaits completion before
/// capture. Cancellation covers both a pending index read and every segment
/// of an intro, so MAIN/pause cannot restart a stale prompt after stopping it.
class RecordedLessonVoicePromptService
    implements
        VoicePromptService,
        SelectedMediaOutputVoicePromptService,
        PhoneSpeakerVoicePromptService,
        SpeechReadyCuePlayer,
        MainTurnVoicePromptService {
  RecordedLessonVoicePromptService({
    required this.mediaService,
    required this.fallback,
    this.age,
    this.ownsFallback = false,
    this.ownsMediaService = false,
    HomiAudioLibrary? library,
    this.ttsTimeout = const Duration(seconds: 20),
  }) : _library = library ?? HomiAudioLibrary();

  static const playbackTimeout = Duration(seconds: 45);
  final LessonMediaService mediaService;
  final VoicePromptService fallback;
  final int? age;
  final bool ownsFallback;
  final bool ownsMediaService;
  final Duration ttsTimeout;
  final HomiAudioLibrary _library;
  int _generation = 0;
  bool _active = false;
  bool _disposed = false;
  Completer<void>? _cancelled;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speakRecordedAndWait(text, locale: locale);

  Future<void> speakRecordedAndWait(
    String text, {
    String locale = 'vi-VN',
    String? audioId,
    String? feedbackState,
  }) => _speak(
    text,
    locale: locale,
    audioId: audioId,
    feedbackState: feedbackState,
    route: LessonPlaybackRoute.selectedLessonDevice,
  );

  Future<void> _speak(
    String text, {
    required String locale,
    required LessonPlaybackRoute route,
    String? audioId,
    String? feedbackState,
  }) async {
    if (_disposed || text.trim().isEmpty) return;
    final generation = ++_generation;
    if (_active) {
      _completeCancellation();
      await Future.wait<void>([mediaService.stopPlayback(), fallback.stop()]);
      if (!_isCurrent(generation)) return;
    }
    _cancelled = Completer<void>();
    _active = true;
    try {
      List<HomiAudioSegment>? sequence;
      if (audioId == null && feedbackState == null && locale == 'vi-VN') {
        try {
          sequence = await _library.sequenceForText(text);
        } catch (error) {
          _trace('INDEX_ERROR during sequence lookup: $error');
        }
      }
      if (!_isCurrent(generation)) return;
      if (sequence != null) {
        for (final segment in sequence) {
          if (!_isCurrent(generation)) return;
          await _playSegment(
            segment.text,
            locale: segment.locale,
            audioId: segment.audioId,
            route: route,
            generation: generation,
          );
        }
      } else {
        await _playSegment(
          text,
          locale: locale,
          audioId: audioId,
          feedbackState: feedbackState,
          route: route,
          generation: generation,
        );
      }
    } finally {
      if (generation == _generation) _active = false;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _playSegment(
    String text, {
    required String locale,
    required LessonPlaybackRoute route,
    required int generation,
    String? audioId,
    String? feedbackState,
  }) async {
    HomiAudioClip? clip;
    var fallbackReason = 'no_matching_clip';
    try {
      clip = await _library.resolve(
        text: text,
        locale: locale,
        audioId: audioId,
        feedbackState: feedbackState,
        age: age,
      );
    } catch (error) {
      // An unavailable index still leaves all curriculum text speakable.
      fallbackReason = 'index_unavailable';
      _trace('INDEX_ERROR id=${audioId ?? "text_lookup"}: $error');
    }
    if (!_isCurrent(generation)) return;
    if (clip != null) {
      try {
        _trace('MP3 id=${clip.id} asset=${clip.uri.path}');
        await mediaService.playToCompletion(
          clip.uri,
          route: route,
          timeout: playbackTimeout,
        );
        return;
      } catch (error) {
        if (!_isCurrent(generation)) return;
        fallbackReason = 'playback_error';
        _trace('MP3_ERROR id=${clip.id}: $error');
        await mediaService.stopPlayback();
      }
    }
    if (!_isCurrent(generation)) return;
    _trace(
      'TTS reason=$fallbackReason id=${audioId ?? "text_lookup"} locale=$locale',
    );
    if (route == LessonPlaybackRoute.phoneSpeaker) {
      await mediaService.preparePhoneSpeakerOutput();
    } else {
      await mediaService.prepareSelectedLessonOutput();
    }
    if (!_isCurrent(generation)) return;
    final Future<void> speech;
    if (route == LessonPlaybackRoute.phoneSpeaker &&
        fallback is PhoneSpeakerVoicePromptService) {
      speech = (fallback as PhoneSpeakerVoicePromptService)
          .speakAndWaitOnPhoneSpeaker(text, locale: locale);
    } else if (fallback is SelectedMediaOutputVoicePromptService) {
      speech = (fallback as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
    } else {
      speech = fallback.speakAndWait(text, locale: locale);
    }
    await Future.any<void>([speech, _cancelled!.future]).timeout(
      ttsTimeout,
      onTimeout: () async {
        if (_isCurrent(generation)) await fallback.stop();
      },
    );
  }

  static void _trace(String message) {
    if (kDebugMode) debugPrint('[HOMI_AUDIO] $message');
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => _speak(text, locale: locale, route: LessonPlaybackRoute.phoneSpeaker);

  @override
  Future<void> stop() async {
    _generation++;
    _completeCancellation();
    final wasActive = _active;
    _active = false;
    if (wasActive) {
      await Future.wait<void>([mediaService.stopPlayback(), fallback.stop()]);
    }
  }

  void _completeCancellation() {
    final cancelled = _cancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    if (ownsFallback) await fallback.dispose();
    if (ownsMediaService) await mediaService.dispose();
  }

  @override
  Future<void> playSpeechReadyCue() async {
    if (fallback is SpeechReadyCuePlayer) {
      await (fallback as SpeechReadyCuePlayer).playSpeechReadyCue();
    }
  }

  @override
  Future<String?> beginMainTurn() async =>
      fallback is MainTurnVoicePromptService
      ? (fallback as MainTurnVoicePromptService).beginMainTurn()
      : null;

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    if (fallback is MainTurnVoicePromptService) {
      await (fallback as MainTurnVoicePromptService).endMainTurn(
        reason,
        turnId: turnId,
      );
    }
  }
}
