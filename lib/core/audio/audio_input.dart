import 'dart:typed_data';

class AudioCapture {
  const AudioCapture({
    required this.filePath,
    required this.mimeType,
    required this.duration,
    required this.inputLabel,
    required this.isBluetoothInput,
    required this.initialNoiseRms,
    this.streamHeaderBytes,
    this.streamedAudioBytes,
    this.recordingSampleRate,
    this.dataBytes,
  });

  final String filePath;
  final String mimeType;
  final Duration duration;
  final String inputLabel;
  final bool isBluetoothInput;
  final double? initialNoiseRms;
  final Uint8List? streamHeaderBytes;
  final int? streamedAudioBytes;
  final int? recordingSampleRate;

  /// In-memory payload used by Flutter Web, where a native file path is not
  /// available. Native platforms may also provide it for a retry upload.
  final Uint8List? dataBytes;
}

abstract interface class AudioInput {
  String get label;
  bool get isBluetooth;
  bool get isAvailable;
  Stream<double> get amplitudeDbfs;

  Future<void> start();
  Future<AudioCapture> stop();
  Future<void> cancel();
  Future<void> dispose();
}

abstract interface class ChunkedAudioInput implements AudioInput {
  Stream<Uint8List> get audioChunks;

  Future<void> startChunked();
}

enum BluetoothAudioConnectionPhase {
  disabled,
  unsupported,
  idle,
  permissionRequired,
  scanning,
  connecting,
  discovering,
  ready,
  recording,
  error,
}

class BluetoothAudioDevice {
  const BluetoothAudioDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isLikelyInnotrik,
  });

  factory BluetoothAudioDevice.fromJson(Map<dynamic, dynamic> json) {
    return BluetoothAudioDevice(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}'.trim(),
      rssi: (json['rssi'] as num?)?.toInt() ?? -127,
      isLikelyInnotrik: json['isLikelyInnotrik'] == true,
    );
  }

  final String id;
  final String name;
  final int rssi;
  final bool isLikelyInnotrik;

  String get displayName => name.isEmpty ? id : name;
}

class BluetoothAudioStatus {
  const BluetoothAudioStatus({
    required this.phase,
    this.deviceId,
    this.deviceName,
    this.message,
    this.packetCount = 0,
    this.invalidPacketCount = 0,
    this.decodedPcmBytes = 0,
    this.sampleRate = 24000,
  });

  final BluetoothAudioConnectionPhase phase;
  final String? deviceId;
  final String? deviceName;
  final String? message;
  final int packetCount;
  final int invalidPacketCount;
  final int decodedPcmBytes;
  final int sampleRate;

  bool get isBridgeSupported =>
      phase != BluetoothAudioConnectionPhase.disabled &&
      phase != BluetoothAudioConnectionPhase.unsupported;

  bool get isConnected =>
      phase == BluetoothAudioConnectionPhase.ready ||
      phase == BluetoothAudioConnectionPhase.recording;

  bool get isBusy =>
      phase == BluetoothAudioConnectionPhase.scanning ||
      phase == BluetoothAudioConnectionPhase.connecting ||
      phase == BluetoothAudioConnectionPhase.discovering;
}

/// Optional control surface implemented by custom Bluetooth audio inputs.
///
/// Keeping this separate from [AudioInput] lets the phone microphone and web
/// implementations remain simple while settings can still manage a physical
/// INNOTRIK device explicitly.
abstract interface class BluetoothAudioInputControl {
  BluetoothAudioStatus get bluetoothStatus;
  Stream<BluetoothAudioStatus> get bluetoothStatusChanges;

  Future<void> initializeBluetooth();
  Future<List<BluetoothAudioDevice>> scanBluetoothDevices();
  Future<void> connectBluetoothDevice(String deviceId);
  Future<void> disconnectBluetoothDevice();
}

/// Lets a coordinator explicitly prevent a custom BLE capture from silently
/// falling back to the phone microphone for one recording attempt.
abstract interface class BluetoothCapturePolicy {
  void requireBluetoothCaptureOnce();
}
