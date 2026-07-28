import 'dart:async';
import 'dart:typed_data';

import 'audio_input.dart';

/// Selects the preferred chunked input when it is available and otherwise
/// keeps the phone microphone as a safe fallback.
class PreferredAudioInput
    implements
        ChunkedAudioInput,
        BluetoothAudioInputControl,
        BluetoothCapturePolicy {
  PreferredAudioInput({
    required ChunkedAudioInput fallback,
    ChunkedAudioInput? preferred,
  }) : _fallback = fallback,
       _preferred = preferred;

  final ChunkedAudioInput _fallback;
  final ChunkedAudioInput? _preferred;
  final StreamController<Uint8List> _chunkController =
      StreamController<Uint8List>.broadcast(sync: true);

  ChunkedAudioInput? _active;
  StreamSubscription<Uint8List>? _chunkSubscription;
  bool _requireBluetoothOnce = false;

  ChunkedAudioInput get _candidate {
    final preferred = _preferred;
    return preferred != null && preferred.isAvailable ? preferred : _fallback;
  }

  ChunkedAudioInput get _current => _active ?? _candidate;

  BluetoothAudioInputControl? get _bluetoothControl {
    final preferred = _preferred;
    return preferred is BluetoothAudioInputControl
        ? preferred as BluetoothAudioInputControl
        : null;
  }

  @override
  String get label => _current.label;

  @override
  bool get isBluetooth => _current.isBluetooth;

  @override
  bool get isAvailable => _candidate.isAvailable;

  @override
  Stream<double> get amplitudeDbfs => _current.amplitudeDbfs;

  @override
  Stream<Uint8List> get audioChunks => _chunkController.stream;

  @override
  void requireBluetoothCaptureOnce() {
    _requireBluetoothOnce = true;
  }

  @override
  BluetoothAudioStatus get bluetoothStatus =>
      _bluetoothControl?.bluetoothStatus ??
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.unsupported,
      );

  @override
  Stream<BluetoothAudioStatus> get bluetoothStatusChanges =>
      _bluetoothControl?.bluetoothStatusChanges ??
      const Stream<BluetoothAudioStatus>.empty();

  @override
  Future<void> initializeBluetooth() async {
    await _bluetoothControl?.initializeBluetooth();
  }

  @override
  Future<List<BluetoothAudioDevice>> scanBluetoothDevices() async {
    return await _bluetoothControl?.scanBluetoothDevices() ??
        const <BluetoothAudioDevice>[];
  }

  @override
  Future<void> connectBluetoothDevice(String deviceId) async {
    final control = _bluetoothControl;
    if (control == null) {
      throw StateError('Bluetooth audio input is not configured.');
    }
    await control.connectBluetoothDevice(deviceId);
  }

  @override
  Future<void> disconnectBluetoothDevice() async {
    await _bluetoothControl?.disconnectBluetoothDevice();
  }

  @override
  Future<void> start() async {
    final requiresBluetooth = _requireBluetoothOnce;
    _requireBluetoothOnce = false;
    _active = requiresBluetooth ? _requiredPreferred() : _candidate;
    try {
      await _active!.start();
    } catch (_) {
      if (requiresBluetooth ||
          !identical(_active, _preferred) ||
          !_fallback.isAvailable) {
        _active = null;
        rethrow;
      }
      _active = _fallback;
      await _fallback.start();
    }
  }

  @override
  Future<void> startChunked() async {
    final requiresBluetooth = _requireBluetoothOnce;
    _requireBluetoothOnce = false;
    _active = requiresBluetooth ? _requiredPreferred() : _candidate;
    await _listenToActiveChunks();
    try {
      await _active!.startChunked();
    } catch (_) {
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      if (requiresBluetooth ||
          !identical(_active, _preferred) ||
          !_fallback.isAvailable) {
        _active = null;
        rethrow;
      }
      await _active!.cancel().catchError((Object _) {});
      _active = _fallback;
      await _listenToActiveChunks();
      await _fallback.startChunked();
    }
  }

  ChunkedAudioInput _requiredPreferred() {
    final preferred = _preferred;
    if (preferred == null || !preferred.isAvailable) {
      throw StateError('Mic Bluetooth chưa kết nối hoặc chưa sẵn sàng.');
    }
    return preferred;
  }

  Future<void> _listenToActiveChunks() async {
    await _chunkSubscription?.cancel();
    _chunkSubscription = _active!.audioChunks.listen(
      _chunkController.add,
      onError: _chunkController.addError,
    );
  }

  @override
  Future<AudioCapture> stop() async {
    final active = _active ?? _candidate;
    try {
      return await active.stop();
    } finally {
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      _active = null;
    }
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    await _chunkSubscription?.cancel();
    _chunkSubscription = null;
    _active = null;
    await active?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _chunkSubscription?.cancel();
    await _chunkController.close();
    await _preferred?.dispose();
    await _fallback.dispose();
  }
}
