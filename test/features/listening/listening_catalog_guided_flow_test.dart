import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'V4 catalog connects every target to guided practice and authored checks',
    () async {
      final catalog = await AssetListeningContentRepository().load();
      final topics = catalog.groups
          .expand((group) => group.topics)
          .toList(growable: false);
      final lessons = topics
          .expand((topic) => topic.lessons)
          .toList(growable: false);
      final targets = lessons
          .expand((lesson) => lesson.sentences)
          .toList(growable: false);
      final challenges = lessons
          .expand((lesson) => lesson.challengeBank)
          .toList(growable: false);
      final missions = catalog.groups
          .expand((group) => group.levels)
          .expand((level) => level.missionBank)
          .toList(growable: false);

      expect(catalog.groups, hasLength(5));
      expect(topics, hasLength(50));
      expect(lessons, hasLength(109));
      expect(targets, hasLength(601));
      expect(challenges, hasLength(872));
      expect(missions, hasLength(180));
      expect(
        lessons.where((lesson) => !lesson.usesV4Flow),
        isEmpty,
        reason: 'Every released lesson must use the V4 listen-first flow.',
      );
      expect(
        lessons.where((lesson) => !lesson.usesGuidedPractice),
        isEmpty,
        reason:
            'A V4 target must not silently fall back to the legacy manual flow.',
      );
      expect(
        lessons.every((lesson) => lesson.challengeBank.length == 8),
        isTrue,
        reason: 'The authored bank contains eight eligible checks per lesson.',
      );
      expect(
        targets.every(
          (target) =>
              target.id.isNotEmpty &&
              target.english.trim().isNotEmpty &&
              target.vietnamese.trim().isNotEmpty &&
              target.englishAudioId?.isNotEmpty == true &&
              target.vietnameseAudioId?.isNotEmpty == true,
        ),
        isTrue,
        reason:
            'Audio IDs are a content contract; a pending generated clip is not a '
            'reason to drop a target from recognition.',
      );

      for (final lesson in lessons) {
        final targetIds = lesson.sentences.map((target) => target.id).toSet();
        for (final challenge in lesson.challengeBank) {
          expect(challenge.id, isNotEmpty, reason: lesson.id);
          expect(challenge.prompt, isNotEmpty, reason: challenge.id);
          expect(challenge.choices, hasLength(2), reason: challenge.id);
          expect(
            challenge.choices,
            contains(challenge.correctAnswer),
            reason: challenge.id,
          );
          expect(targetIds, contains(challenge.targetId), reason: challenge.id);
        }
      }

      for (final group in catalog.groups) {
        expect(
          group.levels,
          hasLength(3),
          reason: '${group.startAge}-${group.endAge}',
        );
        for (final level in group.levels) {
          expect(level.missionBank, hasLength(12), reason: level.id);
          final coverageTargetIds = group.topics
              .where((topic) => level.topicNumbers.contains(topic.number))
              .expand((topic) => topic.lessons)
              .expand((lesson) => lesson.sentences)
              .map((target) => target.id)
              .toSet();
          for (final mission in level.missionBank) {
            expect(mission.choices, hasLength(2), reason: mission.id);
            expect(mission.choices, contains(mission.correctAnswer));
            expect(
              coverageTargetIds,
              contains(mission.coverageTargetId),
              reason: mission.id,
            );
          }
        }
      }

      final entries = lessons
          .map((lesson) => lesson.entry)
          .whereType<ListeningLessonEntry>()
          .toList(growable: false);
      expect(
        entries
            .where((entry) => entry.kind == ListeningLessonEntryKind.hook)
            .length,
        18,
      );
      expect(
        entries
            .where(
              (entry) => entry.kind == ListeningLessonEntryKind.microObjective,
            )
            .length,
        91,
      );

      final youngLessons = catalog.groups
          .where((group) => group.endAge <= 10)
          .expand((group) => group.topics)
          .expand((topic) => topic.lessons);
      final olderLessons = catalog.groups
          .where((group) => group.startAge >= 11)
          .expand((group) => group.topics)
          .expand((topic) => topic.lessons);
      expect(
        youngLessons.every(
          (lesson) => lesson.overviewMode == ListeningOverviewMode.bilingual,
        ),
        isTrue,
      );
      expect(
        olderLessons.every(
          (lesson) => lesson.overviewMode == ListeningOverviewMode.englishOnly,
        ),
        isTrue,
      );

      final alphabet = lessons.singleWhere(
        (lesson) => lesson.id == 'c35-l1-t01-b01',
      );
      expect(alphabet.titleEn, 'A to I Letters');
      expect(
        alphabet.sentences.every((target) => target.requiresAllExpectedTokens),
        isTrue,
        reason:
            'Alphabet targets must retain the letter-and-word recognition rule.',
      );
    },
  );

  test('V4 keeps songs and role plays as authored lesson metadata', () async {
    final catalog = await AssetListeningContentRepository().load();
    final topics = catalog.groups
        .expand((group) => group.topics)
        .toList(growable: false);
    final lessons = topics
        .expand((topic) => topic.lessons)
        .toList(growable: false);
    final songs = {
      for (final lesson in lessons)
        if (lesson.songTitle != null) lesson.id: lesson.songTitle,
    };
    const expectedSongs = <String, String>{
      'c35-l1-t02-b02': 'Count with Me',
      'c35-l3-t09-b02': 'What Should I Wear?',
      'c35-l3-t10-b02': 'My Happy Day',
      'c67-l3-t08-b01': "Let's Play Together",
      'c810-l1-t01-b02': 'My Busy Day',
    };
    const expectedRolePlayLessons = <String, String>{
      'c810-l1-t02-b02': 'Classroom Talk',
      'c810-l2-t04-b03': 'Ask the Way',
      'c810-l3-t07-b02': 'How Much?',
      'c810-l3-t08-b02': 'Help a Friend',
      'c1112-l3-t07-b02': 'Make a Plan',
      'c1112-l3-t08-b02': 'Ask the Price',
      'c1315-l1-t03-b01': 'My Opinion',
      'c1315-l3-t07-b02': 'Ask for Info',
      'c1315-l3-t08-b02': 'My Order',
      'c1315-l3-t09-b02': 'My Choice',
    };

    expect(songs, expectedSongs);
    expect(
      topics.expand((topic) => topic.songs),
      isEmpty,
      reason:
          'V4 song milestones live on their authored lesson; this test must not '
          'require legacy, bundled song clips while TTS media is pending.',
    );

    final rolePlayLessons = lessons
        .where((lesson) => lesson.rolePlay != null)
        .toList(growable: false);
    expect(rolePlayLessons, hasLength(10));
    expect({
      for (final lesson in rolePlayLessons) lesson.id: lesson.titleEn,
    }, expectedRolePlayLessons);
    for (final lesson in rolePlayLessons) {
      final rolePlay = lesson.rolePlay!;
      expect(rolePlay.scenarioVi, isNotEmpty, reason: lesson.id);
      expect(rolePlay.turns, isNotEmpty, reason: lesson.id);
      expect(
        rolePlay.turns.any(
          (turn) => turn.speaker == ListeningRolePlaySpeaker.child,
        ),
        isTrue,
        reason: lesson.id,
      );
      expect(
        rolePlay.turns.any(
          (turn) => turn.speaker == ListeningRolePlaySpeaker.homi,
        ),
        isTrue,
        reason: lesson.id,
      );
      expect(
        rolePlay.turns.every((turn) => turn.english.trim().isNotEmpty),
        isTrue,
        reason: lesson.id,
      );
    }
  });
}
