import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const aiv0ControlServiceUuid = '9E3B0001-4A7C-4D6F-8B21-5C17A2D94010';
const aiv0ButtonEventUuid = '9E3B0002-4A7C-4D6F-8B21-5C17A2D94010';
const aiv0AppStateUuid = '9E3B0003-4A7C-4D6F-8B21-5C17A2D94010';

enum Aiv0BlePhase {
  disabled,
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  error,
}

/// V1 exposes one application-controlled physical button: MAIN.
///
/// Power and volume stay local to the device. Unknown values are retained in
/// the raw log instead of being interpreted as a retired REPLAY command.
enum Aiv0Button { main, unknown }

enum Aiv0ButtonGesture { shortPress, longPress, release, unknown }

enum Aiv0AppState { idle, recording, processing, ready, playing, error }

enum Aiv0AppResult {
  accepted,
  busy,
  noResult,
  micUnavailable,
  bluetoothRouteUnavailable,
  duplicate,
  internalError,
}

class Aiv0BleDevice {
  const Aiv0BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isLikelyAiv0 = false,
    this.advertisesControlService = false,
  });

  factory Aiv0BleDevice.fromMap(Map<Object?, Object?> map) {
    return Aiv0BleDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'H20',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      isLikelyAiv0: map['isLikelyAiv0'] == true,
      advertisesControlService: map['advertisesControlService'] == true,
    );
  }

  final String id;
  final String name;
  final int rssi;
  final bool isLikelyAiv0;
  final bool advertisesControlService;
}

@visibleForTesting
Aiv0BleDevice? selectAiv0AutoConnectCandidate(
  List<Aiv0BleDevice> devices, {
  String? savedDeviceId,
}) {
  if (devices.isEmpty) return null;
  final normalizedSavedId = savedDeviceId?.trim().toUpperCase();
  if (normalizedSavedId != null && normalizedSavedId.isNotEmpty) {
    for (final device in devices) {
      if (device.id.trim().toUpperCase() == normalizedSavedId) {
        return device;
      }
    }
  }

  final serviceMatches =
      devices
          .where((device) => device.advertisesControlService)
          .toList(growable: false)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
  if (serviceMatches.isNotEmpty) return serviceMatches.first;

  final likelyMatches =
      devices.where((device) => device.isLikelyAiv0).toList(growable: false)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
  return likelyMatches.isEmpty ? null : likelyMatches.first;
}

class Aiv0ButtonEvent {
  const Aiv0ButtonEvent({
    required this.rawBytes,
    required this.receivedAt,
    this.deviceId,
    this.button = Aiv0Button.unknown,
    this.gesture = Aiv0ButtonGesture.unknown,
    this.sequence,
    this.flags,
    this.batteryPercent,
    this.uptimeMilliseconds,
    this.isObservedH20Packet = false,
    this.isDraftPacket = false,
    this.isDuplicate = false,
  });

  final Uint8List rawBytes;
  final DateTime receivedAt;
  final String? deviceId;
  final Aiv0Button button;
  final Aiv0ButtonGesture gesture;
  final int? sequence;
  final int? flags;
  final int? batteryPercent;
  final int? uptimeMilliseconds;
  final bool isObservedH20Packet;
  final bool isDraftPacket;
  final bool isDuplicate;

  /// Whether this notification has enough information to enter the unified
  /// MAIN handler. Observed H20 packets are actionable even while the separate
  /// APP State write packet remains unconfirmed.
  bool get isActionable => isObservedH20Packet || isDraftPacket;

  String get rawHex => rawBytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

/// Temporary codec from the V0.1 draft. Keep [confirmed] false until ODM sends
/// MAIN raw hex and confirms the byte layout implemented by firmware.
class Aiv0DraftProtocolCodec {
  const Aiv0DraftProtocolCodec({required this.confirmed});

  static const buttonPacketLength = 12;
  static const appStatePacketLength = 8;
  static const protocolVersion = 1;

  final bool confirmed;

  Aiv0ButtonEvent decodeButtonEvent(
    Uint8List bytes, {
    String? deviceId,
    DateTime? receivedAt,
  }) {
    // Real H20 firmware 1.0.0 packet observed on 9E3B0002:
    //   01 BB SS 01 FF FF PP 00 UU UU UU UU
    // BB is MAIN (01), SS is a transport sequence, PP is the battery
    // percentage and UU is uptime in milliseconds (LE). The current firmware
    // exposes one MAIN action only; it does not expose long-press or release.
    //
    // Decode this independently from [confirmed]. That flag still protects
    // the unconfirmed 8-byte APP State writer; receiving MAIN must not require
    // sending that draft packet back to the device.
    final isObservedH20Packet =
        bytes.length == buttonPacketLength &&
        bytes[0] == protocolVersion &&
        bytes[1] == 0x01 &&
        bytes[3] == 0x01;
    if (isObservedH20Packet) {
      final data = ByteData.sublistView(bytes);
      return Aiv0ButtonEvent(
        rawBytes: bytes,
        deviceId: deviceId,
        receivedAt: receivedAt ?? DateTime.now(),
        button: Aiv0Button.main,
        gesture: Aiv0ButtonGesture.shortPress,
        sequence: bytes[2],
        flags: data.getUint16(4, Endian.little),
        batteryPercent: data.getUint16(6, Endian.little).clamp(0, 100),
        uptimeMilliseconds: data.getUint32(8, Endian.little),
        isObservedH20Packet: true,
      );
    }

    if (!confirmed ||
        bytes.length != buttonPacketLength ||
        bytes[0] != protocolVersion) {
      return Aiv0ButtonEvent(
        rawBytes: bytes,
        deviceId: deviceId,
        receivedAt: receivedAt ?? DateTime.now(),
      );
    }

    final data = ByteData.sublistView(bytes);
    return Aiv0ButtonEvent(
      rawBytes: bytes,
      deviceId: deviceId,
      receivedAt: receivedAt ?? DateTime.now(),
      button: switch (bytes[1]) {
        0x01 => Aiv0Button.main,
        _ => Aiv0Button.unknown,
      },
      gesture: switch (bytes[2]) {
        0x01 => Aiv0ButtonGesture.shortPress,
        0x02 => Aiv0ButtonGesture.longPress,
        0x03 => Aiv0ButtonGesture.release,
        _ => Aiv0ButtonGesture.unknown,
      },
      flags: bytes[3],
      sequence: data.getUint16(4, Endian.little),
      batteryPercent: bytes[6].clamp(0, 100),
      uptimeMilliseconds: data.getUint32(8, Endian.little),
      isDraftPacket: true,
    );
  }

  Uint8List encodeAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
    int flags = 0,
  }) {
    if (!confirmed) {
      throw StateError(
        'AIV0 draft protocol is not confirmed by ODM; APP State was not sent.',
      );
    }
    final bytes = Uint8List(appStatePacketLength);
    final data = ByteData.sublistView(bytes);
    bytes[0] = protocolVersion;
    bytes[1] = state.index;
    bytes[2] = result.index;
    bytes[3] = flags & 0xFF;
    data.setUint16(4, sequence & 0xFFFF, Endian.little);
    return bytes;
  }
}

class Aiv0BleStatus {
  const Aiv0BleStatus({
    required this.phase,
    required this.protocolConfirmed,
    this.deviceId,
    this.deviceName,
    this.message,
    this.writeMode,
    this.batteryPercent,
    this.firmwareRevision,
    this.lastRawHex,
    this.lastButton,
    this.lastGesture,
    this.packetCount = 0,
    this.invalidPacketCount = 0,
    this.duplicatePacketCount = 0,
    this.reconnectCount = 0,
  });

  const Aiv0BleStatus.disabled()
    : this(
        phase: Aiv0BlePhase.disabled,
        protocolConfirmed: false,
        message: 'BLE Control AIV0 chỉ hỗ trợ trên Android/iOS native.',
      );

  factory Aiv0BleStatus.fromMap(
    Map<Object?, Object?> map, {
    required bool protocolConfirmed,
  }) {
    final rawPhase = map['phase']?.toString();
    return Aiv0BleStatus(
      phase: Aiv0BlePhase.values.firstWhere(
        (value) => value.name == rawPhase,
        orElse: () => Aiv0BlePhase.idle,
      ),
      protocolConfirmed: protocolConfirmed,
      deviceId: map['deviceId']?.toString(),
      deviceName: map['deviceName']?.toString(),
      message: map['message']?.toString(),
      writeMode: map['writeMode']?.toString(),
      batteryPercent: (map['batteryPercent'] as num?)?.toInt(),
      firmwareRevision: map['firmwareRevision']?.toString(),
      lastRawHex: map['lastRawHex']?.toString(),
      lastButton: map['lastButton']?.toString(),
      lastGesture: map['lastGesture']?.toString(),
      packetCount: (map['packetCount'] as num?)?.toInt() ?? 0,
      invalidPacketCount: (map['invalidPacketCount'] as num?)?.toInt() ?? 0,
      duplicatePacketCount: (map['duplicatePacketCount'] as num?)?.toInt() ?? 0,
      reconnectCount: (map['reconnectCount'] as num?)?.toInt() ?? 0,
    );
  }

  final Aiv0BlePhase phase;
  final bool protocolConfirmed;
  final String? deviceId;
  final String? deviceName;
  final String? message;
  final String? writeMode;
  final int? batteryPercent;
  final String? firmwareRevision;
  final String? lastRawHex;
  final String? lastButton;
  final String? lastGesture;
  final int packetCount;
  final int invalidPacketCount;
  final int duplicatePacketCount;
  final int reconnectCount;

  bool get isConnected => phase == Aiv0BlePhase.connected;
}

abstract interface class Aiv0BleControl {
  Aiv0BleStatus get status;
  Stream<Aiv0BleStatus> get statusStream;
  Stream<Aiv0ButtonEvent> get buttonEvents;

  Future<void> initialize();
  Future<List<Aiv0BleDevice>> scan({Duration timeout});
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence,
  });
  Future<void> dispose();
}

class MethodChannelAiv0BleControl implements Aiv0BleControl {
  MethodChannelAiv0BleControl({
    required bool enabled,
    required bool draftProtocolConfirmed,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _enabled =
           enabled &&
           !kIsWeb &&
           (defaultTargetPlatform == TargetPlatform.android ||
               defaultTargetPlatform == TargetPlatform.iOS),
       _codec = Aiv0DraftProtocolCodec(confirmed: draftProtocolConfirmed),
       _methodChannel =
           methodChannel ?? const MethodChannel('ailingo_aiv0_ble_control'),
       _eventChannel =
           eventChannel ??
           const EventChannel('ailingo_aiv0_ble_control/events'),
       _status =
           enabled &&
               !kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS)
           ? Aiv0BleStatus(
               phase: Aiv0BlePhase.idle,
               protocolConfirmed: draftProtocolConfirmed,
             )
           : const Aiv0BleStatus.disabled();

  final bool _enabled;
  final Aiv0DraftProtocolCodec _codec;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final _statusController = StreamController<Aiv0BleStatus>.broadcast();
  final _buttonController = StreamController<Aiv0ButtonEvent>.broadcast();
  static const _lastDeviceIdPreference = 'aiv0_ble_last_device_id';
  static const _lastDeviceNamePreference = 'aiv0_ble_last_device_name';
  StreamSubscription<Object?>? _eventSubscription;
  Aiv0BleStatus _status;
  Future<void> _writeQueue = Future<void>.value();
  Future<bool>? _autoConnectFuture;
  bool _manualDisconnectRequested = false;

  @override
  Aiv0BleStatus get status => _status;

  @override
  Stream<Aiv0BleStatus> get statusStream => _statusController.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttonController.stream;

  @override
  Future<void> initialize() async {
    if (!_enabled || _eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) => _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.error,
          protocolConfirmed: _codec.confirmed,
          message: error.toString(),
        ),
      ),
    );
    final map = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'initialize',
    );
    if (map != null) _updateStatus(map);
  }

  /// Requests the platform Bluetooth permission used by AIV0 before the child
  /// operates the physical MAIN button.
  Future<bool> requestPermissions() async {
    if (!_enabled) return true;
    await initialize();
    return await _methodChannel.invokeMethod<bool>('requestPermissions') ??
        false;
  }

  @override
  Future<List<Aiv0BleDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!_enabled) return const [];
    await initialize();
    final permissionGranted = await requestPermissions();
    if (!permissionGranted) {
      throw PlatformException(
        code: 'PERMISSION_REQUIRED',
        message: 'Cần cấp quyền Thiết bị ở gần/Bluetooth để tìm H20.',
      );
    }
    final devices = await _methodChannel.invokeListMethod<Object?>(
      'scan',
      <String, Object?>{'timeoutMs': timeout.inMilliseconds},
    );
    return (devices ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(Aiv0BleDevice.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) async {
    if (!_enabled) return;
    _manualDisconnectRequested = false;
    await initialize();
    final permissionGranted = await requestPermissions();
    if (!permissionGranted) {
      throw PlatformException(
        code: 'PERMISSION_REQUIRED',
        message: 'Cần cấp quyền Bluetooth để kết nối H20.',
      );
    }
    await _methodChannel.invokeMethod<void>('connect', <String, Object?>{
      'deviceId': deviceId,
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastDeviceIdPreference, deviceId);
    final connectedName = _status.deviceName?.trim();
    if (connectedName != null && connectedName.isNotEmpty) {
      await preferences.setString(_lastDeviceNamePreference, connectedName);
    }
  }

  /// Reconnects BLE Control without requiring a second user action after H20
  /// has already been paired through the system Bluetooth/HFP settings.
  ///
  /// The previously verified BLE address is preferred. On first use (or when
  /// the saved native identifier changes), advertised 9E3B0001 service is the
  /// strongest signal; the H20/AIV0 device name is only a safe fallback.
  Future<bool> autoConnectKnownOrNearby({
    Duration scanTimeout = const Duration(seconds: 4),
  }) {
    if (!_enabled || _manualDisconnectRequested) {
      return Future<bool>.value(false);
    }
    final pending = _autoConnectFuture;
    if (pending != null) return pending;
    final future = _runAutoConnect(scanTimeout);
    _autoConnectFuture = future;
    return future.whenComplete(() {
      if (identical(_autoConnectFuture, future)) {
        _autoConnectFuture = null;
      }
    });
  }

  Future<bool> _runAutoConnect(Duration scanTimeout) async {
    await initialize();
    if (_status.isConnected) return true;
    if (_status.phase == Aiv0BlePhase.scanning ||
        _status.phase == Aiv0BlePhase.connecting ||
        _status.phase == Aiv0BlePhase.reconnecting) {
      return false;
    }

    final preferences = await SharedPreferences.getInstance();
    final savedDeviceId = preferences.getString(_lastDeviceIdPreference);
    if (savedDeviceId != null && savedDeviceId.trim().isNotEmpty) {
      try {
        // This is the fast path for normal daily use: native can reopen the
        // verified GATT identifier directly without waiting for another scan.
        await connect(savedDeviceId.trim());
        return true;
      } catch (error) {
        debugPrint(
          'Saved H20 BLE address was unavailable; scanning nearby: $error',
        );
      }
    }

    List<Aiv0BleDevice> devices = const [];
    try {
      devices = await scan(timeout: scanTimeout);
    } catch (error) {
      debugPrint('Automatic H20 BLE scan was skipped: $error');
    }

    final candidate = selectAiv0AutoConnectCandidate(
      devices,
      savedDeviceId: savedDeviceId,
    );
    final targetId = candidate?.id;
    if (targetId == null || targetId.isEmpty) return false;

    try {
      await connect(targetId);
      if (candidate != null && candidate.name.trim().isNotEmpty) {
        await preferences.setString(
          _lastDeviceNamePreference,
          candidate.name.trim(),
        );
      }
      // Native completes `connect` only after service 9E3B0001 is verified and
      // Indicate 9E3B0002 is enabled. The status EventChannel can arrive one
      // microtask later, so the completed method call itself is authoritative.
      return true;
    } catch (error) {
      debugPrint('Automatic H20 BLE connection failed: $error');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_enabled) return;
    _manualDisconnectRequested = true;
    await _methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {
    if (!_enabled || !_codec.confirmed) return;
    final packet = _codec.encodeAppState(
      state: state,
      result: result,
      sequence: sequence,
    );
    final write = _writeQueue.catchError((Object _) {}).then((_) async {
      await _methodChannel.invokeMethod<void>('sendAppState', <String, Object?>{
        'bytes': packet.toList(growable: false),
      });
    });
    _writeQueue = write;
    await write;
  }

  void _handleEvent(Object? event) {
    if (event is! Map<Object?, Object?>) return;
    if (event['type'] == 'button') {
      final bytes = (event['bytes'] as List<Object?>? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt() & 0xFF)
          .toList(growable: false);
      final buttonEvent = _codec.decodeButtonEvent(
        Uint8List.fromList(bytes),
        deviceId: event['deviceId']?.toString(),
        receivedAt: _dateTimeFromEpochMilliseconds(event['receivedAtEpochMs']),
      );
      _buttonController.add(
        Aiv0ButtonEvent(
          rawBytes: buttonEvent.rawBytes,
          receivedAt: buttonEvent.receivedAt,
          deviceId: buttonEvent.deviceId,
          button: buttonEvent.button,
          gesture: buttonEvent.gesture,
          sequence: buttonEvent.sequence,
          flags: buttonEvent.flags,
          batteryPercent: buttonEvent.batteryPercent,
          uptimeMilliseconds: buttonEvent.uptimeMilliseconds,
          isObservedH20Packet: buttonEvent.isObservedH20Packet,
          isDraftPacket: buttonEvent.isDraftPacket,
          isDuplicate: event['duplicate'] == true,
        ),
      );
      return;
    }
    _updateStatus(event);
  }

  void _updateStatus(Map<Object?, Object?> map) {
    _setStatus(Aiv0BleStatus.fromMap(map, protocolConfirmed: _codec.confirmed));
  }

  DateTime? _dateTimeFromEpochMilliseconds(Object? value) {
    final milliseconds = (value as num?)?.toInt();
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  void _setStatus(Aiv0BleStatus value) {
    _status = value;
    _statusController.add(value);
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_enabled) {
      await _methodChannel.invokeMethod<void>('dispose');
    }
    await _statusController.close();
    await _buttonController.close();
  }
}
