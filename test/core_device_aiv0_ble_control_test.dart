import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Aiv0DraftProtocolCodec', () {
    test('keeps raw packet diagnostic-only before ODM confirmation', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: false);
      final event = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 1, 1, 0, 42, 0, 88, 0, 0xD2, 0x04, 0, 0]),
      );

      expect(event.isDraftPacket, isFalse);
      expect(event.button, Aiv0Button.unknown);
      expect(event.sequence, isNull);
      expect(event.rawHex, '01 01 01 00 2A 00 58 00 D2 04 00 00');
    });

    test('decodes only draft MAIN after confirmation', () {
      const codec = Aiv0DraftProtocolCodec(confirmed: true);
      final main = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 1, 1, 0, 42, 0, 88, 0, 0xD2, 0x04, 0, 0]),
      );
      final replay = codec.decodeButtonEvent(
        Uint8List.fromList(<int>[1, 2, 1, 0, 43, 0, 87, 0, 0xE8, 0x03, 0, 0]),
      );

      expect(main.button, Aiv0Button.main);
      expect(main.gesture, Aiv0ButtonGesture.shortPress);
      expect(main.sequence, 42);
      expect(main.batteryPercent, 88);
      expect(main.uptimeMilliseconds, 1234);
      expect(main.isDraftPacket, isTrue);
      expect(replay.button, Aiv0Button.unknown);
      expect(replay.sequence, 43);
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
