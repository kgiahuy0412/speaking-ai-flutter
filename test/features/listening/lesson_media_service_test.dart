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
}

class _ControlledPlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

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
