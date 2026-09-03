import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every catalog practice lesson uses the guided evaluation flow',
    () async {
      final catalog = await AssetListeningContentRepository().load();
      final practiceLessons = catalog.groups
          .expand((group) => group.topics)
          .expand((topic) => topic.lessons)
          .toList(growable: false);

      expect(practiceLessons, hasLength(101));
      expect(
        practiceLessons.where((lesson) => !lesson.usesGuidedPractice),
        isEmpty,
        reason:
            'A practice lesson must not silently fall back to the legacy manual '
            'recording flow because of its code or topic number.',
      );
      expect(
        practiceLessons
            .expand((lesson) => lesson.sentences)
            .every(
              (sentence) =>
                  sentence.id.isNotEmpty && sentence.english.trim().isNotEmpty,
            ),
        isTrue,
        reason: 'Every guided attempt needs a stable sentence and ASR target.',
      );
    },
  );

  test('songs stay outside the sentence evaluation state machine', () async {
    final catalog = await AssetListeningContentRepository().load();
    final songs = catalog.groups
        .expand((group) => group.topics)
        .expand((topic) => topic.songs)
        .toList(growable: false);

    expect(songs, isNotEmpty);
    expect(songs.where((song) => song.usesGuidedPractice), isEmpty);
  });
}
