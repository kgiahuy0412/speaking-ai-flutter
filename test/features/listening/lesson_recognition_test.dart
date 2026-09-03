import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = LessonRecognitionMatcher();

  group('normalizeLessonRecognitionText', () {
    test(
      'normalizes Unicode punctuation, whitespace, contractions, and digits',
      () {
        expect(
          normalizeLessonRecognitionText('  I’m\u00a0not—sure!  '),
          'i am not sure',
        );
        expect(normalizeLessonRecognitionText('8 o’clock'), 'eight o clock');
        expect(normalizeLessonRecognitionText('T‑shirt'), 't shirt');
      },
    );
  });

  group('LessonRecognitionMatcher', () {
    test('accepts a normalized authored target', () {
      final result = matcher.match(
        expectedEnglish: "I'm not sure.",
        transcript: 'I am not sure',
      );

      expect(result.matched, isTrue);
      expect(result.kind, LessonRecognitionMatchKind.exact);
    });

    test('uses a declared ASR variant without accepting it globally', () {
      final withoutVariant = matcher.match(
        expectedEnglish: 'Can I come in?',
        transcript: 'Can eye come in',
      );
      final withVariant = matcher.match(
        expectedEnglish: 'Can I come in?',
        transcript: 'Can eye come in',
        acceptedVariants: const <String>['Can eye come in'],
      );

      expect(withoutVariant.matched, isFalse);
      expect(withVariant.matched, isTrue);
      expect(withVariant.kind, LessonRecognitionMatchKind.acceptedVariant);
    });

    test('requires both the letter and keyword for an Alphabet target', () {
      expect(
        matcher.matches(
          expectedEnglish: 'A. Apple.',
          transcript: 'Apple',
          requireAllExpectedTokens: true,
        ),
        isFalse,
      );
      expect(
        matcher.matches(
          expectedEnglish: 'A. Apple.',
          transcript: 'A',
          requireAllExpectedTokens: true,
        ),
        isFalse,
      );
      expect(
        matcher.matches(
          expectedEnglish: 'A. Apple.',
          transcript: 'A, Apple!',
          requireAllExpectedTokens: true,
        ),
        isTrue,
      );
    });

    test('does not fuzzy-match a different short-word answer option', () {
      expect(
        matcher.matches(expectedEnglish: "It's red.", transcript: "It's read."),
        isFalse,
      );
      expect(
        matcher.matches(expectedEnglish: "It's red.", transcript: "It's blue."),
        isFalse,
      );
    });

    test(
      'allows one safe spelling slip in a longer, otherwise exact target',
      () {
        final result = matcher.match(
          expectedEnglish: 'I study after school.',
          transcript: 'I study after schol.',
        );

        expect(result.matched, isTrue);
        expect(result.kind, LessonRecognitionMatchKind.fuzzy);
      },
    );

    test('allows bounded filler around the full answer only', () {
      final bounded = matcher.match(
        expectedEnglish: 'I study after school.',
        transcript: 'Okay, I study after school.',
      );
      final unbounded = matcher.match(
        expectedEnglish: 'I study after school.',
        transcript: 'Well okay please I study after school now',
      );

      expect(bounded.matched, isTrue);
      expect(bounded.kind, LessonRecognitionMatchKind.containedExpected);
      expect(unbounded.matched, isFalse);
    });

    test('does not let a fuzzy match bypass a missing expected token', () {
      expect(
        matcher.matches(
          expectedEnglish: 'Keep passwords private.',
          transcript: 'Keep password private.',
          requireAllExpectedTokens: true,
        ),
        isFalse,
      );
    });
  });
}
