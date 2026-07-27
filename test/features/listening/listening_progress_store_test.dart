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
