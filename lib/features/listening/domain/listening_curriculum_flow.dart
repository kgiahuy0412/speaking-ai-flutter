import 'listening_content.dart';

enum ListeningTopicLearningState { notStarted, inProgress, completed }

/// Pure curriculum rules shared by the catalog, lesson path, and completion
/// flow. Levels are sequential; topics inside an unlocked level are peers;
/// lessons inside a topic are sequential.
abstract final class ListeningCurriculumFlow {
  static bool lessonCompleted(
    ListeningLessonContent lesson,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    final coreCompleted = (progress[lesson.id] ?? 0) >= lesson.sentences.length;
    return coreCompleted &&
        (!lesson.usesV4Flow || completedV4Activities.contains(lesson.id));
  }

  static ListeningTopicLearningState topicState(
    ListeningTopicContent topic,
    Map<String, int> progress,
    Set<String> completedV4Activities, {
    Set<String> startedLessonIds = const <String>{},
  }) {
    final completed = topic.lessons.every(
      (lesson) => lessonCompleted(lesson, progress, completedV4Activities),
    );
    if (completed) return ListeningTopicLearningState.completed;
    final started = topic.lessons.any(
      (lesson) =>
          (progress[lesson.id] ?? 0) > 0 ||
          startedLessonIds.contains(lesson.id) ||
          completedV4Activities.contains(lesson.id),
    );
    return started
        ? ListeningTopicLearningState.inProgress
        : ListeningTopicLearningState.notStarted;
  }

  static ListeningLessonContent? firstIncompleteLesson(
    ListeningTopicContent topic,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    for (final lesson in topic.lessons) {
      if (!lessonCompleted(lesson, progress, completedV4Activities)) {
        return lesson;
      }
    }
    return null;
  }

  static bool lessonUnlocked(
    ListeningTopicContent topic,
    int lessonIndex,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    if (lessonIndex <= 0) return true;
    return lessonCompleted(
      topic.lessons[lessonIndex - 1],
      progress,
      completedV4Activities,
    );
  }

  static bool allTopicsInLevelCompleted(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) => level.topicNumbers.every((number) {
    final topic = group.topics.where((candidate) => candidate.number == number);
    return topic.isNotEmpty &&
        topicState(topic.first, progress, completedV4Activities) ==
            ListeningTopicLearningState.completed;
  });

  static List<int> incompleteTopicNumbers(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) => level.topicNumbers
      .where((number) {
        final matches = group.topics.where(
          (candidate) => candidate.number == number,
        );
        return matches.isEmpty ||
            topicState(matches.first, progress, completedV4Activities) !=
                ListeningTopicLearningState.completed;
      })
      .toList(growable: false);

  static int currentUnlockedLevelNumber(
    ListeningContentAgeGroup group,
    Set<String> passedLevelIds,
  ) {
    for (final level in group.levels) {
      if (!passedLevelIds.contains(level.id)) return level.number;
    }
    return group.levels.isEmpty ? 1 : group.levels.last.number;
  }

  static bool levelUnlocked(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Set<String> passedLevelIds,
  ) {
    for (final previous in group.levels) {
      if (previous.number >= level.number) break;
      if (!passedLevelIds.contains(previous.id)) return false;
    }
    return true;
  }
}
