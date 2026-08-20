import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/browser_hfp_audio_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes common browser Bluetooth microphone labels', () {
    expect(isLikelyBrowserHfpLabel('AirPods Microphone'), isTrue);
    expect(isLikelyBrowserHfpLabel('INNOTRIK'), isTrue);
    expect(
      isLikelyBrowserHfpLabel('Headset (WH-1000XM5 Hands-Free AG Audio)'),
      isTrue,
    );
    expect(isLikelyBrowserHfpLabel('iPhone Microphone'), isFalse);
    expect(isLikelyBrowserHfpLabel('Default - Microphone Array'), isFalse);
  });

  test(
    'lists, selects, routes and releases a browser HFP microphone',
    () async {
      final input = _FakeSelectableAudioInput(<SelectableAudioInputDevice>[
        const SelectableAudioInputDevice(
          id: 'phone',
          label: 'iPhone Microphone',
        ),
        const SelectableAudioInputDevice(
          id: 'airpods',
          label: 'AirPods Microphone',
        ),
      ]);
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);

      await control.initialize();
      final devices = await control.findDevices();
      expect(devices, hasLength(1));
      expect(devices.single.id, 'airpods');

      await control.connect(devices.single);
      expect(input.selectedAudioInputDevice?.id, 'airpods');
      expect(control.status.phase, BluetoothAudioConnectionPhase.ready);

      await control.startAudioRoute();
      expect(control.status.phase, BluetoothAudioConnectionPhase.recording);
      await control.stopAudioRoute();
      expect(control.status.phase, BluetoothAudioConnectionPhase.ready);

      await control.disconnect();
      expect(input.selectedAudioInputDevice, isNull);
      expect(control.status.phase, BluetoothAudioConnectionPhase.idle);
      await control.dispose();
    },
  );

  test(
    'does not claim HFP when the browser only exposes the phone mic',
    () async {
      final input = _FakeSelectableAudioInput(<SelectableAudioInputDevice>[
        const SelectableAudioInputDevice(
          id: 'phone',
          label: 'iPhone Microphone',
        ),
      ]);
      final control = BrowserHfpAudioControl(enabled: true, audioInput: input);

      expect(await control.findDevices(), isEmpty);
      expect(control.status.phase, BluetoothAudioConnectionPhase.idle);
      expect(control.status.message, contains('chưa hiển thị mic Bluetooth'));
      await control.dispose();
    },
  );
}

class _FakeSelectableAudioInput implements SelectableAudioInputControl {
  _FakeSelectableAudioInput(this.devices);

  final List<SelectableAudioInputDevice> devices;

  @override
  SelectableAudioInputDevice? selectedAudioInputDevice;

  @override
  Future<List<SelectableAudioInputDevice>> listAudioInputDevices() async =>
      devices;

  @override
  Future<void> selectAudioInputDevice(
    SelectableAudioInputDevice? device,
  ) async {
    selectedAudioInputDevice = device;
  }
}
