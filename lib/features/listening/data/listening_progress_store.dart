import 'dart:convert';

import 'listening_progress_persistence.dart';

class ListeningProgressStore {
  const ListeningProgressStore({this.progressFilePath});

  static const String _resumeSuffix = '::current-sentence';
  static const String _skippedMarker = '::skipped-sentence::';
  static const String _learningGuideOpenedKey =
      '__listening-learning-guide-opened-v2';
  static const String _needsPracticeMarker = '::needs-practice::';

  final String? progressFilePath;
  ListeningProgressPersistence get _persistence =>
      ListeningProgressPersistence(customPath: progressFilePath);

  Future<Map<String, int>> readAll() async {
    final progress = await _readRaw();
    progress.removeWhere(
      (key, _) =>
          key.endsWith(_resumeSuffix) ||
          key == _learningGuideOpenedKey ||
          key.contains(_skippedMarker) ||
          key.contains(_needsPracticeMarker),
    );
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

  Future<bool> hasOpenedLearningGuide() async {
    final progress = await _readRaw();
    return progress[_learningGuideOpenedKey] == 1;
  }

  Future<void> markLearningGuideOpened() async {
    final progress = await _readRaw();
    progress[_learningGuideOpenedKey] = 1;
    await _writeRaw(progress);
  }

  Future<Set<int>> readSkippedSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_skippedMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => int.tryParse(entry.key.substring(prefix.length)))
        .whereType<int>()
        .where((index) => index >= 0)
        .toSet();
  }

  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress['$lessonId$_skippedMarker$sentenceIndex'] = 1;
    await _writeRaw(progress);
  }

  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_skippedMarker$sentenceIndex');
    await _writeRaw(progress);
  }

  Future<void> clearSkippedSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_skippedMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    await _writeRaw(progress);
  }

  Future<Set<int>> readNeedsPracticeSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_needsPracticeMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => int.tryParse(entry.key.substring(prefix.length)))
        .whereType<int>()
        .where((index) => index >= 0)
        .toSet();
  }

  Future<void> saveNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    final progress = await _readRaw();
    progress['$lessonId$_needsPracticeMarker$sentenceIndex'] = 1;
    await _writeRaw(progress);
  }

  Future<void> clearNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_needsPracticeMarker$sentenceIndex');
    await _writeRaw(progress);
  }

  Future<void> clearNeedsPracticeSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_needsPracticeMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
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
