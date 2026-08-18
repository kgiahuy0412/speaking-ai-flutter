import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';

class VocabularyStore {
  const VocabularyStore();

  static const _key = 'innotrik.vocabulary.v1';
  static const Set<String> _legacyStarterIds = <String>{
    'family',
    'school',
    'happy',
  };
  static final StreamController<void> _changes =
      StreamController<void>.broadcast(sync: true);

  Stream<void> get changes => _changes.stream;

  Future<List<VocabularyEntry>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null || encoded.isEmpty) {
      return const <VocabularyEntry>[];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) {
        return const <VocabularyEntry>[];
      }
      final entries = decoded
          .whereType<Map<String, Object?>>()
          .map(VocabularyEntry.fromJson)
          .toList(growable: false);
      final migrated = entries
          .where((entry) => !_legacyStarterIds.contains(entry.id))
          .toList(growable: false);
      if (migrated.length != entries.length) {
        await write(migrated);
      }
      return migrated;
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

  /// Marks parent-added words as already introduced by the MAIN assistant.
  /// They remain visible in Family, but are no longer announced as new on the
  /// next vocabulary session.
  Future<void> markIntroduced(Iterable<String> entryIds) async {
    final ids = entryIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final entries = await read();
    final now = DateTime.now();
    var changed = false;
    final updated = entries
        .map((entry) {
          if (!ids.contains(entry.id) || entry.introducedAt != null) {
            return entry;
          }
          changed = true;
          return entry.copyWith(introducedAt: now);
        })
        .toList(growable: false);
    if (changed) {
      await write(updated);
    }
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
