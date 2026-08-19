import 'aiv0_ble_control.dart';
import 'aiv0_ble_control_factory_stub.dart'
    if (dart.library.js_interop) 'aiv0_ble_control_factory_web.dart'
    as platform;

Aiv0BleControl createAiv0BleControl({
  required bool enabled,
  required bool draftProtocolConfirmed,
}) {
  return platform.createPlatformAiv0BleControl(
    enabled: enabled,
    draftProtocolConfirmed: draftProtocolConfirmed,
  );
}
