import 'dart:typed_data';

// OpenAI Realtime PCM input requires mono PCM16 at 24 kHz.
const int pcm16SampleRate = 24000;
const int pcm16ChannelCount = 1;
const int pcm16BitsPerSample = 16;

Uint8List buildPcm16WavHeader({
  required int pcmByteLength,
  int sampleRate = pcm16SampleRate,
  int channelCount = pcm16ChannelCount,
}) {
  const headerLength = 44;
  const bytesPerSample = pcm16BitsPerSample ~/ 8;
  final byteRate = sampleRate * channelCount * bytesPerSample;
  final blockAlign = channelCount * bytesPerSample;
  final bytes = Uint8List(headerLength);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcmByteLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channelCount, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, pcm16BitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcmByteLength, Endian.little);
  return bytes;
}

Uint8List buildPcm16Wav(Uint8List pcmBytes) {
  final header = buildPcm16WavHeader(pcmByteLength: pcmBytes.length);
  return Uint8List.fromList(<int>[...header, ...pcmBytes]);
}
