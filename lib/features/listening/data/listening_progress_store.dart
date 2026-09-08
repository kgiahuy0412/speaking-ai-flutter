import 'dart:convert';

import 'listening_progress_persistence.dart';

enum ListeningResumeStage {
  core,
  challenge,
  song,
  mission,
  reinforcement,
  completed,
  // Appended to preserve the persisted indexes of every existing stage.
  rolePlay,
}

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
  static const String _resumeStageSuffix = '::resume-stage';
  static const String _coreStartedSuffix = '::core-started';
  static const String _missionSelectedMarker = '::mission-selected::';
  static const String _missionAnswerMarker = '::mission-answer::';
  static const String _missionWeakMarker = '::mission-weak::';
  static const String _missionAttemptSuffix = '::mission-attempt';
  static const String _starMarker = '::earned-star::';
  static const String _courseCompletedSuffix = '::course-completed';
  static const String _courseCompletionEventSuffix =
      '::course-completion-event-created';

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
          key.endsWith(_v4LessonActivityPassedMarker) ||
          key.endsWith(_resumeStageSuffix) ||
          key.endsWith(_coreStartedSuffix) ||
          key.contains(_missionSelectedMarker) ||
          key.contains(_missionAnswerMarker) ||
          key.contains(_missionWeakMarker) ||
          key.endsWith(_missionAttemptSuffix) ||
          key.contains(_starMarker) ||
          key.endsWith(_courseCompletedSuffix) ||
          key.endsWith(_courseCompletionEventSuffix),
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

  Future<void> clearV4LessonActivityCompleted(String lessonId) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_v4LessonActivityPassedMarker');
    await _writeRaw(progress);
  }

  Future<ListeningResumeStage> readResumeStage(String lessonId) async {
    final value = (await _readRaw())['$lessonId$_resumeStageSuffix'];
    if (value == null ||
        value < 0 ||
        value >= ListeningResumeStage.values.length) {
      return ListeningResumeStage.core;
    }
    return ListeningResumeStage.values[value];
  }

  Future<void> saveResumeStage(
    String lessonId,
    ListeningResumeStage stage,
  ) async {
    final progress = await _readRaw();
    progress['$lessonId$_resumeStageSuffix'] = stage.index;
    await _writeRaw(progress);
  }

  Future<bool> hasStartedLessonCore(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_coreStartedSuffix'] == 1;
  }

  Future<void> markLessonCoreStarted(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_coreStartedSuffix'] = 1;
    await _writeRaw(progress);
  }

  Future<void> saveMissionSelection(
    String levelId,
    List<String> missionIds,
  ) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionSelectedMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    progress.removeWhere(
      (key, _) => key.startsWith('$levelId$_missionAnswerMarker'),
    );
    for (var index = 0; index < missionIds.length; index += 1) {
      progress['$prefix${missionIds[index]}'] = index + 1;
    }
    await _writeRaw(progress);
  }

  Future<List<String>> readMissionSelection(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionSelectedMarker';
    final selected =
        progress.entries
            .where((entry) => entry.key.startsWith(prefix) && entry.value > 0)
            .toList(growable: false)
          ..sort((left, right) => left.value.compareTo(right.value));
    return selected
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveMissionAnswer(
    String levelId,
    String missionId, {
    required bool correct,
  }) async {
    final progress = await _readRaw();
    progress['$levelId$_missionAnswerMarker$missionId'] = correct ? 1 : -1;
    await _writeRaw(progress);
  }

  Future<Map<String, bool>> readMissionAnswers(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionAnswerMarker';
    return <String, bool>{
      for (final entry in progress.entries)
        if (entry.key.startsWith(prefix) && entry.value != 0)
          entry.key.substring(prefix.length): entry.value == 1,
    };
  }

  Future<void> saveMissionWeakTargets(
    String levelId,
    Iterable<String> targetIds,
  ) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionWeakMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    for (final id in targetIds.where((id) => id.trim().isNotEmpty)) {
      progress['$prefix${id.trim()}'] = 1;
    }
    await _writeRaw(progress);
  }

  Future<Set<String>> readMissionWeakTargets(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionWeakMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<int> readMissionAttempt(String levelId) async {
    return (await _readRaw())['$levelId$_missionAttemptSuffix'] ?? 0;
  }

  Future<void> saveMissionAttempt(String levelId, int attempt) async {
    final progress = await _readRaw();
    progress['$levelId$_missionAttemptSuffix'] = attempt < 0 ? 0 : attempt;
    await _writeRaw(progress);
  }

  Future<void> clearMissionSession(String levelId) async {
    final progress = await _readRaw();
    progress.removeWhere(
      (key, _) =>
          key.startsWith('$levelId$_missionSelectedMarker') ||
          key.startsWith('$levelId$_missionAnswerMarker') ||
          key.startsWith('$levelId$_missionWeakMarker') ||
          key == '$levelId$_missionAttemptSuffix',
    );
    await _writeRaw(progress);
  }

  Future<bool> awardStar(String scopeId, String starId) async {
    final progress = await _readRaw();
    final key = '$scopeId$_starMarker$starId';
    if (progress[key] == 1) return false;
    progress[key] = 1;
    await _writeRaw(progress);
    return true;
  }

  Future<Set<String>> readEarnedStars(String scopeId) async {
    final progress = await _readRaw();
    final prefix = '$scopeId$_starMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<int> readTotalEarnedStars() async {
    final progress = await _readRaw();
    return progress.entries
        .where((entry) => entry.key.contains(_starMarker) && entry.value == 1)
        .length;
  }

  Future<void> markCourseCompleted(String courseId) async {
    final progress = await _readRaw();
    progress['$courseId$_courseCompletedSuffix'] = 1;
    await _writeRaw(progress);
  }

  Future<bool> isCourseCompleted(String courseId) async {
    return (await _readRaw())['$courseId$_courseCompletedSuffix'] == 1;
  }

  /// Returns true exactly once, so the Parent App integration can emit one
  /// completion event without duplicating it after relearn sessions.
  Future<bool> markCourseCompletionEventCreated(String courseId) async {
    final progress = await _readRaw();
    final key = '$courseId$_courseCompletionEventSuffix';
    if (progress[key] == 1) return false;
    progress[key] = 1;
    await _writeRaw(progress);
    return true;
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
