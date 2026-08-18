import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/lesson_recording_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps only the three newest successful recordings per sentence',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lesson-recording-history-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LessonRecordingHistoryStore(
        customPath: '${directory.path}${Platform.pathSeparator}history.json',
      );
      final baseTime = DateTime.utc(2026, 7, 27, 8);

      expect(await store.addSuccessful(_entry(1, baseTime)), isEmpty);
      expect(
        await store.addSuccessful(
          _entry(2, baseTime.add(const Duration(seconds: 1))),
        ),
        isEmpty,
      );
      expect(
        await store.addSuccessful(
          _entry(3, baseTime.add(const Duration(seconds: 2))),
        ),
        isEmpty,
      );
      final evicted = await store.addSuccessful(
        _entry(4, baseTime.add(const Duration(seconds: 3))),
      );

      expect(evicted, <String>['recording-1.m4a']);
      final latest = await store.readForSentence('lesson-1', 'sentence-1');
      expect(latest.map((entry) => entry.id), <String>[
        'recording-4',
        'recording-3',
        'recording-2',
      ]);
      expect(latest, hasLength(3));
    },
  );

  test('recordings from another sentence are not evicted', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lesson-recording-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LessonRecordingHistoryStore(
      customPath: '${directory.path}${Platform.pathSeparator}history.json',
    );
    final time = DateTime.utc(2026, 7, 27, 8);

    await store.addSuccessful(_entry(1, time));
    await store.addSuccessful(
      _entry(2, time.add(const Duration(seconds: 1)), sentenceId: 'sentence-2'),
    );

    expect(await store.readForSentence('lesson-1', 'sentence-1'), hasLength(1));
    expect(await store.readForSentence('lesson-1', 'sentence-2'), hasLength(1));
  });

  test('removes every recording for one lesson and preserves others', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lesson-recording-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LessonRecordingHistoryStore(
      customPath: '${directory.path}${Platform.pathSeparator}history.json',
    );
    final time = DateTime.utc(2026, 8, 18, 8);

    await store.addSuccessful(_entry(1, time));
    await store.addSuccessful(
      _entry(2, time.add(const Duration(seconds: 1)), sentenceId: 'sentence-2'),
    );
    await store.addSuccessful(
      LessonRecordingHistoryEntry(
        id: 'other-recording',
        lessonId: 'lesson-2',
        lessonTitle: 'Bài khác',
        sentenceId: 'other-sentence',
        sentenceNumber: 1,
        english: 'Goodbye!',
        vietnamese: 'Tạm biệt!',
        filePath: 'other-recording.m4a',
        duration: const Duration(seconds: 2),
        createdAt: time.add(const Duration(seconds: 2)),
      ),
    );

    final removed = await store.removeLesson('lesson-1');

    expect(
      removed,
      containsAll(<String>['recording-1.m4a', 'recording-2.m4a']),
    );
    expect(await store.readForSentence('lesson-1', 'sentence-1'), isEmpty);
    expect(await store.readForSentence('lesson-1', 'sentence-2'), isEmpty);
    expect((await store.readAll()).map((entry) => entry.id), <String>[
      'other-recording',
    ]);
  });
}

LessonRecordingHistoryEntry _entry(
  int index,
  DateTime createdAt, {
  String sentenceId = 'sentence-1',
}) {
  return LessonRecordingHistoryEntry(
    id: 'recording-$index',
    lessonId: 'lesson-1',
    lessonTitle: 'Bài học',
    sentenceId: sentenceId,
    sentenceNumber: sentenceId == 'sentence-1' ? 1 : 2,
    english: 'Hello!',
    vietnamese: 'Xin chào!',
    filePath: 'recording-$index.m4a',
    duration: const Duration(seconds: 2),
    createdAt: createdAt,
  );
}
