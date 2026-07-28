import 'dart:math';

import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps every guide cue to its matching asset directory', () async {
    final library = LessonGuideAudioLibrary(
      random: _LastItemRandom(),
      assetPaths: const <String>[
        'assets/audio/A-3-5/GUIDE_RECORD/record.mp3',
        'assets/audio/A-3-5/GUIDE_PRAISE/praise.wav',
        'assets/audio/A-3-5/GUIDE_NEXT/next.m4a',
        'assets/audio/A-3-5/GUIDE_IDLE1/idle-first.aac',
        'assets/audio/A-3-5/GUIDE_IDLE2/idle-second.ogg',
        'assets/audio/A-3-5/GUIDE_SKIP/skip.mp3',
        'assets/audio/A-3-5/GUIDE_ENDING/ending.mp3',
        'assets/audio/A-3-5/GUIDE_RECORD/notes.txt',
      ],
    );

    final expectedPaths = <LessonGuideCue, String>{
      LessonGuideCue.record: '/assets/audio/A-3-5/GUIDE_RECORD/record.mp3',
      LessonGuideCue.praise: '/assets/audio/A-3-5/GUIDE_PRAISE/praise.wav',
      LessonGuideCue.next: '/assets/audio/A-3-5/GUIDE_NEXT/next.m4a',
      LessonGuideCue.idleFirst:
          '/assets/audio/A-3-5/GUIDE_IDLE1/idle-first.aac',
      LessonGuideCue.idleSecond:
          '/assets/audio/A-3-5/GUIDE_IDLE2/idle-second.ogg',
      LessonGuideCue.skip: '/assets/audio/A-3-5/GUIDE_SKIP/skip.mp3',
      LessonGuideCue.ending: '/assets/audio/A-3-5/GUIDE_ENDING/ending.mp3',
    };

    for (final entry in expectedPaths.entries) {
      final uri = await library.randomUri(entry.key, startAge: 3, endAge: 5);
      expect(uri?.scheme, 'asset');
      expect(uri?.path, entry.value);
    }
  });

  test('selects a random supported file and ignores other folders', () async {
    final library = LessonGuideAudioLibrary(
      random: _LastItemRandom(),
      assetPaths: const <String>[
        'assets/audio/A-3-5/GUIDE_NEXT/01.mp3',
        'assets/audio/A-3-5/GUIDE_NEXT/02.mp3',
        'assets/audio/A-3-5/GUIDE_NEXT/readme.txt',
        'assets/audio/A-3-5/GUIDE_NEXT_EXTRA/03.mp3',
        'assets/audio/A-6-7/GUIDE_NEXT/wrong-age.mp3',
      ],
    );

    final uri = await library.randomUri(
      LessonGuideCue.next,
      startAge: 3,
      endAge: 5,
    );

    expect(uri?.path, '/assets/audio/A-3-5/GUIDE_NEXT/02.mp3');
  });

  test('returns null when a guide directory has no audio', () async {
    final library = LessonGuideAudioLibrary(assetPaths: const <String>[]);

    expect(
      await library.randomUri(LessonGuideCue.record, startAge: 13, endAge: 15),
      isNull,
    );
  });

  test('bundles guide audio for every supported age and cue', () async {
    final library = LessonGuideAudioLibrary();
    const ageGroups = <(int, int)>[(3, 5), (6, 7), (8, 10), (11, 12), (13, 15)];

    for (final (startAge, endAge) in ageGroups) {
      for (final cue in LessonGuideCue.values) {
        expect(
          await library.randomUri(cue, startAge: startAge, endAge: endAge),
          isNotNull,
          reason: 'Missing $cue audio for ages $startAge-$endAge',
        );
      }
    }
  });
}

class _LastItemRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.99;

  @override
  int nextInt(int max) => max - 1;
}
