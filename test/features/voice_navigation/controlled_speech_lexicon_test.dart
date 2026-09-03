import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/controlled_speech_lexicon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lexicon = ControlledSpeechLexicon();

  test(
    'contains the approved HOMI fallback expansion of the controlled grammar',
    () {
      final phraseCount = ControlledSpeechLexicon.rules.fold<int>(
        0,
        (count, rule) => count + rule.phrases.length,
      );

      expect(ControlledSpeechLexicon.version, 'V0.2-homi-fallback');
      expect(phraseCount, 377);
    },
  );

  test('every controlled phrase resolves to its declared intent', () {
    for (final rule in ControlledSpeechLexicon.rules) {
      final state = rule.global
          ? ControlledSpeechState.root
          : rule.states.first;
      for (final phrase in rule.phrases) {
        final match = lexicon.resolve(phrase, state: state);
        expect(match, isNotNull, reason: '$phrase in $state');
        expect(match!.intent, rule.intent, reason: '$phrase in $state');
      }
    }
  });

  test('routes duplicated phrases by the current state', () {
    expect(
      lexicon.resolve('Dịch', state: ControlledSpeechState.root)?.intent,
      ControlledSpeechIntent.navTranslate,
    );
    expect(
      lexicon
          .resolve('Dịch', state: ControlledSpeechState.translateMenu)
          ?.intent,
      ControlledSpeechIntent.translateSingle,
    );
    expect(
      lexicon
          .resolve('Nói lại đi', state: ControlledSpeechState.course)
          ?.intent,
      ControlledSpeechIntent.courseReplayCurrent,
    );
    expect(
      lexicon.resolve('Nói lại đi', state: ControlledSpeechState.root)?.intent,
      ControlledSpeechIntent.globalHelp,
    );
    expect(
      lexicon.resolve('Học lại', state: ControlledSpeechState.course)?.intent,
      ControlledSpeechIntent.courseRestartCurrent,
    );
    expect(
      lexicon
          .resolve('Học lại', state: ControlledSpeechState.vocabulary)
          ?.intent,
      ControlledSpeechIntent.vocabularyPracticeAgain,
    );
  });

  test('normalizes Vietnamese accents, punctuation and whitespace', () {
    expect(
      lexicon
          .resolve(
            '  DỊCH   CÂU NÀY!!! ',
            state: ControlledSpeechState.translateMenu,
          )
          ?.intent,
      ControlledSpeechIntent.translateSingle,
    );
  });

  test('global stop wins across N-best candidates and every state', () {
    final match = lexicon.resolveCandidates(const <String>[
      'Học tiếp',
      'Dừng lại',
    ], state: ControlledSpeechState.course);

    expect(match?.intent, ControlledSpeechIntent.globalStop);
    expect(match?.priority, 0);
  });

  test('does not guess from an uncontrolled sentence', () {
    expect(
      lexicon.resolve(
        'Hôm nay con đã học ở trường',
        state: ControlledSpeechState.root,
      ),
      isNull,
    );
  });
}
