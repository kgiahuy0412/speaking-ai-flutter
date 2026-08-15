import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';

class VocabularyStore {
  const VocabularyStore();

  static const _key = 'innotrik.vocabulary.v1';
  static final StreamController<void> _changes =
      StreamController<void>.broadcast(sync: true);

  Stream<void> get changes => _changes.stream;

  Future<List<VocabularyEntry>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null || encoded.isEmpty) {
      final now = DateTime.now();
      final starters = <VocabularyEntry>[
        VocabularyEntry(
          id: 'family',
          word: 'Family',
          meaning: 'Gia đình',
          addedAt: now,
        ),
        VocabularyEntry(
          id: 'school',
          word: 'School',
          meaning: 'Trường học',
          addedAt: now.subtract(const Duration(days: 1)),
        ),
        VocabularyEntry(
          id: 'happy',
          word: 'Happy',
          meaning: 'Vui vẻ',
          addedAt: now.subtract(const Duration(days: 2)),
        ),
      ];
      await write(starters);
      return starters;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) {
        return const <VocabularyEntry>[];
      }
      return decoded
          .whereType<Map<String, Object?>>()
          .map(VocabularyEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <VocabularyEntry>[];
    }
  }

  Future<void> write(List<VocabularyEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    _changes.add(null);
  }

  /// Adds a lesson sentence to a learning collection, or moves the existing
  /// sentence between Review and Stars without creating a duplicate.
  Future<void> upsertLessonSentence({
    required String lessonCode,
    required String sentenceId,
    required String english,
    required String vietnamese,
    required VocabularyCollection collection,
  }) async {
    final entries = await read();
    final normalizedEnglish = english.trim().toLowerCase();
    final stableId = 'lesson:$lessonCode:$sentenceId';
    final updated = entries.where((entry) {
      if (entry.id == stableId) {
        return false;
      }
      final isLessonSentence = entry.sourceSentenceId != null;
      return !isLessonSentence ||
          entry.word.trim().toLowerCase() != normalizedEnglish;
    }).toList();
    updated.insert(
      0,
      VocabularyEntry(
        id: stableId,
        word: english.trim(),
        meaning: vietnamese.trim(),
        addedAt: DateTime.now(),
        collection: collection,
        sourceLessonCode: lessonCode,
        sourceSentenceId: sentenceId,
      ),
    );
    await write(updated);
  }
}
