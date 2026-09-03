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

  test('armed listener replaces the previous source duration', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 1200),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 1200),
        duration: const Duration(milliseconds: 1200),
      ),
      isTrue,
    );
  });

  test('stale completed state cannot finish an armed listener', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 2600),
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
  });

  test('accepts completed before the final position event arrives', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 1200),
      ),
      isFalse,
    );

    // On iOS the completed state can win the scheduling race against the final
    // position update. There is no second player-state event after this one.
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 850),
        duration: const Duration(milliseconds: 1200),
      ),
      isTrue,
    );
  });
}
