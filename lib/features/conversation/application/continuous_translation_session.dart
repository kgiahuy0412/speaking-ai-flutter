import '../domain/conversation_models.dart';

/// Narrow runtime boundary used by [ContinuousTranslationSession].
///
/// Capture, ASR, backend fallback, and playback implementations stay behind
/// this port. The presentation controller remains a compatibility facade while
/// the session owns user-turn serialization and push-to-talk interaction.
abstract interface class ContinuousTranslationRuntime {
  ConversationPhase get phase;
  bool get isBusy;

  Future<void> unlockPlaybackForUserGesture();

  Future<void> startTurn({
    required Duration noSpeechTimeout,
    required bool speakNoSpeechPrompt,
    required bool stopOnSilence,
  });

  Future<void> stopTurn({required bool manual});

  Future<void> playResult({
    required bool reportLatency,
    required bool propagateFailure,
  });
}

/// Owns the interaction state of continuous Vietnamese-to-English turns.
///
/// This is deliberately independent from listening lessons and MAIN
/// navigation. Existing capture and translation behavior is invoked through
/// [ContinuousTranslationRuntime], so this extraction does not add a backend
/// request or alter the online/offline decision tree.
class ContinuousTranslationSession {
  ContinuousTranslationSession({required ContinuousTranslationRuntime runtime})
    : _runtime = runtime;

  final ContinuousTranslationRuntime _runtime;
  Future<void>? _recordingStartOperation;
  bool _pushToTalkPressed = false;
  bool _disposed = false;

  bool get isRecordingStartPending => _recordingStartOperation != null;
  Future<void>? get pendingRecordingStart => _recordingStartOperation;

  Future<void> onPrimaryAction() async {
    if (_disposed) return;
    if (_runtime.phase == ConversationPhase.recording) {
      await _runtime.unlockPlaybackForUserGesture();
      await stopRecording(manual: true);
      return;
    }
    if (_runtime.phase == ConversationPhase.processing) {
      return;
    }
    await startRecording();
  }

  Future<void> startRecording({
    Duration noSpeechTimeout = const Duration(seconds: 3),
    bool speakNoSpeechPrompt = true,
    bool stopOnSilence = true,
  }) {
    if (_disposed) return Future<void>.value();
    final pending = _recordingStartOperation;
    if (pending != null) return pending;

    // Invoke the legacy runtime before publishing the pending marker. This
    // preserves the existing synchronous entry behavior: startTurn can inspect
    // the controller's busy state without seeing its own operation as a block.
    late final Future<void> tracked;
    tracked = _runtime
        .startTurn(
          noSpeechTimeout: noSpeechTimeout,
          speakNoSpeechPrompt: speakNoSpeechPrompt,
          stopOnSilence: stopOnSilence,
        )
        .whenComplete(() {
          if (identical(_recordingStartOperation, tracked)) {
            _recordingStartOperation = null;
          }
        });
    _recordingStartOperation = tracked;
    return tracked;
  }

  Future<void> stopRecording({required bool manual}) async {
    if (_disposed) return;
    _pushToTalkPressed = false;
    await _runtime.stopTurn(manual: manual);
  }

  Future<void> startPushToTalk() async {
    if (_disposed || _pushToTalkPressed || _runtime.isBusy) {
      return;
    }
    _pushToTalkPressed = true;
    await startRecording(
      noSpeechTimeout: const Duration(seconds: 12),
      stopOnSilence: false,
    );
    if (_disposed) return;
    if (_runtime.phase == ConversationPhase.recording && !_pushToTalkPressed) {
      await stopRecording(manual: true);
    } else if (_runtime.phase != ConversationPhase.recording) {
      _pushToTalkPressed = false;
    }
  }

  Future<void> stopPushToTalk() async {
    if (_disposed || !_pushToTalkPressed) {
      return;
    }
    _pushToTalkPressed = false;
    if (_runtime.phase == ConversationPhase.recording) {
      await stopRecording(manual: true);
    }
  }

  Future<void> playResult({
    bool reportLatency = false,
    bool propagateFailure = false,
  }) {
    if (_disposed) return Future<void>.value();
    return _runtime.playResult(
      reportLatency: reportLatency,
      propagateFailure: propagateFailure,
    );
  }

  /// Clears gesture state at a MAIN or lifecycle cancellation boundary.
  ///
  /// The pending start future remains observable until its runtime cleanup
  /// finishes, allowing the controller to retain its existing cancellation
  /// barrier.
  void cancelInteraction() {
    _pushToTalkPressed = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelInteraction();
  }
}
