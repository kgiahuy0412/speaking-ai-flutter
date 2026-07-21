import 'dart:typed_data';

abstract final class InnotrikProtocol {
  static const serviceUuid = '0000ff12-0000-1000-8000-00805f9b34fb';
  static const writeCharacteristicUuid = '0000ff13-0000-1000-8000-00805f9b34fb';
  static const notifyCharacteristicUuid =
      '0000ff14-0000-1000-8000-00805f9b34fb';
  static const otaWriteCharacteristicUuid =
      '0000ff15-0000-1000-8000-00805f9b34fb';
  static const authServiceUuid = '0000ff10-0000-1000-8000-00805f9b34fb';
  static const authCharacteristicUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  static const packetLength = 84;
  static const headerLength = 4;
  static const opusPayloadLength = 80;

  static final Uint8List startMicrophoneCommand = Uint8List.fromList(
    const <int>[0x55, 0xAA, 0xA5, 0x59],
  );
  static final Uint8List stopMicrophoneCommand = Uint8List.fromList(const <int>[
    0x55,
    0xAA,
    0xA5,
    0x58,
  ]);
  static final Uint8List audioPacketHeader = Uint8List.fromList(const <int>[
    0x55,
    0xAA,
    0xA5,
    0x59,
  ]);

  static Uint8List extractOpusPayload(List<int> packet) {
    if (packet.length != packetLength) {
      throw InnotrikPacketException(
        'Gói BLE phải dài $packetLength byte, nhận ${packet.length} byte.',
      );
    }

    for (var index = 0; index < headerLength; index++) {
      if (packet[index] != audioPacketHeader[index]) {
        throw const InnotrikPacketException(
          'Header gói âm thanh INNOTRIK không hợp lệ.',
        );
      }
    }

    return Uint8List.fromList(packet.sublist(headerLength));
  }
}

class InnotrikPacketException implements Exception {
  const InnotrikPacketException(this.message);

  final String message;

  @override
  String toString() => message;
}
