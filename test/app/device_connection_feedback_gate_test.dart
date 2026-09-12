import 'package:ai_speaking_flutter_app/app/device_connection_feedback_gate.dart';
import 'package:ai_speaking_flutter_app/app/device_connection_feedback_overlay.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defers BLE connecting feedback during HOMI prompt playback', () {
    final gate = DeviceConnectionFeedbackGate();

    final playbackActive = gate.isPlaybackActive(
      currentMode: AudioTurnMode.promptPlayback,
      conversationPlaybackActive: false,
      mainSpeakingPlaybackActive: false,
    );

    expect(
      gate.shouldPresent(
        DeviceConnectionFeedbackStage.connecting,
        playbackActive: playbackActive,
      ),
      isFalse,
    );
    expect(gate.hasDeferredConnecting, isTrue);
  });

  test('shows deferred feedback only if BLE is still reconnecting', () {
    final gate = DeviceConnectionFeedbackGate();
    gate.shouldPresent(
      DeviceConnectionFeedbackStage.connecting,
      playbackActive: true,
    );

    expect(
      gate.consumeDeferredConnecting(
        playbackActive: false,
        bleConnecting: true,
      ),
      isTrue,
    );
    expect(gate.hasDeferredConnecting, isFalse);

    gate.shouldPresent(
      DeviceConnectionFeedbackStage.connecting,
      playbackActive: true,
    );
    expect(
      gate.consumeDeferredConnecting(
        playbackActive: false,
        bleConnecting: false,
      ),
      isFalse,
    );
    expect(gate.hasDeferredConnecting, isFalse);
  });

  test('media playback and controller playback both suppress feedback', () {
    final gate = DeviceConnectionFeedbackGate();

    expect(
      gate.isPlaybackActive(
        currentMode: AudioTurnMode.mediaPlayback,
        conversationPlaybackActive: false,
        mainSpeakingPlaybackActive: false,
      ),
      isTrue,
    );
    expect(
      gate.isPlaybackActive(
        currentMode: null,
        conversationPlaybackActive: true,
        mainSpeakingPlaybackActive: false,
      ),
      isTrue,
    );
  });

  test('successful reconnect during playback clears deferred feedback', () {
    final gate = DeviceConnectionFeedbackGate();
    gate.shouldPresent(
      DeviceConnectionFeedbackStage.connecting,
      playbackActive: true,
    );

    expect(
      gate.shouldPresent(
        DeviceConnectionFeedbackStage.connected,
        playbackActive: true,
      ),
      isFalse,
    );
    expect(gate.hasDeferredConnecting, isFalse);
  });
}
