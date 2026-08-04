import 'dart:math' as math;
import 'dart:typed_data';

/// Non-audio telemetry produced by the capture front end.
///
/// These values are safe to attach to request benchmarks: they describe the
/// processing path and signal quality without retaining voice samples.
class AudioProcessingMetrics {
  const AudioProcessingMetrics({
    required this.platformNoiseSuppressionRequested,
    required this.platformEchoCancellationRequested,
    required this.platformAutoGainRequested,
    required this.pcmHighPassApplied,
    required this.pcmAdaptiveNoiseGateApplied,
    this.platformNoiseSuppressionApplied,
    this.platformEchoCancellationApplied,
    this.platformAutoGainApplied,
    this.highPassCutoffHz,
    this.noiseFloorDbfs,
    this.estimatedSnrDb,
    this.clippingRatio,
    this.noiseAttenuationDb,
  });

  final bool platformNoiseSuppressionRequested;
  final bool platformEchoCancellationRequested;
  final bool platformAutoGainRequested;
  final bool? platformNoiseSuppressionApplied;
  final bool? platformEchoCancellationApplied;
  final bool? platformAutoGainApplied;
  final bool pcmHighPassApplied;
  final bool pcmAdaptiveNoiseGateApplied;
  final double? highPassCutoffHz;
  final double? noiseFloorDbfs;
  final double? estimatedSnrDb;
  final double? clippingRatio;
  final double? noiseAttenuationDb;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platformNoiseSuppressionRequested': platformNoiseSuppressionRequested,
    'platformEchoCancellationRequested': platformEchoCancellationRequested,
    'platformAutoGainRequested': platformAutoGainRequested,
    if (platformNoiseSuppressionApplied != null)
      'platformNoiseSuppressionApplied': platformNoiseSuppressionApplied,
    if (platformEchoCancellationApplied != null)
      'platformEchoCancellationApplied': platformEchoCancellationApplied,
    if (platformAutoGainApplied != null)
      'platformAutoGainApplied': platformAutoGainApplied,
    'pcmHighPassApplied': pcmHighPassApplied,
    'pcmAdaptiveNoiseGateApplied': pcmAdaptiveNoiseGateApplied,
    if (highPassCutoffHz != null) 'pcmHighPassCutoffHz': highPassCutoffHz,
    if (noiseFloorDbfs != null) 'pcmNoiseFloorDbfs': noiseFloorDbfs,
    if (estimatedSnrDb != null) 'estimatedSnrDb': estimatedSnrDb,
    if (clippingRatio != null) 'pcmClippingRatio': clippingRatio,
    if (noiseAttenuationDb != null) 'pcmNoiseAttenuationDb': noiseAttenuationDb,
  };
}

/// Conservative streaming PCM16 front end for short child speech.
///
/// The processor deliberately avoids aggressive spectral subtraction. It
/// removes DC/low-frequency rumble with a first-order high-pass filter and
/// attenuates only frames close to the learned ambient floor. The first 300 ms
/// are calibration-only, so a child who speaks immediately is never gated.
class PcmSpeechPreprocessor {
  PcmSpeechPreprocessor({
    required this.sampleRate,
    this.highPassCutoffHz = 80,
    this.calibrationDuration = const Duration(milliseconds: 300),
    this.minimumNoiseGain = 0.45,
  }) : assert(sampleRate > 0),
       assert(highPassCutoffHz > 0),
       assert(minimumNoiseGain > 0 && minimumNoiseGain <= 1),
       _analysisFrameSamples = math.max(1, sampleRate ~/ 100),
       _calibrationFrameTarget = math.max(
         1,
         calibrationDuration.inMilliseconds ~/ 10,
       ),
       _highPassAlpha = _calculateHighPassAlpha(
         sampleRate: sampleRate,
         cutoffHz: highPassCutoffHz,
       );

  final int sampleRate;
  final double highPassCutoffHz;
  final Duration calibrationDuration;
  final double minimumNoiseGain;
  final int _analysisFrameSamples;
  final int _calibrationFrameTarget;
  final double _highPassAlpha;

  final List<double> _calibrationRms = <double>[];
  double? _noiseFloorRms;
  double _previousInput = 0;
  double _previousHighPassed = 0;
  double _gain = 1;
  double _inputEnergy = 0;
  double _outputEnergy = 0;
  double _speechEnergy = 0;
  int _speechSamples = 0;
  int _totalSamples = 0;
  int _clippedSamples = 0;
  bool _adaptiveGateApplied = false;

  Uint8List process(Uint8List pcm16Bytes) {
    if (pcm16Bytes.isEmpty) {
      return Uint8List(0);
    }

    final output = Uint8List(pcm16Bytes.length);
    final inputData = ByteData.sublistView(pcm16Bytes);
    final outputData = ByteData.sublistView(output);
    final sampleCount = pcm16Bytes.length ~/ 2;
    final highPassed = Float64List(sampleCount);

    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
      final offset = sampleIndex * 2;
      final encoded = inputData.getInt16(offset, Endian.little);
      final input = encoded / 32768.0;
      if (input.abs() >= 0.98) {
        _clippedSamples += 1;
      }
      _inputEnergy += input * input;
      final filtered =
          _highPassAlpha * (_previousHighPassed + input - _previousInput);
      _previousInput = input;
      _previousHighPassed = filtered;
      highPassed[sampleIndex] = filtered;
    }

    for (
      var frameStart = 0;
      frameStart < sampleCount;
      frameStart += _analysisFrameSamples
    ) {
      final frameEnd = math.min(
        sampleCount,
        frameStart + _analysisFrameSamples,
      );
      var frameEnergy = 0.0;
      for (var index = frameStart; index < frameEnd; index += 1) {
        final value = highPassed[index];
        frameEnergy += value * value;
      }
      final frameLength = frameEnd - frameStart;
      final frameRms = math.sqrt(frameEnergy / math.max(1, frameLength));
      final targetGain = _targetGain(frameRms);
      final smoothing = targetGain > _gain ? 0.65 : 0.18;
      _gain += (targetGain - _gain) * smoothing;

      final noiseFloor = _noiseFloorRms;
      if (noiseFloor != null && frameRms >= noiseFloor * 2) {
        _speechEnergy += frameEnergy;
        _speechSamples += frameLength;
      }

      for (var index = frameStart; index < frameEnd; index += 1) {
        final filtered = (highPassed[index] * _gain).clamp(-1.0, 1.0);
        _outputEnergy += filtered * filtered;
        final encoded = (filtered * 32767).round().clamp(-32768, 32767).toInt();
        outputData.setInt16(index * 2, encoded, Endian.little);
      }
    }

    if (pcm16Bytes.length.isOdd) {
      output[pcm16Bytes.length - 1] = pcm16Bytes.last;
    }
    _totalSamples += sampleCount;
    return output;
  }

  AudioProcessingMetrics metrics({
    required bool platformNoiseSuppressionRequested,
    required bool platformEchoCancellationRequested,
    required bool platformAutoGainRequested,
    bool? platformNoiseSuppressionApplied,
    bool? platformEchoCancellationApplied,
    bool? platformAutoGainApplied,
  }) {
    final noiseFloor = _noiseFloorRms;
    final speechRms = _speechSamples == 0
        ? null
        : math.sqrt(_speechEnergy / _speechSamples);
    final estimatedSnr =
        noiseFloor == null ||
            noiseFloor <= 0 ||
            speechRms == null ||
            speechRms <= 0
        ? null
        : 20 * _log10(speechRms / noiseFloor);
    final attenuation = _inputEnergy <= 0 || _outputEnergy <= 0
        ? null
        : (10 * _log10(_inputEnergy / _outputEnergy)).clamp(0.0, 30.0);

    return AudioProcessingMetrics(
      platformNoiseSuppressionRequested: platformNoiseSuppressionRequested,
      platformEchoCancellationRequested: platformEchoCancellationRequested,
      platformAutoGainRequested: platformAutoGainRequested,
      platformNoiseSuppressionApplied: platformNoiseSuppressionApplied,
      platformEchoCancellationApplied: platformEchoCancellationApplied,
      platformAutoGainApplied: platformAutoGainApplied,
      pcmHighPassApplied: _totalSamples > 0,
      pcmAdaptiveNoiseGateApplied: _adaptiveGateApplied,
      highPassCutoffHz: highPassCutoffHz,
      noiseFloorDbfs: noiseFloor == null || noiseFloor <= 0
          ? null
          : _rounded(20 * _log10(noiseFloor)),
      estimatedSnrDb: estimatedSnr == null
          ? null
          : _rounded(estimatedSnr.clamp(-20.0, 60.0)),
      clippingRatio: _totalSamples == 0
          ? null
          : _rounded(_clippedSamples / _totalSamples, digits: 6),
      noiseAttenuationDb: attenuation == null ? null : _rounded(attenuation),
    );
  }

  double _targetGain(double frameRms) {
    if (_calibrationRms.length < _calibrationFrameTarget) {
      _calibrationRms.add(frameRms);
      if (_calibrationRms.length == _calibrationFrameTarget) {
        final sorted = List<double>.of(_calibrationRms)..sort();
        final lowerQuartile = sorted[((sorted.length - 1) * 0.25).floor()];
        _noiseFloorRms = math.max(lowerQuartile, 1e-5);
      }
      return 1;
    }

    var noiseFloor = _noiseFloorRms ?? math.max(frameRms, 1e-5);
    if (frameRms < noiseFloor) {
      noiseFloor += (frameRms - noiseFloor) * 0.12;
    } else if (frameRms < noiseFloor * 1.35) {
      noiseFloor += (frameRms - noiseFloor) * 0.025;
    }
    _noiseFloorRms = math.max(noiseFloor, 1e-5);

    final snrDb = 20 * _log10(math.max(frameRms, 1e-7) / noiseFloor);
    if (snrDb >= 8) {
      return 1;
    }
    _adaptiveGateApplied = true;
    if (snrDb <= 2) {
      return minimumNoiseGain;
    }
    final progress = (snrDb - 2) / 6;
    return minimumNoiseGain + ((1 - minimumNoiseGain) * progress);
  }

  static double _calculateHighPassAlpha({
    required int sampleRate,
    required double cutoffHz,
  }) {
    final interval = 1 / sampleRate;
    final timeConstant = 1 / (2 * math.pi * cutoffHz);
    return timeConstant / (timeConstant + interval);
  }

  static double _log10(double value) => math.log(value) / math.ln10;

  static double _rounded(double value, {int digits = 2}) {
    final scale = math.pow(10, digits).toDouble();
    return (value * scale).round() / scale;
  }
}
