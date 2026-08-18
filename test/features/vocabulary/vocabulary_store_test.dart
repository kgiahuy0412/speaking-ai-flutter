import 'dart:convert';

import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('starts empty so parents provide the Family vocabulary', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final entries = await const VocabularyStore().read();

    expect(entries, isEmpty);
  });

  test(
    'removes the three legacy starter words from existing installs',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[
          for (final item in <(String, String, String)>[
            ('family', 'Family', 'Gia đình'),
            ('school', 'School', 'Trường học'),
            ('happy', 'Happy', 'Vui vẻ'),
            ('parent-word', 'Apple', 'Quả táo'),
          ])
            <String, Object>{
              'id': item.$1,
              'word': item.$2,
              'meaning': item.$3,
              'addedAt': DateTime(2026, 8, 18).toIso8601String(),
              'collection': VocabularyCollection.saved.name,
            },
        ]),
      });

      final store = const VocabularyStore();
      final entries = await store.read();

      expect(entries.map((entry) => entry.id), <String>['parent-word']);
      expect((await store.read()).map((entry) => entry.id), <String>[
        'parent-word',
      ]);
    },
  );

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

  test(
    'marks parent vocabulary as introduced and persists the state',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[
          <String, Object>{
            'id': 'parent-apple',
            'word': 'Apple',
            'meaning': 'Quả táo',
            'addedAt': DateTime(2026, 8, 18).toIso8601String(),
            'collection': VocabularyCollection.saved.name,
          },
        ]),
      });
      const store = VocabularyStore();

      await store.markIntroduced(const <String>['parent-apple']);
      final entry = (await store.read()).single;

      expect(entry.introducedAt, isNotNull);
      expect(entry.word, 'Apple');
      expect(entry.collection, VocabularyCollection.saved);
    },
  );
}
