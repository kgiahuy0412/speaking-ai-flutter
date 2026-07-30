class VoiceActivityUpdate {
  const VoiceActivityUpdate({
    required this.speechStarted,
    required this.voiceActive,
    required this.isCalibrating,
    required this.noisyEnvironment,
    required this.noiseFloorDbfs,
    required this.startThresholdDbfs,
    required this.stopThresholdDbfs,
  });

  /// True only for the sample that confirms the start of speech.
  final bool speechStarted;
  final bool voiceActive;
  final bool isCalibrating;
  final bool noisyEnvironment;
  final double noiseFloorDbfs;
  final double startThresholdDbfs;
  final double stopThresholdDbfs;
}

/// Volume-based VAD shared by the browser, Android microphone and Bluetooth
/// capture paths.
///
/// The detector learns the ambient level at the beginning of each recording,
/// follows gradual changes while nobody is speaking, and uses separate start
/// and stop thresholds. Requiring a small amount of speech-like level
/// variation rejects short impacts and steady fan/air-conditioner noise.
class AdaptiveVoiceActivityDetector {
  AdaptiveVoiceActivityDetector({
    this.calibrationDuration = const Duration(milliseconds: 300),
    this.minimumSpeechDuration = const Duration(milliseconds: 180),
    this.steadyNoiseDuration = const Duration(milliseconds: 630),
    this.minimumSpeechVariationDb = 4,
    this.startMarginDb = 10,
    this.stopMarginDb = 6,
    this.noisyFloorDbfs = -36,
  });

  final Duration calibrationDuration;
  final Duration minimumSpeechDuration;
  final Duration steadyNoiseDuration;
  final double minimumSpeechVariationDb;
  final double startMarginDb;
  final double stopMarginDb;
  final double noisyFloorDbfs;

  final List<double> _calibrationSamples = <double>[];
  bool _calibrated = false;
  bool _speechConfirmed = false;
  double _noiseFloorDbfs = -60;
  Duration? _candidateStartedAt;
  double _candidateMinimum = 0;
  double _candidateMaximum = -90;
  double _candidateTotal = 0;
  int _candidateSamples = 0;

  double get noiseFloorDbfs => _noiseFloorDbfs;

  double get startThresholdDbfs =>
      (_noiseFloorDbfs + startMarginDb).clamp(-46.0, -8.0).toDouble();

  double get stopThresholdDbfs {
    final adaptive = (_noiseFloorDbfs + stopMarginDb)
        .clamp(-50.0, -12.0)
        .toDouble();
    return adaptive < startThresholdDbfs - 3
        ? adaptive
        : startThresholdDbfs - 3;
  }

  bool get noisyEnvironment => _noiseFloorDbfs >= noisyFloorDbfs;

  void reset() {
    _calibrationSamples.clear();
    _calibrated = false;
    _speechConfirmed = false;
    _noiseFloorDbfs = -60;
    _clearCandidate();
  }

  /// Confirms speech from a stronger signal such as an ASR partial result.
  void confirmSpeech() {
    _speechConfirmed = true;
    _clearCandidate();
  }

  VoiceActivityUpdate addSample(double dbfs, {required Duration elapsed}) {
    final level = dbfs.clamp(-90.0, 0.0).toDouble();
    var speechStarted = false;

    if (!_calibrated) {
      _calibrationSamples.add(level);
      _noiseFloorDbfs = _lowerQuartile(_calibrationSamples);
      if (elapsed < calibrationDuration || _calibrationSamples.length < 3) {
        return _update(
          speechStarted: false,
          voiceActive: false,
          isCalibrating: true,
        );
      }
      _calibrated = true;
    }

    if (!_speechConfirmed) {
      if (level >= startThresholdDbfs) {
        _addCandidate(level, elapsed);
        final candidateAge = elapsed - _candidateStartedAt!;
        final variation = _candidateMaximum - _candidateMinimum;
        if (candidateAge >= minimumSpeechDuration &&
            variation >= minimumSpeechVariationDb) {
          _speechConfirmed = true;
          speechStarted = true;
          _clearCandidate();
        } else if (candidateAge >= steadyNoiseDuration &&
            variation < minimumSpeechVariationDb) {
          // A sustained, almost-flat level is much more likely to be a fan,
          // engine or air conditioner than a spoken phrase. Promote it to the
          // ambient floor instead of treating it as speech.
          _noiseFloorDbfs = _candidateTotal / _candidateSamples;
          _clearCandidate();
        }
      } else {
        _clearCandidate();
        _followAmbientLevel(level);
      }
    }

    final voiceActive = _speechConfirmed && level >= stopThresholdDbfs;
    return _update(
      speechStarted: speechStarted,
      voiceActive: voiceActive,
      isCalibrating: false,
    );
  }

  void _addCandidate(double level, Duration elapsed) {
    _candidateStartedAt ??= elapsed;
    if (_candidateSamples == 0) {
      _candidateMinimum = level;
      _candidateMaximum = level;
    } else {
      if (level < _candidateMinimum) {
        _candidateMinimum = level;
      }
      if (level > _candidateMaximum) {
        _candidateMaximum = level;
      }
    }
    _candidateTotal += level;
    _candidateSamples += 1;
  }

  void _followAmbientLevel(double level) {
    final alpha = level < _noiseFloorDbfs ? 0.12 : 0.035;
    _noiseFloorDbfs = (_noiseFloorDbfs * (1 - alpha)) + (level * alpha);
  }

  void _clearCandidate() {
    _candidateStartedAt = null;
    _candidateMinimum = 0;
    _candidateMaximum = -90;
    _candidateTotal = 0;
    _candidateSamples = 0;
  }

  VoiceActivityUpdate _update({
    required bool speechStarted,
    required bool voiceActive,
    required bool isCalibrating,
  }) => VoiceActivityUpdate(
    speechStarted: speechStarted,
    voiceActive: voiceActive,
    isCalibrating: isCalibrating,
    noisyEnvironment: noisyEnvironment,
    noiseFloorDbfs: noiseFloorDbfs,
    startThresholdDbfs: startThresholdDbfs,
    stopThresholdDbfs: stopThresholdDbfs,
  );

  static double _lowerQuartile(List<double> samples) {
    final sorted = samples.toList(growable: false)..sort();
    final index = ((sorted.length - 1) * 0.25).floor();
    return sorted[index];
  }
}
