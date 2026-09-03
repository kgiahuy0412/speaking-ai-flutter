import 'dart:convert';

import 'listening_progress_persistence.dart';

class ListeningProgressStore {
  const ListeningProgressStore({this.progressFilePath});

  static const String _resumeSuffix = '::current-sentence';
  static const String _skippedMarker = '::skipped-sentence::';
  static const String _learningGuideOpenedKey =
      '__listening-learning-guide-opened-v2';
  static const String _needsPracticeMarker = '::needs-practice::';
  static const String _levelMissionPassedMarker = '::level-mission-passed';
  static const String _v4LessonActivityPassedMarker =
      '::v4-lesson-activity-passed';

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
          key.contains(_needsPracticeMarker) ||
          key.endsWith(_levelMissionPassedMarker) ||
          key.endsWith(_v4LessonActivityPassedMarker),
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

  /// A level becomes complete only after its authored four-question mission
  /// reaches the V4 pass threshold. This marker is intentionally separate
  /// from per-lesson sentence progress so topic totals remain accurate.
  Future<bool> hasPassedLevelMission(String levelId) async {
    final progress = await _readRaw();
    return progress['$levelId$_levelMissionPassedMarker'] == 1;
  }

  Future<void> markLevelMissionPassed(String levelId) async {
    final progress = await _readRaw();
    progress['$levelId$_levelMissionPassedMarker'] = 1;
    await _writeRaw(progress);
  }

  /// V4 lessons are complete only after the learner finishes both authored
  /// end-of-lesson challenges. Core sentence progress remains separate so a
  /// learner who leaves during the challenge resumes at the final sentence
  /// instead of being shown as having completed the lesson or topic.
  Future<Set<String>> readCompletedV4LessonActivities() async {
    final progress = await _readRaw();
    return progress.entries
        .where(
          (entry) =>
              entry.value == 1 &&
              entry.key.endsWith(_v4LessonActivityPassedMarker),
        )
        .map(
          (entry) => entry.key.substring(
            0,
            entry.key.length - _v4LessonActivityPassedMarker.length,
          ),
        )
        .where((lessonId) => lessonId.isNotEmpty)
        .toSet();
  }

  Future<bool> hasCompletedV4LessonActivity(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_v4LessonActivityPassedMarker'] == 1;
  }

  Future<void> markV4LessonActivityCompleted(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_v4LessonActivityPassedMarker'] = 1;
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
