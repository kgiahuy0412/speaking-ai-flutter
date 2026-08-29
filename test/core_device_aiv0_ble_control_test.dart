import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIV0 native diagnostics', () {
    test('recognizes the connected CBPeripheral raw-value description', () {
      final status = Aiv0BleStatus.fromMap(<Object?, Object?>{
        'phase': 'connected',
        'peripheralState': 'CBPeripheralState(rawValue: 2)',
        'mainNotificationState': 'notifying',
      }, protocolConfirmed: false);

      expect(status.phase, Aiv0BlePhase.connected);
      expect(status.isConnected, isTrue);
      expect(status.peripheralState, 'connected');
    });

    test(
      'does not report connected when the native GATT peripheral is disconnected',
      () {
        final status = Aiv0BleStatus.fromMap(<Object?, Object?>{
          'phase': 'connected',
          'peripheralState': 'CBPeripheralState(rawValue: 0)',
          'mainNotificationState': 'unavailable',
          'lastDisconnectCode': 'CBErrorDomain:7',
          'lastDisconnectMessage': 'The specified device has disconnected.',
          'lastDisconnectEpochMs': 1_787_987_522_081,
          'lastNotificationRecovery':
              'reconnect • peripheral=disconnected • notify=unavailable',
          'deferredRecoveryRepeatCount': 12,
        }, protocolConfirmed: false);

        expect(status.phase, Aiv0BlePhase.reconnecting);
        expect(status.isConnected, isFalse);
        expect(status.peripheralState, 'disconnected');
        expect(status.mainNotificationState, 'unavailable');
        expect(status.lastDisconnectCode, 'CBErrorDomain:7');
        expect(
          status.lastDisconnectMessage,
          'The specified device has disconnected.',
        );
        expect(
          status.lastDisconnectAt,
          DateTime.fromMillisecondsSinceEpoch(1_787_987_522_081),
        );
        expect(
          status.lastNotificationRecovery,
          'reconnect • peripheral=disconnected • notify=unavailable',
        );
        expect(status.deferredRecoveryRepeatCount, 12);
      },
    );
  });

  group('AIV0 automatic connection selection', () {
    test('prefers the previously verified H20 address', () {
      const devices = <Aiv0BleDevice>[
        Aiv0BleDevice(
          id: 'AA:AA',
          name: 'H20 nearby',
          rssi: -30,
          isLikelyAiv0: true,
        ),
        Aiv0BleDevice(
          id: 'BB:BB',
          name: 'H20 saved',
          rssi: -80,
          isLikelyAiv0: true,
        ),
      ];

      expect(
        selectAiv0AutoConnectCandidate(devices, savedDeviceId: 'bb:bb')?.id,
        'BB:BB',
      );
    });

    test('prefers an advertised control service over a name match', () {
      const devices = <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'NAME', name: 'H20', rssi: -20, isLikelyAiv0: true),
        Aiv0BleDevice(
          id: 'SERVICE',
          name: 'Unknown',
          rssi: -70,
          isLikelyAiv0: true,
          advertisesControlService: true,
        ),
      ];

      expect(selectAiv0AutoConnectCandidate(devices)?.id, 'SERVICE');
    });

    test('does not connect an unrelated BLE device', () {
      const devices = <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'OTHER', name: 'Other', rssi: -10),
      ];

      expect(selectAiv0AutoConnectCandidate(devices), isNull);
    });
  });

  group('Aiv0DraftProtocolCodec', () {
    test('decodes observed H20 MAIN packet without enabling APP State', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: false);
      final event = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[
          0x01,
          0x01,
          0x10,
          0x01,
          0x01,
          0x04,
          0x3E,
          0x00,
          0x3A,
          0xF2,
          0x0B,
          0x00,
        ]),
      );

      expect(event.isObservedH20Packet, isTrue);
      expect(event.isDraftPacket, isFalse);
      expect(event.isActionable, isTrue);
      expect(event.button, Aiv0Button.main);
      expect(event.gesture, Aiv0ButtonGesture.shortPress);
      expect(event.sequence, 0x10);
      expect(event.flags, 0x0401);
      expect(event.batteryPercent, 62);
      expect(event.uptimeMilliseconds, 782906);
      expect(event.rawHex, '01 01 10 01 01 04 3E 00 3A F2 0B 00');
    });

    test('does not invent long press or release for current H20 packets', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: false);
      final longPress = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[
          0x01,
          0x01,
          0x11,
          0x02,
          0x01,
          0x04,
          0x3E,
          0x00,
          0x10,
          0xF3,
          0x0B,
          0x00,
        ]),
      );
      final release = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[
          0x01,
          0x01,
          0x11,
          0x03,
          0x01,
          0x04,
          0x3E,
          0x00,
          0x20,
          0xF3,
          0x0B,
          0x00,
        ]),
      );

      expect(longPress.button, Aiv0Button.unknown);
      expect(longPress.gesture, Aiv0ButtonGesture.unknown);
      expect(longPress.isObservedH20Packet, isFalse);
      expect(longPress.isActionable, isFalse);
      expect(release.button, Aiv0Button.unknown);
      expect(release.gesture, Aiv0ButtonGesture.unknown);
      expect(release.isObservedH20Packet, isFalse);
      expect(release.isActionable, isFalse);
    });

    test('keeps an unknown raw packet diagnostic-only', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: false);
      final event = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[0xAA, 0x01, 0x00]),
      );

      expect(event.isActionable, isFalse);
      expect(event.button, Aiv0Button.unknown);
    });

    test('decodes only draft MAIN after confirmation', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: true);
      final main = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 1, 1, 0, 42, 0, 88, 0, 0xD2, 0x04, 0, 0]),
      );
      final replay = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 2, 1, 0, 43, 0, 87, 0, 0xE8, 0x03, 0, 0]),
      );
      final longPress = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 1, 2, 0, 44, 0, 86, 0, 0xE9, 0x03, 0, 0]),
      );
      final release = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 1, 3, 0, 44, 0, 86, 0, 0xEA, 0x03, 0, 0]),
      );

      expect(main.button, Aiv0Button.main);
      expect(main.gesture, Aiv0ButtonGesture.shortPress);
      expect(main.sequence, 42);
      expect(main.batteryPercent, 88);
      expect(main.uptimeMilliseconds, 1234);
      expect(main.isDraftPacket, isTrue);
      expect(replay.button, Aiv0Button.unknown);
      expect(replay.sequence, 43);
      expect(longPress.gesture, Aiv0ButtonGesture.longPress);
      expect(release.gesture, Aiv0ButtonGesture.release);
    });

    test('encodes the draft 8-byte APP State with acknowledged sequence', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: true);

      final packet = codec.encodeAppState(
        state: Aiv0AppState.playing,
        result: Aiv0AppResult.accepted,
        sequence: 0x1234,
      );

      expect(packet, <int>[1, 4, 0, 0, 0x34, 0x12, 0, 0]);
    });

    test('does not dispatch a packet with an unexpected version', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: true);

      final event = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[2, 1, 1, 0, 1, 0, 90, 0, 0, 0, 0, 0]),
      );

      expect(event.isDraftPacket, isFalse);
      expect(event.button, Aiv0Button.unknown);
    });

    test('refuses to encode APP State before ODM confirmation', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: false);

      expect(
        () => codec.encodeAppState(
          state: Aiv0AppState.idle,
          result: Aiv0AppResult.accepted,
        ),
        throwsStateError,
      );
    });
  });
}
