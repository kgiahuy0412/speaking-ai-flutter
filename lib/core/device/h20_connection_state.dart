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
    required this.hfpReady,
    required this.bleReady,
  });

  factory H20ConnectionState.from({
    required BluetoothAudioStatus hfpStatus,
    required Aiv0BleStatus bleStatus,
    bool mainTurnActive = false,
  }) {
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
      hfpReady: hfpReady,
      bleReady: bleReady,
    );
  }

  final H20ConnectionPhase phase;
  final bool hfpReady;
  final bool bleReady;

  bool get isH20Ready => hfpReady && bleReady;
}
