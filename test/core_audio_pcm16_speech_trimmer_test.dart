import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/pcm16_speech_trimmer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pcm16Segments(List<(int, double)> segments) {
  const sampleRate = 16000;
  final samples = <int>[];
  var phase = 0;
  for (final (durationMs, amplitude) in segments) {
    final count = sampleRate * durationMs ~/ 1000;
    for (var index = 0; index < count; index += 1) {
      final value = amplitude == 0
          ? 0
          : (math.sin(phase * 0.17) * amplitude * 32767).round();
      samples.add(value.clamp(-32768, 32767));
      phase += 1;
    }
  }
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < samples.length; index += 1) {
    data.setInt16(index * 2, samples[index], Endian.little);
  }
  return bytes;
}

void main() {
  test('trims long silence but keeps conservative speech padding', () {
    final original = _pcm16Segments(<(int, double)>[
      (700, 0),
      (900, 0.12),
      (900, 0),
    ]);

    final result = trimPcm16SpeechForAsr(original);

    expect(result.trimmed, isTrue);
    expect(result.reason, 'trimmed');
    expect(result.leadingTrimDurationMs, inInclusiveRange(400, 440));
    expect(result.trailingTrimDurationMs, inInclusiveRange(460, 500));
    expect(result.trimmedDurationMs, greaterThanOrEqualTo(860));
    expect(result.bytes.length.isEven, isTrue);
  });

  test('keeps softly spoken child audio above a quiet noise floor', () {
    final original = _pcm16Segments(<(int, double)>[
      (600, 0.0005),
      (800, 0.012),
      (700, 0.0005),
    ]);

    final result = trimPcm16SpeechForAsr(original);

    expect(result.trimmed, isTrue);
    expect(result.bytes, isNotEmpty);
    expect(result.sourceStartByte, lessThan(600 * 32));
    expect(result.sourceEndByte, greaterThan(1400 * 32));
  });

  test('does not invent speech or trim an all-silent recording', () {
    final original = Uint8List(16000 * 2 * 2);

    final result = trimPcm16SpeechForAsr(original);

    expect(result.trimmed, isFalse);
    expect(result.reason, 'speech_not_found');
    expect(result.bytes, orderedEquals(original));
  });

  test('does not trim when the useful saving is too small', () {
    final original = _pcm16Segments(<(int, double)>[
      (120, 0),
      (800, 0.15),
      (180, 0),
    ]);

    final result = trimPcm16SpeechForAsr(original);

    expect(result.trimmed, isFalse);
    expect(result.reason, 'saving_too_small');
    expect(result.bytes, orderedEquals(original));
  });
}
