import 'package:ai_speaking_flutter_app/core/audio/adaptive_voice_activity_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects a soft voice above a quiet ambient floor', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-62, -61, -63, -62, -61]);

    final updates = _feed(detector, const <double>[
      -44,
      -38,
      -43,
    ], startMs: 450);

    expect(updates.last.speechStarted, isTrue);
    expect(updates.last.voiceActive, isTrue);
    expect(updates.last.startThresholdDbfs, closeTo(-46, 0.01));
  });

  test('rejects a short impact in a quiet room', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-61, -60, -62, -61, -60]);

    final updates = _feed(detector, const <double>[
      -10,
      -60,
      -59,
      -61,
    ], startMs: 450);

    expect(updates.any((update) => update.speechStarted), isFalse);
    expect(updates.last.voiceActive, isFalse);
  });

  test('learns a steady fan instead of treating it as speech', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-62, -61, -63, -62, -61]);

    final updates = _feed(detector, const <double>[
      -29,
      -29.4,
      -28.8,
      -29.2,
      -29,
      -29.3,
      -28.9,
      -29.1,
    ], startMs: 450);

    expect(updates.any((update) => update.speechStarted), isFalse);
    expect(detector.noiseFloorDbfs, closeTo(-29.1, 0.3));
    expect(updates.last.noisyEnvironment, isTrue);
  });

  test('detects speech that rises above an already noisy room', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-35, -34, -33, -35, -34]);

    final updates = _feed(detector, const <double>[
      -22,
      -12,
      -20,
    ], startMs: 450);

    expect(updates.last.speechStarted, isTrue);
    expect(updates.last.voiceActive, isTrue);
    expect(updates.last.noisyEnvironment, isTrue);
    expect(updates.last.startThresholdDbfs, greaterThan(-27));
  });

  test('uses hysteresis so a brief level dip does not end speech', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-62, -61, -63, -62, -61]);
    _feed(detector, const <double>[-42, -28, -36], startMs: 450);

    final shortDip = detector.addSample(
      -48,
      elapsed: const Duration(milliseconds: 720),
    );
    final silence = detector.addSample(
      -56,
      elapsed: const Duration(milliseconds: 810),
    );

    expect(shortDip.voiceActive, isTrue);
    expect(silence.voiceActive, isFalse);
  });

  test('accepts an ASR partial result as stronger speech evidence', () {
    final detector = AdaptiveVoiceActivityDetector();
    _calibrate(detector, const <double>[-58, -57, -59, -58, -57]);

    detector.confirmSpeech();
    final voice = detector.addSample(
      -35,
      elapsed: const Duration(milliseconds: 450),
    );
    final silence = detector.addSample(
      -60,
      elapsed: const Duration(milliseconds: 540),
    );

    expect(voice.speechStarted, isFalse);
    expect(voice.voiceActive, isTrue);
    expect(silence.voiceActive, isFalse);
  });
}

void _calibrate(AdaptiveVoiceActivityDetector detector, List<double> levels) {
  _feed(detector, levels);
}

List<VoiceActivityUpdate> _feed(
  AdaptiveVoiceActivityDetector detector,
  List<double> levels, {
  int startMs = 0,
  int stepMs = 90,
}) => <VoiceActivityUpdate>[
  for (var index = 0; index < levels.length; index += 1)
    detector.addSample(
      levels[index],
      elapsed: Duration(milliseconds: startMs + (index * stepMs)),
    ),
];
