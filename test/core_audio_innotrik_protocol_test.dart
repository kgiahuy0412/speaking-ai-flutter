import 'package:ai_speaking_flutter_app/core/audio/innotrik_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InnotrikProtocol', () {
    test('extracts the documented 80-byte Opus payload', () {
      final packet = <int>[
        0x55,
        0xAA,
        0xA5,
        0x59,
        ...List<int>.generate(80, (index) => index),
      ];

      final payload = InnotrikProtocol.extractOpusPayload(packet);

      expect(payload, hasLength(80));
      expect(payload.first, 0);
      expect(payload.last, 79);
    });

    test('rejects a packet with the wrong length', () {
      expect(
        () => InnotrikProtocol.extractOpusPayload(<int>[0x55, 0xAA]),
        throwsA(isA<InnotrikPacketException>()),
      );
    });

    test('rejects a packet with the wrong header', () {
      final packet = <int>[0x55, 0xAA, 0xA5, 0x58, ...List<int>.filled(80, 0)];

      expect(
        () => InnotrikProtocol.extractOpusPayload(packet),
        throwsA(isA<InnotrikPacketException>()),
      );
    });
  });
}
