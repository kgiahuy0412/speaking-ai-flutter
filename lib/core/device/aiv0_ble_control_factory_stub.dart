import 'aiv0_ble_control.dart';

Aiv0BleControl createPlatformAiv0BleControl({
  required bool enabled,
  required bool draftProtocolConfirmed,
}) {
  return MethodChannelAiv0BleControl(
    enabled: enabled,
    draftProtocolConfirmed: draftProtocolConfirmed,
  );
}
