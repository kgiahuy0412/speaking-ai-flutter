import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_speaking_flutter_app/core/audio/pcm_speech_preprocessor.dart';

void main() {
  const sampleRate = 16000;

  test('high-pass removes rumble while preserving the speech band', () {
    final lowInput = _sinePcm(
      sampleRate: sampleRate,
      frequencyHz: 40,
      amplitude: 0.3,
      duration: const Duration(seconds: 1),
    );
    final speechInput = _sinePcm(
      sampleRate: sampleRate,
      frequencyHz: 500,
      amplitude: 0.3,
      duration: const Duration(seconds: 1),
    );
    final lowOutput = PcmSpeechPreprocessor(
      sampleRate: sampleRate,
      calibrationDuration: const Duration(seconds: 2),
    ).process(lowInput);
    final speechOutput = PcmSpeechPreprocessor(
      sampleRate: sampleRate,
      calibrationDuration: const Duration(seconds: 2),
    ).process(speechInput);

    expect(_rms(lowOutput) / _rms(lowInput), lessThan(0.55));
    expect(_rms(speechOutput) / _rms(speechInput), greaterThan(0.9));
  });

  test('adaptive gate attenuates steady noise and keeps later speech', () {
    final processor = PcmSpeechPreprocessor(sampleRate: sampleRate);
    final calibrationNoise = _sinePcm(
      sampleRate: sampleRate,
      frequencyHz: 700,
      amplitude: 0.02,
      duration: const Duration(milliseconds: 300),
    );
    final steadyNoise = _sinePcm(
      sampleRate: sampleRate,
      frequencyHz: 700,
      amplitude: 0.02,
      duration: const Duration(milliseconds: 500),
    );
    final speech = _sinePcm(
      sampleRate: sampleRate,
      frequencyHz: 500,
      amplitude: 0.2,
      duration: const Duration(milliseconds: 500),
    );

    final calibrationOutput = processor.process(calibrationNoise);
    final noiseOutput = processor.process(steadyNoise);
    final speechOutput = processor.process(speech);
    final metrics = processor.metrics(
      platformNoiseSuppressionRequested: true,
      platformEchoCancellationRequested: true,
      platformAutoGainRequested: true,
    );

    expect(_rms(calibrationOutput) / _rms(calibrationNoise), greaterThan(0.9));
    expect(_rms(noiseOutput) / _rms(steadyNoise), lessThan(0.65));
    expect(_rms(speechOutput) / _rms(speech), greaterThan(0.85));
    expect(metrics.pcmHighPassApplied, isTrue);
    expect(metrics.pcmAdaptiveNoiseGateApplied, isTrue);
    expect(metrics.estimatedSnrDb, greaterThan(12));
    expect(metrics.clippingRatio, 0);
  });

  test('keeps PCM byte length and reports clipping without voice data', () {
    final processor = PcmSpeechPreprocessor(sampleRate: sampleRate);
    final input = Uint8List.fromList(<int>[0xff, 0x7f, 0x00, 0x80, 0x55]);

    final output = processor.process(input);
    final metrics = processor.metrics(
      platformNoiseSuppressionRequested: true,
      platformEchoCancellationRequested: true,
      platformAutoGainRequested: true,
      platformNoiseSuppressionApplied: true,
    );

    expect(output, hasLength(input.length));
    expect(output.last, input.last);
    expect(metrics.clippingRatio, 1);
    expect(
      metrics.toJson(),
      containsPair('platformNoiseSuppressionApplied', true),
    );
  });
}

Uint8List _sinePcm({
  required int sampleRate,
  required double frequencyHz,
  required double amplitude,
  required Duration duration,
}) {
  final sampleCount =
      (sampleRate * duration.inMicroseconds) ~/ Duration.microsecondsPerSecond;
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < sampleCount; index += 1) {
    final sample =
        amplitude * math.sin(2 * math.pi * frequencyHz * index / sampleRate);
    data.setInt16(
      index * 2,
      (sample * 32767).round().clamp(-32768, 32767).toInt(),
      Endian.little,
    );
  }
  return bytes;
}

double _rms(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  var energy = 0.0;
  for (var index = 0; index < sampleCount; index += 1) {
    final sample = data.getInt16(index * 2, Endian.little) / 32768.0;
    energy += sample * sample;
  }
  return math.sqrt(energy / math.max(1, sampleCount));
}
