import 'dart:async';

import 'package:flutter/foundation.dart';

enum MainSpeakingSessionState {
  inactive,
  ready,
  recording,
  processing,
  playing,
}

enum MainSpeakingNoSpeechAction { retry, exit }

/// Tracks the context-sensitive Main button while the child practices speech.
///
/// The ten-second timeout only runs while Main is waiting to start a new turn.
/// Recording, translation and result playback always suspend the timeout.
class MainSpeakingSessionController extends ChangeNotifier {
  MainSpeakingSessionController({
    this.idleTimeout = const Duration(seconds: 10),
  });

  final Duration idleTimeout;

  Timer? _idleTimer;
  MainSpeakingSessionState _state = MainSpeakingSessionState.inactive;
  int _consecutiveNoSpeechTurns = 0;
  bool _disposed = false;

  MainSpeakingSessionState get state => _state;
  bool get isActive => _state != MainSpeakingSessionState.inactive;
  bool get isReady => _state == MainSpeakingSessionState.ready;
  int get consecutiveNoSpeechTurns => _consecutiveNoSpeechTurns;

  void enter() {
    if (_disposed) {
      return;
    }
    _consecutiveNoSpeechTurns = 0;
    _setState(MainSpeakingSessionState.ready, restartReadyTimeout: true);
  }

  void exit() {
    if (_disposed) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = null;
    _consecutiveNoSpeechTurns = 0;
    _setState(MainSpeakingSessionState.inactive);
  }

  /// The first silent continuous turn gets one child-friendly retry. A second
  /// consecutive silent turn exits the hands-free session.
  MainSpeakingNoSpeechAction registerNoSpeechTurn() {
    if (_disposed || !isActive) {
      return MainSpeakingNoSpeechAction.exit;
    }
    _consecutiveNoSpeechTurns += 1;
    return _consecutiveNoSpeechTurns == 1
        ? MainSpeakingNoSpeechAction.retry
        : MainSpeakingNoSpeechAction.exit;
  }

  void markSpeechTurnCompleted() {
    _consecutiveNoSpeechTurns = 0;
  }

  void synchronize({
    required bool isRecording,
    required bool isBusy,
    required bool isPlaying,
  }) {
    if (_disposed || !isActive) {
      return;
    }
    final nextState = isRecording
        ? MainSpeakingSessionState.recording
        : isPlaying
        ? MainSpeakingSessionState.playing
        : isBusy
        ? MainSpeakingSessionState.processing
        : MainSpeakingSessionState.ready;
    if (nextState == _state) {
      return;
    }
    _setState(
      nextState,
      restartReadyTimeout: nextState == MainSpeakingSessionState.ready,
    );
  }

  void _setState(
    MainSpeakingSessionState nextState, {
    bool restartReadyTimeout = false,
  }) {
    if (_state == nextState && !restartReadyTimeout) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = null;
    _state = nextState;
    if (restartReadyTimeout && nextState == MainSpeakingSessionState.ready) {
      _idleTimer = Timer(idleTimeout, () {
        _idleTimer = null;
        if (_disposed || _state != MainSpeakingSessionState.ready) {
          return;
        }
        _state = MainSpeakingSessionState.inactive;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    super.dispose();
  }
}
