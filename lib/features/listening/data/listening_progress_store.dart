import 'dart:convert';

import 'listening_progress_persistence.dart';

class ListeningProgressStore {
  const ListeningProgressStore({this.progressFilePath});

  static const String _resumeSuffix = '::current-sentence';

  final String? progressFilePath;
  ListeningProgressPersistence get _persistence =>
      ListeningProgressPersistence(customPath: progressFilePath);

  Future<Map<String, int>> readAll() async {
    final progress = await _readRaw();
    progress.removeWhere((key, _) => key.endsWith(_resumeSuffix));
    return progress;
  }

  Future<Map<String, int>> _readRaw() async {
    try {
      final raw = await _persistence.read();
      if (raw == null || raw.trim().isEmpty) {
        return <String, int>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return <String, int>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key, value is int ? value : 0),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<int> readLesson(String lessonId) async {
    return (await readAll())[lessonId] ?? 0;
  }

  Future<int> readCurrentSentence(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_resumeSuffix'] ?? progress[lessonId] ?? 0;
  }

  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress['$lessonId$_resumeSuffix'] = sentenceIndex < 0 ? 0 : sentenceIndex;
    await _writeRaw(progress);
  }

  Future<void> saveLesson(String lessonId, int completedSentences) async {
    final progress = await _readRaw();
    final previous = progress[lessonId] ?? 0;
    if (completedSentences <= previous) {
      return;
    }
    progress[lessonId] = completedSentences;
    await _writeRaw(progress);
  }

  Future<void> _writeRaw(Map<String, int> progress) async {
    await _persistence.write(jsonEncode(progress));
  }
}
