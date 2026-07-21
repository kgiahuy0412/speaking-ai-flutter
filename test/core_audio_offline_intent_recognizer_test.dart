import 'package:ai_speaking_flutter_app/core/audio/offline_intent_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = OfflineIntentPolicy(
    confidenceThreshold: 0.88,
    marginThreshold: 0.15,
    stableUpdates: 3,
    earlyFallbackMs: 800,
  );

  test('manifest resolves cached audio URLs against the backend', () {
    final manifest = OfflineIntentManifest.fromJson(<String, dynamic>{
      'version': 'v1',
      'sampleRate': 24000,
      'policy': <String, dynamic>{
        'confidenceThreshold': 0.88,
        'marginThreshold': 0.15,
        'stableUpdates': 3,
        'earlyFallbackMs': 800,
      },
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'drink_water',
          'contexts': <String>['home', 'school'],
          'samples': <String>['Con muốn uống nước'],
          'englishText': 'Can I have some water, please?',
          'audioUrl': '/generated-audio/water.mp3',
        },
      ],
    }, backendBaseUri: Uri.parse('https://api.example.com'));

    expect(manifest.items, hasLength(1));
    expect(
      manifest.items.single.audioUri,
      Uri.parse('https://api.example.com/generated-audio/water.mp3'),
    );
    expect(manifest.policy.earlyFallbackMs, 800);
  });

  test('gate requires high confidence, a clear margin and three updates', () {
    final gate = OfflineIntentGate(policy);

    expect(gate.evaluate(_hypothesis(confidence: 0.87, runnerUp: 0.1)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.92, runnerUp: 0.8)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.92, runnerUp: 0.2)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.93, runnerUp: 0.2)), isNull);

    final decision = gate.evaluate(
      _hypothesis(confidence: 0.94, runnerUp: 0.2),
    );
    expect(decision?.hypothesis.intentId, 'drink_water');
    expect(decision?.margin, closeTo(0.74, 0.001));
  });

  test('an uncertain update resets stability to avoid a false rule', () {
    final gate = OfflineIntentGate(policy);

    expect(gate.evaluate(_hypothesis(confidence: 0.94, runnerUp: 0.2)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.95, runnerUp: 0.2)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.7, runnerUp: 0.3)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.96, runnerUp: 0.2)), isNull);
    expect(gate.evaluate(_hypothesis(confidence: 0.96, runnerUp: 0.2)), isNull);
    expect(
      gate.evaluate(_hypothesis(confidence: 0.96, runnerUp: 0.2)),
      isNotNull,
    );
  });
}

OfflineIntentHypothesis _hypothesis({
  required double confidence,
  required double runnerUp,
}) {
  return OfflineIntentHypothesis(
    intentId: 'drink_water',
    transcript: 'Con muốn uống nước',
    confidence: confidence,
    alternatives: <OfflineIntentAlternative>[
      OfflineIntentAlternative(intentId: 'ask_teacher', confidence: runnerUp),
    ],
  );
}
