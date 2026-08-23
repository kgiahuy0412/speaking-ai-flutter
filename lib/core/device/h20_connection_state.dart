import '../audio/audio_input.dart';
import 'aiv0_ble_control.dart';

enum H20ConnectionPhase {
  disconnected,
  hfpReady,
  bleReady,
  h20Ready,
  mainTurnActive,
}

/// One app-level view of H20 readiness across its independent HFP and BLE
/// transports. Neither link alone is reported as a fully ready H20.
class H20ConnectionState {
  const H20ConnectionState({
    required this.phase,
    required this.hfpSelected,
    required this.hfpReady,
    required this.bleReady,
  });

  factory H20ConnectionState.from({
    required BluetoothAudioStatus hfpStatus,
    required Aiv0BleStatus bleStatus,
    bool mainTurnActive = false,
  }) {
    final hfpSelected = hfpStatus.deviceId != null;
    final hfpReady = hfpStatus.isConnected && hfpStatus.routeActive;
    final bleReady = bleStatus.isConnected;
    final phase = mainTurnActive && hfpReady
        ? H20ConnectionPhase.mainTurnActive
        : hfpReady && bleReady
        ? H20ConnectionPhase.h20Ready
        : hfpReady
        ? H20ConnectionPhase.hfpReady
        : bleReady
        ? H20ConnectionPhase.bleReady
        : H20ConnectionPhase.disconnected;
    return H20ConnectionState(
      phase: phase,
      hfpSelected: hfpSelected,
      hfpReady: hfpReady,
      bleReady: bleReady,
    );
  }

  final H20ConnectionPhase phase;
  final bool hfpSelected;
  final bool hfpReady;
  final bool bleReady;

  bool get isH20Ready => hfpReady && bleReady;

  /// Whether a physical H20 MAIN press may start the strict HFP turn.
  ///
  /// An idle iOS audio session normally exposes the paired headset as A2DP,
  /// so [hfpReady] can be false until recording starts. Requiring an already
  /// active HFP/SCO route here creates a circular dependency: the MAIN turn is
  /// what asks iOS to activate that route. A persisted HFP selection plus the
  /// live BLE control link is sufficient to let the speech input activate and
  /// authoritatively verify HFP. Failure to activate remains an error; callers
  /// must not fall back to the phone microphone in the same turn.
  bool get canStartStrictHfpTurn => hfpSelected && bleReady;
}
