import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a valid mono 24 kHz PCM WAV header', () {
    final header = buildPcm16WavHeader(pcmByteLength: 32000);
    final data = ByteData.sublistView(header);

    expect(ascii.decode(header.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little), 32036);
    expect(ascii.decode(header.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(28, Endian.little), 48000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(header.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), 32000);
  });

  test('prefixes PCM bytes with the matching header', () {
    final pcm = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final wav = buildPcm16Wav(pcm);

    expect(wav, hasLength(48));
    expect(wav.sublist(44), pcm);
    expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 4);
  });

  test('keeps a 200 ms chunk at the browser effective sample rate', () {
    expect(pcm16ChunkByteLength(sampleRate: 24000), 9600);
    expect(pcm16ChunkByteLength(sampleRate: 48000), 19200);
  });

  test('writes the effective browser sample rate into the WAV header', () {
    final header = buildPcm16WavHeader(pcmByteLength: 19200, sampleRate: 48000);
    final data = ByteData.sublistView(header);

    expect(data.getUint32(24, Endian.little), 48000);
    expect(data.getUint32(28, Endian.little), 96000);
  });
}
