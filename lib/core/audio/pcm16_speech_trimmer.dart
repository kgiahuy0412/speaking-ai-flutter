import 'dart:math' as math;
import 'dart:typed_data';

class Pcm16SpeechTrimResult {
  const Pcm16SpeechTrimResult({
    required this.bytes,
    required this.originalByteLength,
    required this.sourceStartByte,
    required this.sourceEndByte,
    required this.sampleRate,
    required this.trimmed,
    required this.reason,
    this.thresholdRms,
  });

  final Uint8List bytes;
  final int originalByteLength;
  final int sourceStartByte;
  final int sourceEndByte;
  final int sampleRate;
  final bool trimmed;
  final String reason;
  final double? thresholdRms;

  int get trimmedByteLength => originalByteLength - bytes.length;

  int get trimmedDurationMs =>
      (trimmedByteLength * 1000) ~/ math.max(1, sampleRate * 2);

  int get leadingTrimDurationMs =>
      (sourceStartByte * 1000) ~/ math.max(1, sampleRate * 2);

  int get trailingTrimDurationMs =>
      ((originalByteLength - sourceEndByte) * 1000) ~/
      math.max(1, sampleRate * 2);
}

/// Conservatively removes only well-supported silence around mono PCM16.
///
/// The retained range includes generous leading/trailing padding. When speech
/// cannot be identified confidently, or the saving is too small, the original
/// bytes are returned unchanged. This keeps quiet child speech intact while
/// avoiding upload/model work for long browser calibration and VAD tails.
Pcm16SpeechTrimResult trimPcm16SpeechForAsr(
  Uint8List pcmBytes, {
  int sampleRate = 16000,
  int analysisWindowMs = 20,
  int leadingPaddingMs = 280,
  int trailingPaddingMs = 420,
  int minimumUsefulSavingMs = 220,
  int minimumRetainedAudioMs = 500,
}) {
  final usableByteLength = pcmBytes.length - (pcmBytes.length % 2);
  if (sampleRate <= 0 || usableByteLength <= 0) {
    return _unchangedTrimResult(
      pcmBytes,
      sampleRate: sampleRate,
      reason: 'invalid_pcm',
    );
  }
  final sampleCount = usableByteLength ~/ 2;
  final frameSamples = math.max(
    1,
    (sampleRate * analysisWindowMs / 1000).round(),
  );
  final input = ByteData.sublistView(pcmBytes, 0, usableByteLength);
  final frameRms = <double>[];
  for (var start = 0; start < sampleCount; start += frameSamples) {
    final end = math.min(sampleCount, start + frameSamples);
    var energy = 0.0;
    for (var index = start; index < end; index += 1) {
      final sample = input.getInt16(index * 2, Endian.little) / 32768.0;
      energy += sample * sample;
    }
    frameRms.add(math.sqrt(energy / math.max(1, end - start)));
  }
  if (frameRms.length < 3) {
    return _unchangedTrimResult(
      pcmBytes,
      sampleRate: sampleRate,
      reason: 'audio_too_short',
    );
  }

  final sortedRms = List<double>.of(frameRms)..sort();
  final quietIndex = ((sortedRms.length - 1) * 0.2).floor();
  final quietRms = sortedRms[quietIndex];
  // The lower bound avoids treating quantization noise as speech. The upper
  // bound prevents a noisy environment from raising the gate enough to cut a
  // softly spoken word.
  final thresholdRms = (quietRms * 2.4).clamp(0.006, 0.025).toDouble();
  final active = frameRms.map((value) => value >= thresholdRms).toList();

  bool hasNeighbourSupport(int index) {
    var activeCount = 0;
    final first = math.max(0, index - 1);
    final last = math.min(active.length - 1, index + 2);
    for (var candidate = first; candidate <= last; candidate += 1) {
      if (active[candidate]) activeCount += 1;
    }
    return activeCount >= 2;
  }

  var firstActive = -1;
  var lastActive = -1;
  for (var index = 0; index < active.length; index += 1) {
    if (active[index] && hasNeighbourSupport(index)) {
      firstActive = index;
      break;
    }
  }
  for (var index = active.length - 1; index >= 0; index -= 1) {
    if (active[index] && hasNeighbourSupport(index)) {
      lastActive = index;
      break;
    }
  }
  if (firstActive < 0 || lastActive < firstActive) {
    return _unchangedTrimResult(
      pcmBytes,
      sampleRate: sampleRate,
      reason: 'speech_not_found',
      thresholdRms: thresholdRms,
    );
  }

  final leadingPaddingSamples = (sampleRate * leadingPaddingMs / 1000).round();
  final trailingPaddingSamples = (sampleRate * trailingPaddingMs / 1000)
      .round();
  final startSample = math.max(
    0,
    firstActive * frameSamples - leadingPaddingSamples,
  );
  final endSample = math.min(
    sampleCount,
    (lastActive + 1) * frameSamples + trailingPaddingSamples,
  );
  final retainedSamples = endSample - startSample;
  final savedSamples = sampleCount - retainedSamples;
  final minimumSavingSamples = (sampleRate * minimumUsefulSavingMs / 1000)
      .round();
  final minimumRetainedSamples = (sampleRate * minimumRetainedAudioMs / 1000)
      .round();
  if (savedSamples < minimumSavingSamples ||
      retainedSamples < minimumRetainedSamples) {
    return _unchangedTrimResult(
      pcmBytes,
      sampleRate: sampleRate,
      reason: 'saving_too_small',
      thresholdRms: thresholdRms,
    );
  }

  final startByte = startSample * 2;
  final endByte = endSample * 2;
  return Pcm16SpeechTrimResult(
    bytes: Uint8List.fromList(
      Uint8List.sublistView(pcmBytes, startByte, endByte),
    ),
    originalByteLength: usableByteLength,
    sourceStartByte: startByte,
    sourceEndByte: endByte,
    sampleRate: sampleRate,
    trimmed: true,
    reason: 'trimmed',
    thresholdRms: thresholdRms,
  );
}

Pcm16SpeechTrimResult _unchangedTrimResult(
  Uint8List pcmBytes, {
  required int sampleRate,
  required String reason,
  double? thresholdRms,
}) {
  return Pcm16SpeechTrimResult(
    bytes: Uint8List.fromList(pcmBytes),
    originalByteLength: pcmBytes.length,
    sourceStartByte: 0,
    sourceEndByte: pcmBytes.length,
    sampleRate: sampleRate,
    trimmed: false,
    reason: reason,
    thresholdRms: thresholdRms,
  );
}
