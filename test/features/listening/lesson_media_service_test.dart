import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playToCompletion waits until playback reports its ending', () async {
    final playback = _CompletingPlaybackService();
    final mediaService = LessonMediaService(playbackService: playback);
    final uri = Uri.parse('asset:///assets/audio/GUIDE_RECORD/record.mp3');

    await mediaService.playToCompletion(uri);

    expect(playback.playedUris, <Uri>[uri]);
    expect(playback.events, <String>['play', 'started', 'ended']);
    await mediaService.dispose();
  });
}

class _CompletingPlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final List<Uri> playedUris = <Uri>[];
  final List<String> events = <String>[];

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playedUris.add(uri);
    events.add('play');
    _playingController.add(true);
    await Future<void>.delayed(Duration.zero);
    events.add('started');
    _playingController.add(false);
    events.add('ended');
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> dispose() => _playingController.close();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async {
    _playingController.add(false);
  }
}
