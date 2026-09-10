import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks the exact V3 child-facing menu and completion copy', () {
    expect(
      VocabularyFlowV3.todayEmptyMenu,
      'Hôm nay chưa có nội dung mới. Bạn muốn học Ba mẹ đã thêm, Luyện lại hay Ngôi sao?',
    );
    expect(
      VocabularyFlowV3.todayCompletion,
      'Bạn muốn học tiếp hay học nội dung khác?',
    );
    expect(
      VocabularyFlowV3.parentGroupCompletion,
      'Bạn muốn nghe tiếp hay học nội dung khác?',
    );
    expect(
      VocabularyFlowV3.reviewGroupCompletion,
      'Bạn muốn luyện tiếp hay học nội dung khác?',
    );
    expect(
      VocabularyFlowV3.starGroupCompletion,
      'Bạn muốn nghe thêm hay học nội dung khác?',
    );
    expect(
      VocabularyFlowV3.starScopeRetry,
      'Bạn chọn Ngôi sao mới nhất hoặc nghe lại tất cả nhé.',
    );
    expect(VocabularyFlowV3.stopHere, 'Mình dừng ở đây nhé.');
  });

  test('star transition cues rotate without a consecutive repeat', () {
    expect(VocabularyFlowV3.starNextCues, hasLength(5));
    expect(VocabularyFlowV3.starNextCues.toSet(), hasLength(5));
    for (var index = 1; index < VocabularyFlowV3.starNextCues.length; index++) {
      expect(
        VocabularyFlowV3.starNextCues[index],
        isNot(VocabularyFlowV3.starNextCues[index - 1]),
      );
    }
  });

  test('latest is newest first while all playback is oldest first', () {
    final entries = <VocabularyEntry>[
      _entry('middle', DateTime(2026, 9, 2)),
      _entry('oldest', DateTime(2026, 9, 1)),
      _entry('newest', DateTime(2026, 9, 3)),
    ];

    final latest = VocabularyFlowV3.orderedForPlayback(
      entries,
      journey: VocabularyJourneyKind.stars,
      scope: VocabularyPlaybackScope.latest,
    );
    final all = VocabularyFlowV3.orderedForPlayback(
      entries,
      journey: VocabularyJourneyKind.stars,
      scope: VocabularyPlaybackScope.all,
    );

    expect(latest.map((entry) => entry.id), <String>[
      'newest',
      'middle',
      'oldest',
    ]);
    expect(all.map((entry) => entry.id), <String>[
      'oldest',
      'middle',
      'newest',
    ]);
  });

  test(
    'Alphabet accepts the keyword alone but parent content is unchanged',
    () {
      final alphabet = VocabularyEntry(
        id: 'alphabet',
        word: 'A. Apple.',
        meaning: 'A. Quả táo.',
        addedAt: DateTime(2026, 9, 10),
        source: VocabularySource.topicCore,
      );
      final parent = VocabularyEntry(
        id: 'parent',
        word: 'A. Apple.',
        meaning: 'A. Quả táo.',
        addedAt: DateTime(2026, 9, 10),
      );

      expect(VocabularyFlowV3.acceptedVariantsFor(alphabet), <String>[
        'Apple.',
      ]);
      expect(VocabularyFlowV3.acceptedVariantsFor(parent), isEmpty);
    },
  );
}

VocabularyEntry _entry(String id, DateTime earnedAt) => VocabularyEntry(
  id: id,
  word: id,
  meaning: id,
  addedAt: earnedAt.subtract(const Duration(days: 10)),
  collection: VocabularyCollection.star,
  source: VocabularySource.topicCore,
  earnedAt: earnedAt,
  correctAudioPath: '/audio/$id.wav',
);
