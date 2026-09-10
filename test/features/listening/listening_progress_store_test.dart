import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resume sentence can move backward without losing completion', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    await fixture.store.saveLesson('lesson-1', 10);
    await fixture.store.saveCurrentSentence('lesson-1', 4);

    expect(await fixture.store.readLesson('lesson-1'), 10);
    expect(await fixture.store.readCurrentSentence('lesson-1'), 4);
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 10});

    await fixture.store.saveCurrentSentence('lesson-1', 0);

    expect(await fixture.store.readCurrentSentence('lesson-1'), 0);
    expect(await fixture.store.readLesson('lesson-1'), 10);
  });

  test('legacy progress remains a valid resume position', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.file.writeAsString(jsonEncode(<String, int>{'legacy': 3}));

    expect(await fixture.store.readCurrentSentence('legacy'), 3);
  });

  test(
    'skipped sentences persist without leaking into lesson totals',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveLesson('lesson-1', 3);
      await fixture.store.saveSkippedSentence('lesson-1', 1);
      await fixture.store.saveSkippedSentence('lesson-1', 4);

      expect(await fixture.store.readSkippedSentences('lesson-1'), <int>{1, 4});
      expect(await fixture.store.readAll(), <String, int>{'lesson-1': 3});

      await fixture.store.clearSkippedSentence('lesson-1', 1);
      expect(await fixture.store.readSkippedSentences('lesson-1'), <int>{4});

      await fixture.store.clearSkippedSentences('lesson-1');
      expect(await fixture.store.readSkippedSentences('lesson-1'), isEmpty);
    },
  );

  test('V2 guide and retry queue metadata do not change totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasOpenedLearningGuide(), isFalse);
    await fixture.store.markLearningGuideOpened();
    await fixture.store.saveNeedsPracticeSentence('lesson-1', 1);
    await fixture.store.saveNeedsPracticeSentence('lesson-1', 4);
    await fixture.store.saveLesson('lesson-1', 2);

    expect(await fixture.store.hasOpenedLearningGuide(), isTrue);
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), <int>{
      1,
      4,
    });
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 2});

    await fixture.store.clearNeedsPracticeSentence('lesson-1', 1);
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), <int>{
      4,
    });
    await fixture.store.clearNeedsPracticeSentences('lesson-1');
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), isEmpty);
  });

  test('V4 level mission completion does not inflate lesson totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasPassedLevelMission('C35-L1'), isFalse);
    await fixture.store.markLevelMissionPassed('C35-L1');
    await fixture.store.saveLesson('lesson-1', 2);

    expect(await fixture.store.hasPassedLevelMission('C35-L1'), isTrue);
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 2});
  });

  test(
    'V4 lesson activity completion stays separate from core progress',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveLesson('v4-lesson', 3);

      expect(
        await fixture.store.hasCompletedV4LessonActivity('v4-lesson'),
        isFalse,
      );
      expect(await fixture.store.readCompletedV4LessonActivities(), isEmpty);

      await fixture.store.markV4LessonActivityCompleted('v4-lesson');

      expect(
        await fixture.store.hasCompletedV4LessonActivity('v4-lesson'),
        isTrue,
      );
      expect(await fixture.store.readCompletedV4LessonActivities(), <String>{
        'v4-lesson',
      });
      expect(await fixture.store.readAll(), <String, int>{'v4-lesson': 3});
    },
  );

  test('V4 resume stage and partial mission answers survive restart', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    await fixture.store.saveResumeStage(
      'lesson-last',
      ListeningResumeStage.mission,
    );
    await fixture.store.saveMissionSelection('level-1', <String>[
      'm1',
      'm2',
      'm3',
      'm4',
    ]);
    await fixture.store.saveMissionAnswer('level-1', 'm1', correct: true);
    await fixture.store.saveMissionAnswer('level-1', 'm2', correct: false);
    await fixture.store.saveMissionWeakTargets('level-1', <String>{'t2'});
    await fixture.store.saveMissionAttempt('level-1', 1);

    expect(
      await fixture.store.readResumeStage('lesson-last'),
      ListeningResumeStage.mission,
    );
    expect(await fixture.store.readMissionSelection('level-1'), <String>[
      'm1',
      'm2',
      'm3',
      'm4',
    ]);
    expect(await fixture.store.readMissionAnswers('level-1'), <String, bool>{
      'm1': true,
      'm2': false,
    });
    expect(await fixture.store.readMissionWeakTargets('level-1'), <String>{
      't2',
    });
    expect(await fixture.store.readMissionAttempt('level-1'), 1);
    expect(await fixture.store.readAll(), isEmpty);

    await fixture.store.clearMissionSession('level-1');
    expect(await fixture.store.readMissionSelection('level-1'), isEmpty);
    expect(await fixture.store.readMissionAnswers('level-1'), isEmpty);
    expect(await fixture.store.readMissionWeakTargets('level-1'), isEmpty);
    expect(await fixture.store.readMissionAttempt('level-1'), 0);
  });

  test('first core sentence start persists without changing totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasStartedLessonCore('lesson-first'), isFalse);
    await fixture.store.markLessonCoreStarted('lesson-first');

    expect(await fixture.store.hasStartedLessonCore('lesson-first'), isTrue);
    expect(await fixture.store.readAll(), isEmpty);
  });

  test(
    'stars are idempotent and course completion event is one-shot',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      expect(await fixture.store.awardStar('lesson-1', 'core:t1'), isTrue);
      expect(await fixture.store.awardStar('lesson-1', 'core:t1'), isFalse);
      expect(await fixture.store.awardStar('lesson-1', 'challenge:q1'), isTrue);
      expect(await fixture.store.readEarnedStars('lesson-1'), <String>{
        'core:t1',
        'challenge:q1',
      });
      expect(await fixture.store.readTotalEarnedStars(), 2);

      expect(await fixture.store.isCourseCompleted('11-12'), isFalse);
      await fixture.store.markCourseCompleted('11-12');
      expect(await fixture.store.isCourseCompleted('11-12'), isTrue);
      expect(
        await fixture.store.markCourseCompletionEventCreated('11-12'),
        isTrue,
      );
      expect(
        await fixture.store.markCourseCompletionEventCreated('11-12'),
        isFalse,
      );
      expect(await fixture.store.readAll(), isEmpty);
    },
  );

  test(
    'topic-selection checkpoint survives interruption but not totals',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveTopicSelectionCheckpoint(
        '3-5',
        levelNumber: 2,
        announceLevel: true,
      );

      final checkpoint = await fixture.store.readTopicSelectionCheckpoint(
        '3-5',
      );
      expect(checkpoint?.levelNumber, 2);
      expect(checkpoint?.announceLevel, isTrue);
      expect(await fixture.store.readAll(), isEmpty);

      await fixture.store.clearTopicSelectionCheckpoint('3-5');
      expect(await fixture.store.readTopicSelectionCheckpoint('3-5'), isNull);
    },
  );

  test('full-topic and full-level relearn preserve earned stars', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    for (final lessonId in <String>['lesson-1', 'lesson-2']) {
      await fixture.store.saveLesson(lessonId, 3);
      await fixture.store.markLessonCoreStarted(lessonId);
      await fixture.store.markV4LessonActivityCompleted(lessonId);
      await fixture.store.saveResumeStage(
        lessonId,
        ListeningResumeStage.completed,
      );
    }
    await fixture.store.awardStar('lesson-1', 'core:t1');
    await fixture.store.markLevelMissionPassed('level-1');
    await fixture.store.saveMissionSelection('level-1', <String>['m1']);

    await fixture.store.resetLevelForRelearn(
      levelId: 'level-1',
      lessonIds: const <String>['lesson-1', 'lesson-2'],
    );

    expect(await fixture.store.readAll(), isEmpty);
    expect(await fixture.store.readStartedLessonCores(), isEmpty);
    expect(await fixture.store.readCompletedV4LessonActivities(), isEmpty);
    expect(await fixture.store.hasPassedLevelMission('level-1'), isFalse);
    expect(await fixture.store.readMissionSelection('level-1'), isEmpty);
    expect(await fixture.store.readEarnedStars('lesson-1'), <String>{
      'core:t1',
    });
  });
}

class _ProgressFixture {
  const _ProgressFixture({
    required this.directory,
    required this.file,
    required this.store,
  });

  final Directory directory;
  final File file;
  final ListeningProgressStore store;

  static Future<_ProgressFixture> create() async {
    final directory = await Directory(
      'build/listening-progress-test-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}progress.json',
    );
    return _ProgressFixture(
      directory: directory,
      file: file,
      store: ListeningProgressStore(progressFilePath: file.path),
    );
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
