import 'dart:math' as math;
import 'dart:typed_data';

/// Streaming mono PCM16 resampler intended for microphone audio.
///
/// Each output sample is the area-weighted average of the source samples that
/// overlap its time window. This behaves as a small box low-pass filter while
/// downsampling and, unlike per-chunk interpolation, keeps timing continuous
/// across arbitrary browser AudioWorklet buffer boundaries.
class Pcm16MonoResampler {
  Pcm16MonoResampler({
    required this.sourceSampleRate,
    required this.targetSampleRate,
  }) : assert(sourceSampleRate > 0),
       assert(targetSampleRate > 0),
       _sourceSamplesPerOutput = sourceSampleRate / targetSampleRate,
       _nextOutputBoundary = sourceSampleRate / targetSampleRate;

  final int sourceSampleRate;
  final int targetSampleRate;
  final double _sourceSamplesPerOutput;
  final BytesBuilder _pendingBytes = BytesBuilder(copy: false);

  double _sourcePosition = 0;
  double _nextOutputBoundary;
  double _weightedSum = 0;
  double _weight = 0;
  bool _closed = false;

  Uint8List process(Uint8List pcm16Bytes) {
    if (_closed) {
      throw StateError('PCM resampler has already been flushed.');
    }
    if (pcm16Bytes.isEmpty) {
      return Uint8List(0);
    }

    _pendingBytes.add(pcm16Bytes);
    final pending = _pendingBytes.takeBytes();
    final usableLength = pending.length - (pending.length % 2);
    if (usableLength < pending.length) {
      _pendingBytes.add(Uint8List.sublistView(pending, usableLength));
    }
    if (usableLength == 0) {
      return Uint8List(0);
    }
    if (sourceSampleRate == targetSampleRate) {
      return Uint8List.fromList(
        Uint8List.sublistView(pending, 0, usableLength),
      );
    }

    final input = ByteData.sublistView(pending, 0, usableLength);
    final outputSamples = <int>[];
    const epsilon = 1e-9;

    for (var offset = 0; offset < usableLength; offset += 2) {
      final sample = input.getInt16(offset, Endian.little).toDouble();
      var remaining = 1.0;

      while (remaining > epsilon) {
        final untilBoundary = math.max(
          0.0,
          _nextOutputBoundary - _sourcePosition,
        );
        final portion = math.min(remaining, untilBoundary);

        if (portion > epsilon) {
          _weightedSum += sample * portion;
          _weight += portion;
          _sourcePosition += portion;
          remaining -= portion;
        }

        if (_sourcePosition + epsilon >= _nextOutputBoundary) {
          outputSamples.add(_finishOutputSample());
          _sourcePosition = _nextOutputBoundary;
          _nextOutputBoundary += _sourceSamplesPerOutput;
        } else if (portion <= epsilon) {
          // Floating-point drift must never leave the loop stuck between two
          // adjacent output windows.
          _nextOutputBoundary += _sourceSamplesPerOutput;
        }
      }
    }

    return _encode(outputSamples);
  }

  /// Emits the final fractional output window, if the recording did not end
  /// exactly on a target-sample boundary.
  Uint8List flush() {
    if (_closed) {
      return Uint8List(0);
    }
    _closed = true;
    _pendingBytes.takeBytes();
    if (_weight <= 1e-9 || sourceSampleRate == targetSampleRate) {
      return Uint8List(0);
    }
    return _encode(<int>[_finishOutputSample()]);
  }

  int _finishOutputSample() {
    final value = _weight <= 1e-9 ? 0 : (_weightedSum / _weight).round();
    _weightedSum = 0;
    _weight = 0;
    return value.clamp(-32768, 32767).toInt();
  }

  static Uint8List _encode(List<int> samples) {
    if (samples.isEmpty) {
      return Uint8List(0);
    }
    final output = Uint8List(samples.length * 2);
    final data = ByteData.sublistView(output);
    for (var index = 0; index < samples.length; index += 1) {
      data.setInt16(index * 2, samples[index], Endian.little);
    }
    return output;
  }
}
