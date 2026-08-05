import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/pcm16_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resamples Safari 48 kHz PCM to continuous 16 kHz PCM', () {
    const sourceRate = 48000;
    const targetRate = 16000;
    final source = _sinePcm(
      sampleRate: sourceRate,
      durationMs: 1000,
      frequencyHz: 440,
    );
    final resampler = Pcm16MonoResampler(
      sourceSampleRate: sourceRate,
      targetSampleRate: targetRate,
    );
    final output = BytesBuilder(copy: false);

    // Deliberately use uneven AudioWorklet-style boundaries, including an odd
    // byte boundary, to verify that streaming state is preserved.
    const boundaries = <int>[4097, 12001, 33333, 70001];
    var start = 0;
    for (final end in <int>[...boundaries, source.length]) {
      output.add(resampler.process(Uint8List.sublistView(source, start, end)));
      start = end;
    }
    output.add(resampler.flush());
    final resampled = output.takeBytes();

    expect(resampled.length, targetRate * 2);
    expect(_zeroCrossingCount(resampled), inInclusiveRange(870, 890));
  });

  test('keeps already-16 kHz PCM byte-identical', () {
    final source = _sinePcm(
      sampleRate: 16000,
      durationMs: 200,
      frequencyHz: 300,
    );
    final resampler = Pcm16MonoResampler(
      sourceSampleRate: 16000,
      targetSampleRate: 16000,
    );

    final output = BytesBuilder(copy: false)
      ..add(resampler.process(Uint8List.sublistView(source, 0, 101)))
      ..add(resampler.process(Uint8List.sublistView(source, 101)))
      ..add(resampler.flush());

    expect(output.takeBytes(), source);
  });
}

Uint8List _sinePcm({
  required int sampleRate,
  required int durationMs,
  required double frequencyHz,
}) {
  final sampleCount = sampleRate * durationMs ~/ 1000;
  final output = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(output);
  for (var index = 0; index < sampleCount; index += 1) {
    final sample =
        (math.sin(2 * math.pi * frequencyHz * index / sampleRate) * 20000)
            .round();
    data.setInt16(index * 2, sample, Endian.little);
  }
  return output;
}

int _zeroCrossingCount(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  var previous = data.getInt16(0, Endian.little);
  var crossings = 0;
  for (var offset = 2; offset < pcm.length; offset += 2) {
    final current = data.getInt16(offset, Endian.little);
    if ((previous < 0 && current >= 0) || (previous >= 0 && current < 0)) {
      crossings += 1;
    }
    previous = current;
  }
  return crossings;
}
