import '../core/audio/audio_turn_coordinator.dart';
import 'device_connection_feedback_overlay.dart';

/// Keeps transient BLE recovery UI out of an active HOMI audio turn.
///
/// Some headset firmware briefly reports BLE reconnecting while HFP/SCO owns
/// the radio. The BLE layer must continue recovering, but showing that native
/// transition while HOMI is speaking makes a healthy audio turn look broken.
class DeviceConnectionFeedbackGate {
  bool _connectingDeferred = false;

  bool get hasDeferredConnecting => _connectingDeferred;

  bool isPlaybackActive({
    required AudioTurnMode? currentMode,
    required bool conversationPlaybackActive,
    required bool mainSpeakingPlaybackActive,
  }) {
    return currentMode == AudioTurnMode.promptPlayback ||
        currentMode == AudioTurnMode.mediaPlayback ||
        conversationPlaybackActive ||
        mainSpeakingPlaybackActive;
  }

  bool shouldPresent(
    DeviceConnectionFeedbackStage stage, {
    required bool playbackActive,
  }) {
    if (!playbackActive) {
      if (stage == DeviceConnectionFeedbackStage.connected) {
        _connectingDeferred = false;
      }
      return true;
    }
    _connectingDeferred = stage == DeviceConnectionFeedbackStage.connecting;
    return false;
  }

  bool consumeDeferredConnecting({
    required bool playbackActive,
    required bool bleConnecting,
  }) {
    if (playbackActive || !_connectingDeferred) {
      return false;
    }
    _connectingDeferred = false;
    return bleConnecting;
  }

  void clear() {
    _connectingDeferred = false;
  }
}
