import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_curriculum_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final topics = <ListeningTopicContent>[
    _topic(1),
    _topic(2),
    _topic(3),
    _topic(4, levelNumber: 2),
  ];
  final levels = <ListeningLevelContent>[
    const ListeningLevelContent(
      id: 'level-1',
      number: 1,
      titleVi: 'Level 1',
      topicNumbers: <int>[1, 2, 3],
    ),
    const ListeningLevelContent(
      id: 'level-2',
      number: 2,
      titleVi: 'Level 2',
      topicNumbers: <int>[4],
    ),
  ];
  final group = ListeningContentAgeGroup(
    startAge: 3,
    endAge: 5,
    topics: topics,
    levels: levels,
  );

  test('topics are peers while lessons remain sequential', () {
    final progress = <String, int>{};
    const activities = <String>{};

    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        0,
        progress,
        activities,
      ),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        1,
        progress,
        activities,
      ),
      isFalse,
    );

    progress['topic-1-lesson-1'] = 1;
    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        1,
        progress,
        activities,
      ),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.topicState(topics[1], progress, activities),
      ListeningTopicLearningState.notStarted,
    );
  });

  test('mission eligibility depends on every topic, not numeric order', () {
    final progress = <String, int>{
      for (final number in <int>[1, 2])
        for (final lesson in topics[number - 1].lessons) lesson.id: 1,
    };

    expect(
      ListeningCurriculumFlow.allTopicsInLevelCompleted(
        group,
        levels.first,
        progress,
        const <String>{},
      ),
      isFalse,
    );

    for (final lesson in topics[2].lessons) {
      progress[lesson.id] = 1;
    }
    expect(
      ListeningCurriculumFlow.allTopicsInLevelCompleted(
        group,
        levels.first,
        progress,
        const <String>{},
      ),
      isTrue,
    );
  });

  test('the next Level unlocks only after the previous mission passes', () {
    expect(
      ListeningCurriculumFlow.levelUnlocked(group, levels[1], const <String>{}),
      isFalse,
    );
    expect(
      ListeningCurriculumFlow.levelUnlocked(group, levels[1], const <String>{
        'level-1',
      }),
      isTrue,
    );
  });
}

ListeningTopicContent _topic(int number, {int levelNumber = 1}) {
  return ListeningTopicContent(
    id: 'topic-$number',
    number: number,
    titleVi: 'Chủ đề $number',
    titleEn: 'Topic $number',
    levelNumber: levelNumber,
    lessons: <ListeningLessonContent>[
      _lesson('topic-$number-lesson-1', 1),
      _lesson('topic-$number-lesson-2', 2),
    ],
  );
}

ListeningLessonContent _lesson(String id, int number) {
  return ListeningLessonContent(
    id: id,
    number: number,
    titleVi: 'Bài $number',
    titleEn: 'Lesson $number',
    intro: '',
    outro: '',
    estimatedMinutes: 1,
    sentences: const <ListeningSentenceContent>[
      ListeningSentenceContent(
        number: 1,
        english: 'Hello.',
        vietnamese: 'Xin chào.',
      ),
    ],
  );
}
