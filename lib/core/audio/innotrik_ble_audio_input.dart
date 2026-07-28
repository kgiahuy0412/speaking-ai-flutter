import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'audio_input.dart';
import 'recording_storage.dart';
import 'wav_audio.dart';

/// Android BLE input for the INNOTRIK wearable microphone.
///
/// Android owns GATT framing and raw Opus decoding. Dart only receives mono
/// PCM16 at 24 kHz, which is the same contract used by phone-microphone
/// Realtime and Batch Chunks. This prevents raw vendor packets from being
/// mislabeled as playable audio.
class InnotrikBleAudioInput
    implements ChunkedAudioInput, BluetoothAudioInputControl {
  InnotrikBleAudioInput({
    required this.enabled,
    MethodChannel controlChannel = const MethodChannel('ailingo_innotrik_ble'),
    EventChannel eventChannel = const EventChannel(
      'ailingo_innotrik_ble/events',
    ),
    BasicMessageChannel<ByteData?> pcmChannel =
        const BasicMessageChannel<ByteData?>(
          'ailingo_innotrik_ble/pcm',
          BinaryCodec(),
        ),
  }) : _controlChannel = controlChannel,
       _eventChannel = eventChannel,
       _pcmChannel = pcmChannel,
       _status = BluetoothAudioStatus(
         phase: enabled
             ? BluetoothAudioConnectionPhase.idle
             : BluetoothAudioConnectionPhase.disabled,
       );

  final bool enabled;
  final MethodChannel _controlChannel;
  final EventChannel _eventChannel;
  final BasicMessageChannel<ByteData?> _pcmChannel;
  final StreamController<Uint8List> _audioChunkController =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast(sync: true);
  final StreamController<BluetoothAudioStatus> _statusController =
      StreamController<BluetoothAudioStatus>.broadcast(sync: true);

  BluetoothAudioStatus _status;
  StreamSubscription<dynamic>? _eventSubscription;
  Future<void>? _initialization;
  BytesBuilder? _pcmBytes;
  BytesBuilder? _pendingChunkBytes;
  DateTime? _startedAt;
  String? _currentPath;
  double? _initialNoiseRms;
  bool _capturing = false;
  bool _disposed = false;

  int get _sampleRate => _status.sampleRate > 0 ? _status.sampleRate : 24000;

  int get _chunkByteLength => pcm16ChunkByteLength(sampleRate: _sampleRate);

  @override
  String get label {
    final name = _status.deviceName?.trim();
    return name == null || name.isEmpty
        ? 'Mic INNOTRIK'
        : 'Mic INNOTRIK • $name';
  }

  @override
  bool get isBluetooth => true;

  @override
  bool get isAvailable => enabled && _status.isConnected;

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<Uint8List> get audioChunks => _audioChunkController.stream;

  @override
  BluetoothAudioStatus get bluetoothStatus => _status;

  @override
  Stream<BluetoothAudioStatus> get bluetoothStatusChanges =>
      _statusController.stream;

  @override
  Future<void> initializeBluetooth() {
    if (!enabled) {
      return Future<void>.value();
    }
    return _initialization ??= _doInitializeBluetooth();
  }

  Future<void> _doInitializeBluetooth() async {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error) {
        _setStatus(
          BluetoothAudioStatus(
            phase: BluetoothAudioConnectionPhase.error,
            message: _friendlyNativeError(error),
          ),
        );
      },
    );
    _pcmChannel.setMessageHandler((data) async {
      if (data != null && data.lengthInBytes > 0) {
        _handlePcmBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      return null;
    });

    try {
      final snapshot = await _controlChannel.invokeMapMethod<dynamic, dynamic>(
        'initialize',
      );
      if (snapshot != null) {
        _setStatus(_statusFromMap(snapshot));
      }
    } on MissingPluginException {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.unsupported,
          message: 'Bản Android này chưa có cầu nối BLE INNOTRIK.',
        ),
      );
    } on PlatformException catch (error) {
      _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyNativeError(error),
        ),
      );
    }
  }

  @override
  Future<List<BluetoothAudioDevice>> scanBluetoothDevices() async {
    await initializeBluetooth();
    _requireBridgeSupport();
    final permissions =
        await _controlChannel.invokeMethod<bool>('requestPermissions') ?? false;
    if (!permissions) {
      throw const InnotrikAudioInputException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để quét INNOTRIK.',
      );
    }
    final result = await _controlChannel.invokeListMethod<dynamic>(
      'scan',
      const <String, dynamic>{'timeoutMs': 5000},
    );
    final devices = (result ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(BluetoothAudioDevice.fromJson)
        .where((device) => device.id.isNotEmpty)
        .toList(growable: false);
    return devices;
  }

  @override
  Future<void> connectBluetoothDevice(String deviceId) async {
    await initializeBluetooth();
    _requireBridgeSupport();
    final permissions =
        await _controlChannel.invokeMethod<bool>('requestPermissions') ?? false;
    if (!permissions) {
      throw const InnotrikAudioInputException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để kết nối INNOTRIK.',
      );
    }
    await _controlChannel.invokeMethod<void>('connect', <String, dynamic>{
      'deviceId': deviceId,
      'timeoutMs': 15000,
    });
  }

  @override
  Future<void> disconnectBluetoothDevice() async {
    if (!enabled) {
      return;
    }
    if (_capturing) {
      await cancel();
    }
    try {
      await _controlChannel.invokeMethod<void>('disconnect');
    } on MissingPluginException {
      // The bridge is optional outside Android.
    }
  }

  void _requireBridgeSupport() {
    if (!_status.isBridgeSupported) {
      throw InnotrikAudioInputException(
        _status.message ?? 'Điện thoại này không hỗ trợ BLE INNOTRIK.',
      );
    }
  }

  @override
  Future<void> start() => startChunked();

  @override
  Future<void> startChunked() async {
    await initializeBluetooth();
    if (!isAvailable) {
      throw const InnotrikAudioInputException(
        'Hãy quét và kết nối Mic INNOTRIK trước khi bắt đầu nói.',
      );
    }
    if (_capturing) {
      throw const InnotrikAudioInputException('Mic INNOTRIK đang thu âm.');
    }

    _pcmBytes = BytesBuilder(copy: false);
    _pendingChunkBytes = BytesBuilder(copy: false);
    _initialNoiseRms = null;
    _startedAt = DateTime.now();
    _currentPath = await createTemporaryRecordingPath('wav');
    _capturing = true;
    try {
      await _controlChannel.invokeMethod<void>('startCapture');
    } catch (error) {
      _capturing = false;
      _pcmBytes = null;
      _pendingChunkBytes = null;
      rethrow;
    }
  }

  void _handlePcmBytes(Uint8List bytes) {
    if (!_capturing || bytes.isEmpty) {
      return;
    }
    final immutable = Uint8List.fromList(bytes);
    _pcmBytes?.add(immutable);
    _pendingChunkBytes?.add(immutable);
    _emitAmplitude(immutable);

    final pending = _pendingChunkBytes?.takeBytes() ?? Uint8List(0);
    var offset = 0;
    while (pending.length - offset >= _chunkByteLength) {
      _audioChunkController.add(
        Uint8List.fromList(pending.sublist(offset, offset + _chunkByteLength)),
      );
      offset += _chunkByteLength;
    }
    if (offset < pending.length) {
      _pendingChunkBytes?.add(Uint8List.fromList(pending.sublist(offset)));
    }
  }

  void _emitAmplitude(Uint8List pcm) {
    final evenLength = pcm.length - (pcm.length % 2);
    if (evenLength < 2) {
      return;
    }
    final data = ByteData.sublistView(pcm, 0, evenLength);
    var squareSum = 0.0;
    final sampleCount = evenLength ~/ 2;
    for (var offset = 0; offset < evenLength; offset += 2) {
      final sample = data.getInt16(offset, Endian.little) / 32768.0;
      squareSum += sample * sample;
    }
    final rms = math.sqrt(squareSum / sampleCount);
    _initialNoiseRms ??= rms;
    final dbfs = rms <= 0 ? -90.0 : 20 * math.log(rms) / math.ln10;
    _amplitudeController.add(dbfs.clamp(-90.0, 0.0).toDouble());
  }

  void _flushFinalChunk() {
    final finalChunk = _pendingChunkBytes?.takeBytes();
    if (finalChunk != null && finalChunk.isNotEmpty) {
      _audioChunkController.add(finalChunk);
    }
  }

  @override
  Future<AudioCapture> stop() async {
    if (!_capturing) {
      throw const InnotrikAudioInputException(
        'Mic INNOTRIK chưa bắt đầu thu âm.',
      );
    }
    try {
      await _controlChannel.invokeMethod<void>('stopCapture');
    } finally {
      _capturing = false;
    }
    _flushFinalChunk();

    final pcm = _pcmBytes?.takeBytes() ?? Uint8List(0);
    final path = _currentPath;
    final startedAt = _startedAt;
    if (pcm.isEmpty || path == null || startedAt == null) {
      throw InnotrikAudioInputException(
        'Đã kết nối nhưng chưa giải mã được audio INNOTRIK. '
        'Gói hợp lệ: ${_status.packetCount}, lỗi gói: '
        '${_status.invalidPacketCount}.',
      );
    }

    final header = buildPcm16WavHeader(
      pcmByteLength: pcm.length,
      sampleRate: _sampleRate,
    );
    final wav = Uint8List.fromList(<int>[...header, ...pcm]);
    await persistRecordingBytes(path, wav);
    final capture = AudioCapture(
      filePath: path,
      mimeType: 'audio/wav',
      duration: DateTime.now().difference(startedAt),
      inputLabel: label,
      isBluetoothInput: true,
      initialNoiseRms: _initialNoiseRms,
      streamHeaderBytes: header,
      streamedAudioBytes: pcm.length,
      recordingSampleRate: _sampleRate,
      dataBytes: wav,
    );
    _resetCaptureBuffers();
    return capture;
  }

  @override
  Future<void> cancel() async {
    _capturing = false;
    try {
      await _controlChannel.invokeMethod<void>('cancelCapture');
    } on MissingPluginException {
      // No native resource exists on unsupported platforms.
    } finally {
      _resetCaptureBuffers();
    }
  }

  void _resetCaptureBuffers() {
    _pcmBytes = null;
    _pendingChunkBytes = null;
    _currentPath = null;
    _startedAt = null;
    _initialNoiseRms = null;
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map<dynamic, dynamic>) {
      return;
    }
    final next = _statusFromMap(event);
    _setStatus(next);
    if (_capturing && next.phase == BluetoothAudioConnectionPhase.error) {
      _audioChunkController.addError(
        InnotrikAudioInputException(
          next.message ?? 'Luồng audio INNOTRIK bị gián đoạn.',
        ),
      );
    }
  }

  BluetoothAudioStatus _statusFromMap(Map<dynamic, dynamic> map) {
    final phaseName = '${map['phase'] ?? 'idle'}';
    final phase = BluetoothAudioConnectionPhase.values.firstWhere(
      (item) => item.name == phaseName,
      orElse: () => BluetoothAudioConnectionPhase.error,
    );
    return BluetoothAudioStatus(
      phase: phase,
      deviceId: _nullableString(map['deviceId']) ?? _status.deviceId,
      deviceName: _nullableString(map['deviceName']) ?? _status.deviceName,
      message: _nullableString(map['message']),
      packetCount: (map['packetCount'] as num?)?.toInt() ?? _status.packetCount,
      invalidPacketCount:
          (map['invalidPacketCount'] as num?)?.toInt() ??
          _status.invalidPacketCount,
      decodedPcmBytes:
          (map['decodedPcmBytes'] as num?)?.toInt() ?? _status.decodedPcmBytes,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? _status.sampleRate,
    );
  }

  String? _nullableString(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  void _setStatus(BluetoothAudioStatus next) {
    if (_disposed) {
      return;
    }
    _status = next;
    _statusController.add(next);
  }

  String _friendlyNativeError(Object error) {
    if (error is PlatformException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : error.code;
    }
    return '$error';
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _eventSubscription?.cancel();
    _pcmChannel.setMessageHandler(null);
    try {
      await _controlChannel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // Expected on web/iOS until their native bridge exists.
    }
    await _audioChunkController.close();
    await _amplitudeController.close();
    await _statusController.close();
  }
}

class InnotrikAudioInputException implements Exception {
  const InnotrikAudioInputException(this.message);

  final String message;

  @override
  String toString() => message;
}
