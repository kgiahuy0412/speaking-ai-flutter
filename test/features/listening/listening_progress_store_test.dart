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
