import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'aiv0_ble_control.dart';

@JS('innotrikAiv0BleSupported')
external bool _isWebBluetoothSupported();

@JS('innotrikAiv0BleUnsupportedReason')
external JSString _webBluetoothUnsupportedReason();

@JS('innotrikAiv0BleScan')
external JSPromise<JSAny?> _scanWebBluetooth();

@JS('innotrikAiv0BleConnect')
external JSPromise<JSAny?> _connectWebBluetooth(JSString deviceId);

@JS('innotrikAiv0BleDisconnect')
external JSPromise<JSAny?> _disconnectWebBluetooth();

@JS('innotrikAiv0BleSendAppState')
external JSPromise<JSAny?> _sendWebAppState(JSArray<JSNumber> bytes);

@JS('innotrikAiv0BleSetEventHandler')
external void _setWebBluetoothEventHandler(JSFunction? handler);

/// Browser implementation for AIV0's BLE control plane.
///
/// Audio does not travel through this connection. HFP microphone/speaker
/// routing remains owned by the operating system and MediaDevices.
class BrowserAiv0BleControl implements Aiv0BleControl {
  BrowserAiv0BleControl({
    required bool enabled,
    required bool draftProtocolConfirmed,
  }) : _enabled = enabled,
       _codec = Aiv0DraftProtocolCodec(confirmed: draftProtocolConfirmed),
       _status = enabled
           ? Aiv0BleStatus(
               phase: Aiv0BlePhase.idle,
               protocolConfirmed: draftProtocolConfirmed,
               message:
                   'Web Bluetooth sẵn sàng. Bấm Quét & kết nối để chọn H20.',
             )
           : Aiv0BleStatus(
               phase: Aiv0BlePhase.disabled,
               protocolConfirmed: draftProtocolConfirmed,
               message: 'BLE Control AIV0 đang tắt trong cấu hình bản Web.',
             );

  final bool _enabled;
  final Aiv0DraftProtocolCodec _codec;
  final StreamController<Aiv0BleStatus> _statusController =
      StreamController<Aiv0BleStatus>.broadcast();
  final StreamController<Aiv0ButtonEvent> _buttonController =
      StreamController<Aiv0ButtonEvent>.broadcast();

  Aiv0BleStatus _status;
  JSFunction? _eventHandler;
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;

  @override
  Aiv0BleStatus get status => _status;

  @override
  Stream<Aiv0BleStatus> get statusStream => _statusController.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttonController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    if (!_enabled) return;
    if (!_isWebBluetoothSupported()) {
      _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.disabled,
          protocolConfirmed: _codec.confirmed,
          message: _webBluetoothUnsupportedReason().toDart,
        ),
      );
      return;
    }
    _eventHandler = ((JSAny event) => _handleWebEvent(event)).toJS;
    _setWebBluetoothEventHandler(_eventHandler);
    _setStatus(
      Aiv0BleStatus(
        phase: Aiv0BlePhase.idle,
        protocolConfirmed: _codec.confirmed,
        message: 'Web Bluetooth sẵn sàng. Bấm Quét & kết nối để chọn H20.',
      ),
    );
  }

  @override
  Future<List<Aiv0BleDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await initialize();
    _requireSupport();
    _setStatus(
      Aiv0BleStatus(
        phase: Aiv0BlePhase.scanning,
        protocolConfirmed: _codec.confirmed,
        message: 'Chọn H20/AIV0 trong bộ chọn Bluetooth của trình duyệt.',
      ),
    );
    try {
      // requestDevice owns its chooser lifetime; cancelling it is preferable
      // to expiring while the user is still looking for the headset.
      final result = await _scanWebBluetooth().toDart;
      final map = _mapFromJs(result);
      if (map == null) {
        throw StateError('Trình duyệt không trả về thiết bị BLE đã chọn.');
      }
      final device = Aiv0BleDevice.fromMap(map);
      if (device.id.isEmpty) {
        throw StateError('Thiết bị BLE không có mã nhận dạng hợp lệ.');
      }
      _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.idle,
          protocolConfirmed: _codec.confirmed,
          deviceId: device.id,
          deviceName: device.name,
          message: 'Đã chọn ${device.name}; chạm thiết bị để kết nối.',
        ),
      );
      return <Aiv0BleDevice>[device];
    } catch (error) {
      _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.error,
          protocolConfirmed: _codec.confirmed,
          message: _friendlyError(error),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    await initialize();
    _requireSupport();
    _setStatus(
      Aiv0BleStatus(
        phase: Aiv0BlePhase.connecting,
        protocolConfirmed: _codec.confirmed,
        deviceId: deviceId,
        message: 'Đang xác nhận service 9E3B0001 và MAIN 9E3B0002…',
      ),
    );
    try {
      final result = await _connectWebBluetooth(deviceId.toJS).toDart;
      final map = _mapFromJs(result);
      if (map == null) {
        throw StateError('Không nhận được trạng thái kết nối BLE từ Web.');
      }
      _updateStatus(map);
    } catch (error) {
      _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.error,
          protocolConfirmed: _codec.confirmed,
          deviceId: deviceId,
          message: _friendlyError(error),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_enabled || _disposed) return;
    try {
      final result = await _disconnectWebBluetooth().toDart;
      final map = _mapFromJs(result);
      if (map != null) _updateStatus(map);
    } catch (error) {
      _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.error,
          protocolConfirmed: _codec.confirmed,
          message: _friendlyError(error),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {
    if (!_enabled || !_codec.confirmed || !_status.isConnected) return;
    final packet = _codec.encodeAppState(
      state: state,
      result: result,
      sequence: sequence,
    );
    final jsBytes = packet.map((byte) => byte.toJS).toList().toJS;
    final write = _writeQueue.catchError((Object _) {}).then((_) async {
      await _sendWebAppState(jsBytes).toDart;
    });
    _writeQueue = write;
    await write;
  }

  void _handleWebEvent(JSAny event) {
    if (_disposed) return;
    final map = _mapFromJs(event);
    if (map == null) return;
    if (map['type'] == 'button') {
      final bytes = (map['bytes'] as List<Object?>? ?? const <Object?>[])
          .whereType<num>()
          .map((value) => value.toInt() & 0xFF)
          .toList(growable: false);
      final decoded = _codec.decodeButtonEvent(
        Uint8List.fromList(bytes),
        deviceId: map['deviceId']?.toString(),
        receivedAt: _dateTimeFromEpochMilliseconds(map['receivedAtEpochMs']),
      );
      _buttonController.add(
        Aiv0ButtonEvent(
          rawBytes: decoded.rawBytes,
          receivedAt: decoded.receivedAt,
          deviceId: decoded.deviceId,
          button: decoded.button,
          gesture: decoded.gesture,
          sequence: decoded.sequence,
          flags: decoded.flags,
          batteryPercent: decoded.batteryPercent,
          uptimeMilliseconds: decoded.uptimeMilliseconds,
          isObservedH20Packet: decoded.isObservedH20Packet,
          isDraftPacket: decoded.isDraftPacket,
          isDuplicate: map['duplicate'] == true,
        ),
      );
      return;
    }
    _updateStatus(map);
  }

  Map<Object?, Object?>? _mapFromJs(JSAny? value) {
    final dartValue = value?.dartify();
    if (dartValue is! Map<Object?, Object?>) return null;
    return dartValue;
  }

  void _updateStatus(Map<Object?, Object?> map) {
    _setStatus(Aiv0BleStatus.fromMap(map, protocolConfirmed: _codec.confirmed));
  }

  DateTime? _dateTimeFromEpochMilliseconds(Object? value) {
    final milliseconds = (value as num?)?.toInt();
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  void _requireSupport() {
    if (_status.phase == Aiv0BlePhase.disabled) {
      throw StateError(
        _status.message ?? 'Trình duyệt này không hỗ trợ Web Bluetooth.',
      );
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^Error:\s*'), '');
  }

  void _setStatus(Aiv0BleStatus value) {
    if (_disposed) return;
    _status = value;
    _statusController.add(value);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_eventHandler != null) {
      _setWebBluetoothEventHandler(null);
      _eventHandler = null;
    }
    if (_enabled && _isWebBluetoothSupported()) {
      try {
        await _disconnectWebBluetooth().toDart;
      } catch (_) {
        // Best effort while the Flutter tree is shutting down.
      }
    }
    await _statusController.close();
    await _buttonController.close();
  }
}
