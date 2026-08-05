import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('does not accept a stale completed state before the source end', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 1600),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: true,
      ),
      isFalse,
    );
  });

  test('does not accept old end position immediately after a new start', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 11700),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: false,
      ),
      isFalse,
    );
  });

  test('accepts completion when the current source reaches its end', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 11600),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: true,
      ),
      isTrue,
    );
  });
}
