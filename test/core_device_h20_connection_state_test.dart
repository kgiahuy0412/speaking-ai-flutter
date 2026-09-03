import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/h20_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hfpReady = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    routeActive: true,
  );
  const hfpMissing = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
  );
  const hfpSelectedButIdle = BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
    deviceId: 'h20-hfp',
    deviceName: 'H20',
  );
  const bleReady = Aiv0BleStatus(
    phase: Aiv0BlePhase.connected,
    protocolConfirmed: false,
  );
  const bleMissing = Aiv0BleStatus(
    phase: Aiv0BlePhase.idle,
    protocolConfirmed: false,
  );

  test('requires both transports before reporting H20 ready', () {
    expect(
      H20ConnectionState.from(hfpStatus: hfpReady, bleStatus: bleMissing).phase,
      H20ConnectionPhase.hfpReady,
    );
    expect(
      H20ConnectionState.from(hfpStatus: hfpMissing, bleStatus: bleReady).phase,
      H20ConnectionPhase.bleReady,
    );
    expect(
      H20ConnectionState.from(hfpStatus: hfpReady, bleStatus: bleReady).phase,
      H20ConnectionPhase.h20Ready,
    );
  });

  test('keeps HFP ownership visible while a MAIN turn is active', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpReady,
      bleStatus: bleMissing,
      mainTurnActive: true,
    );

    expect(state.phase, H20ConnectionPhase.mainTurnActive);
    expect(state.hfpReady, isTrue);
    expect(state.bleReady, isFalse);
  });

  test('allows MAIN to activate a selected but currently idle HFP route', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpSelectedButIdle,
      bleStatus: bleReady,
    );

    expect(state.phase, H20ConnectionPhase.bleReady);
    expect(state.hfpSelected, isTrue);
    expect(state.hfpReady, isFalse);
    expect(state.canStartStrictHfpTurn, isTrue);
  });

  test('does not start strict HFP turn without a selected HFP input', () {
    final state = H20ConnectionState.from(
      hfpStatus: hfpMissing,
      bleStatus: bleReady,
    );

    expect(state.hfpSelected, isFalse);
    expect(state.canStartStrictHfpTurn, isFalse);
  });
}
