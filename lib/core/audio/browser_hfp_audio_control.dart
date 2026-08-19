import 'dart:async';

import 'audio_input.dart';
import 'hfp_audio_control.dart';

/// Selects a browser-visible Bluetooth headset microphone.
///
/// Web Bluetooth cannot control the Bluetooth Classic HFP profile. The
/// headset must already be connected in the operating system, after which the
/// browser may expose its microphone through MediaDevices/getUserMedia.
class BrowserHfpAudioControl implements HfpAudioControl {
  BrowserHfpAudioControl({
    required this.enabled,
    required SelectableAudioInputControl audioInput,
  }) : _audioInput = audioInput;

  final bool enabled;
  final SelectableAudioInputControl _audioInput;
  final StreamController<BluetoothAudioStatus> _statusController =
      StreamController<BluetoothAudioStatus>.broadcast();

  BluetoothAudioStatus _status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
    sampleRate: 16000,
  );
  bool _disposed = false;
  bool _initialized = false;

  @override
  bool get usesBrowserAudioInput => true;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _statusController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    if (!enabled) {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.disabled,
          message: 'HFP Web đang tắt trong cấu hình bản build.',
          sampleRate: 16000,
        ),
      );
      return;
    }
    _setStatus(
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.idle,
        message: 'Kết nối tai nghe trong hệ điều hành rồi chọn mic trên Web.',
        sampleRate: 16000,
      ),
    );
  }

  @override
  Future<List<HfpAudioDevice>> findDevices() async {
    await initialize();
    _requireSupport();
    _setStatus(
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.scanning,
        message: 'Đang kiểm tra các mic mà trình duyệt cho phép sử dụng…',
        sampleRate: 16000,
      ),
    );
    try {
      final selectedId = _audioInput.selectedAudioInputDevice?.id;
      final inputs = await _audioInput.listAudioInputDevices();
      final devices =
          inputs
              .where((device) => isLikelyBrowserHfpLabel(device.displayName))
              .map(
                (device) => HfpAudioDevice(
                  id: device.id,
                  name: device.displayName,
                  isConnected: device.id == selectedId,
                ),
              )
              .toList(growable: false)
            ..sort((a, b) {
              if (a.isConnected != b.isConnected) {
                return a.isConnected ? -1 : 1;
              }
              return a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
            });
      final selected = _audioInput.selectedAudioInputDevice;
      if (selected != null) {
        _setReady(selected);
      } else {
        _setStatus(
          BluetoothAudioStatus(
            phase: BluetoothAudioConnectionPhase.idle,
            message: devices.isEmpty
                ? 'Trình duyệt chưa hiển thị mic Bluetooth. Hãy kết nối tai nghe trong Cài đặt hệ thống rồi thử lại.'
                : 'Chọn mic của tai nghe Bluetooth để dùng HFP Web.',
            sampleRate: 16000,
          ),
        );
      }
      return devices;
    } catch (error) {
      _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> connect(HfpAudioDevice device) async {
    await initialize();
    _requireSupport();
    _setStatus(
      BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.connecting,
        deviceId: device.id,
        deviceName: device.displayName,
        message: 'Đang chọn mic Bluetooth trong trình duyệt…',
        sampleRate: 16000,
      ),
    );
    try {
      await _audioInput.selectAudioInputDevice(
        SelectableAudioInputDevice(id: device.id, label: device.displayName),
      );
      final selected = _audioInput.selectedAudioInputDevice;
      if (selected == null || selected.id != device.id) {
        throw const HfpAudioException(
          'Trình duyệt không thể chọn mic Bluetooth này.',
        );
      }
      _setReady(selected);
    } catch (error) {
      _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          deviceId: device.id,
          deviceName: device.displayName,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _audioInput.selectAudioInputDevice(null);
    _setStatus(
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.idle,
        message: 'Đã trở về mic mặc định của trình duyệt.',
        sampleRate: 16000,
      ),
    );
  }

  @override
  Future<void> startAudioRoute() async {
    await initialize();
    _requireSupport();
    final selected = _audioInput.selectedAudioInputDevice;
    if (selected == null) {
      throw const HfpAudioException(
        'Hãy chọn mic Bluetooth trước khi bắt đầu nói.',
      );
    }
    _setStatus(
      BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.recording,
        deviceId: selected.id,
        deviceName: selected.displayName,
        message: 'Đang ghi âm từ mic Bluetooth do trình duyệt cung cấp.',
        sampleRate: 16000,
      ),
    );
  }

  @override
  Future<void> stopAudioRoute() async {
    final selected = _audioInput.selectedAudioInputDevice;
    if (selected != null) {
      _setReady(selected);
    }
  }

  void _setReady(SelectableAudioInputDevice selected) {
    _setStatus(
      BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: selected.id,
        deviceName: selected.displayName,
        message: 'Mic Bluetooth đã được chọn cho phiên Web này.',
        sampleRate: 16000,
      ),
    );
  }

  void _requireSupport() {
    if (!_status.isBridgeSupported) {
      throw HfpAudioException(
        _status.message ?? 'Trình duyệt này không hỗ trợ chọn mic HFP.',
      );
    }
  }

  void _setStatus(BluetoothAudioStatus status) {
    if (_disposed) {
      return;
    }
    _status = status;
    _statusController.add(status);
  }

  String _friendlyError(Object error) {
    if (error is HfpAudioException) {
      return error.message;
    }
    return '$error';
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await _audioInput.selectAudioInputDevice(null);
    _disposed = true;
    await _statusController.close();
  }
}

bool isLikelyBrowserHfpLabel(String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(
    r'bluetooth|hfp|hands[ -]?free|headset|headphone|earbud|airpods|buds|beats|bose|jabra|freebuds|galaxy buds|pixel buds|sony w[fh]-|qcy|plantronics|poly|innotrik|\bh[ -]?20\b|bt audio|tai nghe|蓝牙|耳机',
    caseSensitive: false,
  ).hasMatch(normalized);
}
