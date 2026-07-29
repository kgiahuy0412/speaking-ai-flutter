import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'playToCompletion does not finish until playback reports ended',
    () async {
      final playback = _ControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a temporary playing false state',
    () async {
      final playback = _CompletionAwareControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/next-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      playback.pauseTemporarily();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      playback.resume();
      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a completed state from the old source',
    () async {
      final playback = _StaleCompletionPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/new-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );
}

class _ControlledPlaybackService implements AudioPlaybackService {
  _ControlledPlaybackService({this.finishInsidePlay = false});

  final bool finishInsidePlay;
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    if (finishInsidePlay) {
      _playing.add(false);
      await Future<void>.delayed(Duration.zero);
    }
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() => _playing.add(false);

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() => _playing.close();
}

class _CompletionAwareControlledPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void pauseTemporarily() => _playing.add(false);

  void resume() => _playing.add(true);

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}

class _StaleCompletionPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  _StaleCompletionPlaybackService() {
    _completed = StreamController<void>.broadcast(
      sync: true,
      onListen: () {
        final subscribedBeforeNewSourceStarted = playCalls == 0;
        if (subscribedBeforeNewSourceStarted) {
          scheduleMicrotask(() => _completed.add(null));
        }
      },
    );
  }

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  late final StreamController<void> _completed;
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}
