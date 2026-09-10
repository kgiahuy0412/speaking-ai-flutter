import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'parent daily quota is five and deleting does not restore quota',
    () async {
      const store = VocabularyStore();
      final now = DateTime(2026, 9, 10, 8);

      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
        VocabularyTranslation(
          englishText: 'Banana',
          vietnameseText: 'Quả chuối',
        ),
        VocabularyTranslation(englishText: 'Orange', vietnameseText: 'Quả cam'),
      ], now: now);
      final entries = await store
          .addParentEntries(const <VocabularyTranslation>[
            VocabularyTranslation(
              englishText: 'School',
              vietnameseText: 'Trường học',
            ),
            VocabularyTranslation(
              englishText: 'Teacher',
              vietnameseText: 'Giáo viên',
            ),
          ], now: now.add(const Duration(minutes: 1)));

      await store.deleteParentEntry(entries.first.id);

      expect(
        () => store.addParentEntries(const <VocabularyTranslation>[
          VocabularyTranslation(
            englishText: 'Friend',
            vietnameseText: 'Bạn bè',
          ),
        ], now: now.add(const Duration(minutes: 2))),
        throwsA(isA<VocabularyDailyLimitException>()),
      );
    },
  );

  test('a parent entry locks as soon as learning starts', () async {
    const store = VocabularyStore();
    final entries = await store.addParentEntries(const <VocabularyTranslation>[
      VocabularyTranslation(englishText: 'Hello', vietnameseText: 'Xin chào'),
    ], now: DateTime(2026, 9, 10, 9));
    final id = entries.single.id;

    await store.markLearningStarted(id, now: DateTime(2026, 9, 10, 10));

    expect(
      () => store.deleteParentEntry(id),
      throwsA(isA<VocabularyLockedException>()),
    );
    expect((await store.read()).single.canParentEdit, isFalse);
  });

  test(
    'group commit updates parent states and removes passed topic retry',
    () async {
      const store = VocabularyStore();
      final now = DateTime(2026, 9, 10, 8);
      final parent = await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
        VocabularyTranslation(
          englishText: 'Banana',
          vietnameseText: 'Quả chuối',
        ),
      ], now: now);
      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: 'This is my bag',
        vietnamese: 'Đây là cặp của con',
        collection: VocabularyCollection.review,
        source: VocabularySource.topicCore,
        occurredAt: now.add(const Duration(minutes: 1)),
      );
      final all = await store.read();
      final apple = parent.firstWhere((entry) => entry.word == 'Apple');
      final banana = parent.firstWhere((entry) => entry.word == 'Banana');
      final topic = all.firstWhere((entry) => entry.sourceSentenceId == 'S1');

      await store.commitPracticeResults(
        results: <String, bool>{
          apple.id: true,
          banana.id: false,
          topic.id: true,
        },
        correctAudioPaths: <String, String>{apple.id: '/audio/apple.wav'},
        now: now.add(const Duration(minutes: 2)),
      );

      final committed = await store.read();
      final learned = committed.singleWhere((entry) => entry.id == apple.id);
      final retry = committed.singleWhere((entry) => entry.id == banana.id);
      expect(learned.status, VocabularyLearningStatus.learnedWell);
      expect(learned.correctAudioPath, '/audio/apple.wav');
      expect(retry.status, VocabularyLearningStatus.needsPractice);
      expect(retry.collection, VocabularyCollection.review);
      expect(committed.any((entry) => entry.id == topic.id), isFalse);
    },
  );

  test(
    'stars dedupe by slot while allowing the same target in two slots',
    () async {
      const store = VocabularyStore();
      final first = DateTime(2026, 9, 10, 8);

      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: 'Hello',
        vietnamese: 'Xin chào',
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        starSlotId: 'A035_T01_L01:core:S1',
        correctAudioPath: '/audio/first.wav',
        occurredAt: first,
      );
      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: 'Hello',
        vietnamese: 'Xin chào',
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        starSlotId: 'A035_T01_L01:core:S1',
        correctAudioPath: '/audio/updated.wav',
        occurredAt: first.add(const Duration(minutes: 1)),
      );
      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: 'Hello',
        vietnamese: 'Xin chào',
        collection: VocabularyCollection.star,
        source: VocabularySource.topicChallenge,
        starSlotId: 'A035_T01_L01:challenge:1',
        occurredAt: first.add(const Duration(minutes: 2)),
      );

      final stars = await store.starEntries();
      expect(stars, hasLength(2));
      expect(
        stars
            .singleWhere((entry) => entry.starSlotId == 'A035_T01_L01:core:S1')
            .correctAudioPath,
        '/audio/updated.wav',
      );
    },
  );

  test(
    'review merges duplicate targets and a pass clears every topic retry',
    () async {
      const store = VocabularyStore();
      final now = DateTime(2026, 9, 10, 8);
      for (final lesson in <String>['L01', 'L02']) {
        await store.upsertLessonSentence(
          lessonCode: lesson,
          sentenceId: 'S1',
          english: 'Open your book!',
          vietnamese: 'Mở sách ra',
          collection: VocabularyCollection.review,
          source: VocabularySource.topicCore,
          occurredAt: now,
        );
      }

      final review = await store.reviewEntries();
      expect(review, hasLength(1));

      await store.commitPracticeResults(
        results: <String, bool>{review.single.id: true},
      );

      expect(await store.reviewEntries(), isEmpty);
      expect(await store.read(), isEmpty);
    },
  );

  test(
    'today session takes the five oldest pending entries and resumes',
    () async {
      const store = VocabularyStore();
      const sessions = VocabularySessionStore();
      final base = DateTime(2026, 9, 1);
      await store.write(<VocabularyEntry>[
        for (var index = 5; index >= 0; index--)
          VocabularyEntry(
            id: 'parent-$index',
            word: 'Word $index',
            meaning: 'Nghĩa $index',
            addedAt: base.add(Duration(days: index)),
          ),
      ]);

      final first = await sessions.prepareToday(
        store,
        now: DateTime(2026, 9, 10),
      );
      expect(first?.entryIds, <String>[
        'parent-0',
        'parent-1',
        'parent-2',
        'parent-3',
        'parent-4',
      ]);

      await sessions.saveActive(first!.copyWith(currentIndex: 2));
      final resumed = await sessions.prepareToday(
        store,
        now: DateTime(2026, 9, 10, 15),
      );
      expect(resumed?.id, first.id);
      expect(resumed?.currentIndex, 2);
    },
  );

  test('deleting an unlearned active item backfills today to five', () async {
    const store = VocabularyStore();
    const sessions = VocabularySessionStore();
    final base = DateTime(2026, 9, 1);
    await store.write(<VocabularyEntry>[
      for (var index = 0; index < 6; index++)
        VocabularyEntry(
          id: 'parent-$index',
          word: 'Word $index',
          meaning: 'Nghĩa $index',
          addedAt: base.add(Duration(days: index)),
        ),
    ]);
    final active = await sessions.prepareToday(
      store,
      now: DateTime(2026, 9, 10),
    );
    await sessions.saveActive(active!.copyWith(currentIndex: 2));

    await store.deleteParentEntry('parent-0');
    final reconciled = await sessions.prepareToday(
      store,
      now: DateTime(2026, 9, 10, 12),
    );

    expect(reconciled?.entryIds, <String>[
      'parent-1',
      'parent-2',
      'parent-3',
      'parent-4',
      'parent-5',
    ]);
    expect(reconciled?.entryIds[reconciled.currentIndex], 'parent-2');
  });

  test(
    'invalid and duplicate suggestions are hidden before selection',
    () async {
      const store = VocabularyStore();
      final now = DateTime(2026, 9, 10);
      await store.upsertLessonSentence(
        lessonCode: 'L01',
        sentenceId: 'S1',
        english: 'Apple',
        vietnamese: 'Quả táo',
        collection: VocabularyCollection.review,
        occurredAt: now,
      );
      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Banana',
          vietnameseText: 'Quả chuối',
        ),
      ], now: now);

      final options = await store.filterParentSuggestions(const <
        VocabularyTranslation
      >[
        VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
        VocabularyTranslation(
          englishText: 'Banana',
          vietnameseText: 'Quả chuối',
        ),
        VocabularyTranslation(englishText: 'Orange', vietnameseText: 'Quả cam'),
        VocabularyTranslation(
          englishText: 'Orange!',
          vietnameseText: 'Quả cam',
        ),
        VocabularyTranslation(englishText: 'School', vietnameseText: ''),
      ]);

      expect(options.map((option) => option.englishText), <String>['Orange']);
    },
  );

  test(
    'mastering a topic target removes it from Review without a Star',
    () async {
      const store = VocabularyStore();
      await store.upsertLessonSentence(
        lessonCode: 'L01',
        sentenceId: 'mission:1',
        english: 'Open your book',
        vietnamese: 'Mở sách ra',
        collection: VocabularyCollection.review,
        source: VocabularySource.topicMission,
      );

      await store.clearTopicReviewTarget('Open your book!');

      expect(await store.reviewEntries(), isEmpty);
      expect(await store.starEntries(), isEmpty);
    },
  );

  test(
    'first vocabulary entry is remembered for the whole local day',
    () async {
      const sessions = VocabularySessionStore();

      expect(
        await sessions.markAndCheckFirstEntryToday(DateTime(2026, 9, 10, 8)),
        isTrue,
      );
      expect(
        await sessions.markAndCheckFirstEntryToday(DateTime(2026, 9, 10, 20)),
        isFalse,
      );
      expect(
        await sessions.markAndCheckFirstEntryToday(DateTime(2026, 9, 11, 8)),
        isTrue,
      );
    },
  );
}
