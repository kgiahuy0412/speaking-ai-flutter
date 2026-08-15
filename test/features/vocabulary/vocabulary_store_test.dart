import 'dart:convert';

import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'moves one lesson sentence from Review to Stars without duplication',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[]),
      });
      const store = VocabularyStore();

      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: "I'm An",
        vietnamese: 'Con là An',
        collection: VocabularyCollection.review,
      );
      var entries = await store.read();
      expect(entries, hasLength(1));
      expect(entries.single.collection, VocabularyCollection.review);

      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: "I'm An",
        vietnamese: 'Con là An',
        collection: VocabularyCollection.star,
      );
      entries = await store.read();

      expect(entries, hasLength(1));
      expect(entries.single.collection, VocabularyCollection.star);
      expect(entries.single.word, "I'm An");
      expect(entries.single.meaning, 'Con là An');
    },
  );

  test('loads legacy vocabulary entries into the Saved collection', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[
        <String, Object>{
          'id': 'legacy',
          'word': 'Family',
          'meaning': 'Gia đình',
          'addedAt': DateTime(2026, 8, 14).toIso8601String(),
        },
      ]),
    });

    final entries = await const VocabularyStore().read();

    expect(entries.single.collection, VocabularyCollection.saved);
  });
}
