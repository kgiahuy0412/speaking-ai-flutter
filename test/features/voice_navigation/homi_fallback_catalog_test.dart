import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomiFallbackCatalog', () {
    test(
      'preserves the approved catalog counts and structurally valid records',
      () {
        final literalPhraseCount = HomiFallbackCatalog
            .childPhrasesByIntent
            .values
            .fold<int>(0, (count, phrases) => count + phrases.length);
        final numericTemplateCount = HomiFallbackCatalog
            .numericChildPatternsByIntent
            .values
            .fold<int>(0, (count, patterns) => count + patterns.length);

        expect(HomiFallbackCatalog.childPhrasesByIntent, hasLength(21));
        expect(HomiFallbackCatalog.literalChildPhraseCount, 488);
        expect(literalPhraseCount, HomiFallbackCatalog.literalChildPhraseCount);
        expect(HomiFallbackCatalog.numericChildTemplateCount, 12);
        expect(
          numericTemplateCount,
          HomiFallbackCatalog.numericChildTemplateCount,
        );
        expect(HomiFallbackCatalog.assistantPromptById, hasLength(69));
        expect(HomiFallbackCatalog.silencePromptById, hasLength(9));
        expect(HomiFallbackCatalog.fallbackPolicyById, hasLength(8));

        for (final entry in HomiFallbackCatalog.childPhrasesByIntent.entries) {
          expect(entry.key, matches(r'^INT-\d{3}$'));
          for (final phrase in entry.value) {
            expect(
              HomiFallbackCatalog.normalizeVietnamese(phrase),
              isNotEmpty,
              reason: '${entry.key}: $phrase',
            );
          }
        }
        for (final patterns
            in HomiFallbackCatalog.numericChildPatternsByIntent.values) {
          for (final pattern in patterns) {
            expect(pattern.raw, isNotEmpty);
            expect(
              pattern.literalSegments.length,
              pattern.placeholderNames.length + 1,
              reason: pattern.raw,
            );
            expect(pattern.placeholderNames, everyElement(isNotEmpty));
          }
        }
        for (final entry in HomiFallbackCatalog.fallbackPolicyById.entries) {
          expect(entry.value.id, entry.key);
          expect(entry.value.context, isNotEmpty);
          expect(entry.value.firstPrompt, isNotEmpty);
        }
      },
    );

    test('keeps colliding commands explicit for state-aware callers', () {
      final stopIntentIds = HomiFallbackCatalog.childPhrasesByIntent.entries
          .where(
            (entry) => entry.value.any(
              (phrase) =>
                  HomiFallbackCatalog.matchesWholePhrase('Dừng lại', phrase),
            ),
          )
          .map((entry) => entry.key);

      expect(stopIntentIds, unorderedEquals(<String>['INT-001', 'INT-018']));
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-001', 'Dừng lại'),
        isTrue,
      );
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-018', 'Dừng lại'),
        isTrue,
      );
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-010', 'Dừng lại'),
        isFalse,
      );

      // "Học lại" has different meanings in lesson, vocabulary, and
      // confirmation states. The catalog must retain those separate IDs.
      for (final intentId in <String>['INT-011', 'INT-014', 'INT-019']) {
        expect(
          HomiFallbackCatalog.matchesChildPhrase(intentId, 'Học lại'),
          isTrue,
        );
      }
    });

    test('recognizes representative controlled-command fallback variants', () {
      const expectedIntentByPhrase = <String, String>{
        'Mình hổng muốn học nữa': 'INT-001',
        'Học bài ni': 'INT-002',
        'Học chữ ni': 'INT-003',
        'Qua câu kế đi': 'INT-008',
        'Ôn lại mấy chữ này nè': 'INT-014',
        'Giờ mình làm cái chi?': 'INT-016',
      };

      for (final entry in expectedIntentByPhrase.entries) {
        expect(
          HomiFallbackCatalog.matchesChildPhrase(entry.value, entry.key),
          isTrue,
          reason: '${entry.key} should resolve as ${entry.value}',
        );
      }
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-010', '  NGHE LẠI!!! '),
        isTrue,
      );
      expect(
        HomiFallbackCatalog.matchesChildPhrase(
          'INT-010',
          'Bây giờ bạn nghe lại giúp mình',
        ),
        isFalse,
        reason: 'Fallback matching must not accept a partial phrase.',
      );
    });

    test('provides main-assistant yes, no, and number choices safely', () {
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-019', 'Oki luôn'),
        isTrue,
      );
      expect(HomiFallbackCatalog.matchesChildPhrase('INT-020', 'Hổng'), isTrue);
      expect(HomiFallbackCatalog.matchesChildPhrase('INT-021', '14'), isTrue);

      final numberPatterns =
          HomiFallbackCatalog.numericChildPatternsByIntent['INT-021']!;
      expect(
        numberPatterns.map((pattern) => pattern.raw),
        containsAll(<String>[
          'Mình [số] tuổi',
          'Chủ đề số [số]',
          'Cho mình bài số [số]',
        ]),
      );
      expect(
        HomiFallbackCatalog.matchesChildPhrase('INT-021', 'Mình 6 tuổi'),
        isFalse,
        reason:
            'Numeric templates stay separate so only a number-expecting state can activate them.',
      );
      expect(
        HomiFallbackCatalog.assistantPromptById['AI-016'],
        contains('“có” hoặc “không”'),
      );
    });

    test(
      'keeps continuous translation requests out of one-shot translation',
      () {
        expect(
          HomiFallbackCatalog.matchesChildPhrase(
            'INT-006',
            'Mở chế độ dịch liên tục giúp mình',
          ),
          isTrue,
        );
        expect(
          HomiFallbackCatalog.matchesChildPhrase(
            'INT-004',
            'Mở chế độ dịch liên tục giúp mình',
          ),
          isFalse,
        );
        expect(
          HomiFallbackCatalog.matchesChildPhrase(
            'INT-018',
            'Dừng dịch liên tục',
          ),
          isTrue,
        );
        expect(
          HomiFallbackCatalog.fallbackPolicyById['FB-009']?.context,
          'Dịch liên tục',
        );
      },
    );

    test(
      'accepts approved HOMI wake-word variants but not incidental mentions',
      () {
        for (final phrase in <String>[
          'Hey HÔMI',
          'Hay HOMIE',
          'Ê HOMPI',
          'Hôm-mi ơi',
          'HOMI nghe mình nói không?',
        ]) {
          expect(
            HomiFallbackCatalog.matchesChildPhrase('INT-022', phrase),
            isTrue,
            reason: phrase,
          );
        }
        expect(
          HomiFallbackCatalog.matchesChildPhrase('INT-022', 'Mình thích HOMI'),
          isFalse,
        );
      },
    );
  });
}
