import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';

class VocabularyStore {
  const VocabularyStore();

  static const _key = 'innotrik.vocabulary.v1';

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
  }
}
