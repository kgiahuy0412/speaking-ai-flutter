import 'dart:async';

import 'package:flutter/services.dart';

import 'audio_input.dart';

class HfpAudioDevice {
  const HfpAudioDevice({
    required this.id,
    required this.name,
    required this.isConnected,
  });

  factory HfpAudioDevice.fromJson(Map<dynamic, dynamic> json) {
    return HfpAudioDevice(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}'.trim(),
      isConnected: json['isConnected'] == true,
    );
  }

  final String id;
  final String name;
  final bool isConnected;

  String get displayName => name.isEmpty ? id : name;
}

abstract interface class HfpAudioControl {
  BluetoothAudioStatus get status;
  Stream<BluetoothAudioStatus> get statusChanges;

  Future<void> initialize();
  Future<List<HfpAudioDevice>> findDevices();
  Future<void> connect(HfpAudioDevice device);
  Future<void> disconnect();
  Future<void> startAudioRoute();
  Future<void> stopAudioRoute();
  Future<void> dispose();
}

/// Controls the Android Bluetooth Classic HFP/SCO microphone route.
///
/// Android's public API cannot initiate an HFP profile connection. The native
/// bridge therefore lists paired HFP-capable devices, lets Android Settings
/// finish the profile connection when needed, and then selects the SCO input.
class MethodChannelHfpAudioControl implements HfpAudioControl {
  MethodChannelHfpAudioControl({
    required this.enabled,
    MethodChannel methodChannel = const MethodChannel('ailingo_hfp_audio'),
    EventChannel eventChannel = const EventChannel('ailingo_hfp_audio/events'),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final bool enabled;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<BluetoothAudioStatus> _statusController =
      StreamController<BluetoothAudioStatus>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  Future<void>? _initialization;
  BluetoothAudioStatus _status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
    sampleRate: 16000,
  );
  bool _disposed = false;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _statusController.stream;

  @override
  Future<void> initialize() {
    if (!enabled) {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.disabled,
          message: 'HFP đang tắt trong cấu hình bản build.',
          sampleRate: 16000,
        ),
      );
      return Future<void>.value();
    }
    return _initialization ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error) => _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      ),
    );
    try {
      final snapshot = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'initialize',
      );
      if (snapshot != null) {
        _setStatus(_statusFromMap(snapshot));
      }
    } on MissingPluginException {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.unsupported,
          message: 'Bản Android này chưa có cầu nối HFP.',
          sampleRate: 16000,
        ),
      );
    } on PlatformException catch (error) {
      _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      );
    }
  }

  @override
  Future<List<HfpAudioDevice>> findDevices() async {
    await initialize();
    _requireSupport();
    final permissions =
        await _methodChannel.invokeMethod<bool>('requestPermissions') ?? false;
    if (!permissions) {
      throw const HfpAudioException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để tìm thiết bị HFP.',
      );
    }
    final result = await _methodChannel.invokeListMethod<dynamic>(
      'findDevices',
    );
    return (result ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(HfpAudioDevice.fromJson)
        .where((device) => device.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> connect(HfpAudioDevice device) async {
    await initialize();
    _requireSupport();
    final permissions =
        await _methodChannel.invokeMethod<bool>('requestPermissions') ?? false;
    if (!permissions) {
      throw const HfpAudioException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để dùng HFP.',
      );
    }
    await _methodChannel.invokeMethod<void>('connect', <String, dynamic>{
      'deviceId': device.id,
    });
  }

  @override
  Future<void> disconnect() async {
    if (!enabled) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('disconnect');
    } on MissingPluginException {
      // The bridge is optional outside Android.
    }
  }

  @override
  Future<void> startAudioRoute() async {
    await initialize();
    _requireSupport();
    await _methodChannel.invokeMethod<void>('startAudioRoute');
  }

  @override
  Future<void> stopAudioRoute() async {
    if (!enabled) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stopAudioRoute');
    } on MissingPluginException {
      // The bridge is optional outside Android.
    }
  }

  void _requireSupport() {
    if (!_status.isBridgeSupported) {
      throw HfpAudioException(
        _status.message ?? 'Điện thoại này không hỗ trợ âm thanh HFP.',
      );
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is Map<dynamic, dynamic>) {
      _setStatus(_statusFromMap(event));
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
      sampleRate: 16000,
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

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : error.code;
    }
    return '$error';
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stopAudioRoute();
    _disposed = true;
    await _eventSubscription?.cancel();
    await _statusController.close();
  }
}

class HfpAudioException implements Exception {
  const HfpAudioException(this.message);

  final String message;

  @override
  String toString() => message;
}
