import 'dart:convert';

import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ListeningContentCatalog catalog;
  late List<ListeningContentAgeGroup> groups;
  late List<ListeningLevelContent> levels;
  late List<ListeningTopicContent> topics;
  late List<ListeningLessonContent> lessons;
  late List<ListeningSentenceContent> targets;
  late List<Map<String, Object?>> audioManifestEntries;

  setUpAll(() async {
    catalog = await AssetListeningContentRepository().load();
    groups = catalog.groups;
    levels = groups.expand((group) => group.levels).toList(growable: false);
    topics = groups.expand((group) => group.topics).toList(growable: false);
    lessons = topics.expand((topic) => topic.lessons).toList(growable: false);
    targets = lessons
        .expand((lesson) => lesson.sentences)
        .toList(growable: false);
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/listening_audio_manifest_v4.json',
              ),
            )
            as Map<String, dynamic>;
    audioManifestEntries = (manifest['entries'] as List<dynamic>)
        .map((entry) => Map<String, Object?>.from(entry as Map))
        .toList(growable: false);
  });

  group('V4 listening curriculum', () {
    test(
      'loads the approved V4 curriculum footprint through the app model',
      () {
        expect(groups, hasLength(5));
        expect(levels, hasLength(15));
        expect(topics, hasLength(50));
        expect(lessons, hasLength(109));
        expect(targets, hasLength(601));
        expect(
          lessons.expand((lesson) => lesson.challengeBank),
          hasLength(872),
        );
        expect(levels.expand((level) => level.missionBank), hasLength(180));

        expect(
          groups
              .map((group) => '${group.startAge}-${group.endAge}')
              .toList(growable: false),
          orderedEquals(const <String>['3-5', '6-7', '8-10', '11-12', '13-15']),
        );
        expect(groups.every((group) => group.levels.length == 3), isTrue);
        expect(groups.every((group) => group.topics.length == 10), isTrue);
        expect(
          groups.every(
            (group) =>
                group.levels
                    .map((level) => level.topicNumbers.length)
                    .toList(growable: false)
                    .join(',') ==
                '3,3,4',
          ),
          isTrue,
        );
        expect(levels.every((level) => level.missionBank.length == 12), isTrue);
        expect(lessons.every((lesson) => lesson.entry != null), isTrue);
        expect(lessons.every((lesson) => lesson.usesV4Flow), isTrue);
        expect(
          lessons.every((lesson) => lesson.challengeBank.length == 8),
          isTrue,
        );
      },
    );

    test(
      'keeps every authored challenge and mission tied to a core target',
      () {
        final targetById = <String, ListeningSentenceContent>{
          for (final target in targets) target.id: target,
        };

        expect(targetById, hasLength(601));
        for (final lesson in lessons) {
          for (final challenge in lesson.challengeBank) {
            final target = targetById[challenge.targetId];
            expect(
              target,
              isNotNull,
              reason: 'Unknown target: ${challenge.id}',
            );
            expect(challenge.choices, hasLength(2), reason: challenge.id);
            expect(
              challenge.choices,
              contains(challenge.correctAnswer),
              reason: challenge.id,
            );
            expect(
              target!.english,
              challenge.correctAnswer,
              reason: 'Challenge ${challenge.id} changed its authored target.',
            );
          }
        }

        for (final level in levels) {
          for (final mission in level.missionBank) {
            final target = targetById[mission.coverageTargetId];
            expect(target, isNotNull, reason: 'Unknown target: ${mission.id}');
            expect(mission.choices, hasLength(2), reason: mission.id);
            expect(
              mission.choices,
              contains(mission.correctAnswer),
              reason: mission.id,
            );
            expect(
              target!.english,
              mission.correctAnswer,
              reason: 'Mission ${mission.id} changed its authored target.',
            );
            expect(level.topicNumbers, contains(mission.topicNumber));
          }
        }
      },
    );

    test('uses the V4 age-specific overview rules', () {
      for (final group in groups) {
        final groupLessons = group.topics
            .expand((topic) => topic.lessons)
            .toList(growable: false);
        final expectsBilingualOverview = group.endAge <= 10;

        expect(groupLessons, isNotEmpty);
        expect(
          groupLessons.every(
            (lesson) =>
                lesson.overviewMode ==
                (expectsBilingualOverview
                    ? ListeningOverviewMode.bilingual
                    : ListeningOverviewMode.englishOnly),
          ),
          isTrue,
          reason: '${group.startAge}-${group.endAge}',
        );

        if (expectsBilingualOverview) {
          expect(
            groupLessons.every((lesson) => lesson.overviewAudioId == null),
            isTrue,
          );
        } else {
          expect(
            groupLessons.every(
              (lesson) =>
                  lesson.overviewAudioId != null &&
                  lesson.overviewAudioId!.endsWith('_OVERVIEW_EN'),
            ),
            isTrue,
          );
        }
      }
    });

    test('preserves the V4 role-play and song placements', () {
      final rolePlayLessons = lessons
          .where((lesson) => lesson.rolePlay != null)
          .toList(growable: false);
      final songLessons = lessons
          .where((lesson) => lesson.songTitle != null)
          .toList(growable: false);

      expect(rolePlayLessons, hasLength(10));
      expect(
        rolePlayLessons.map((lesson) => lesson.id).toSet(),
        equals(const <String>{
          'c810-l1-t02-b02',
          'c810-l2-t04-b03',
          'c810-l3-t07-b02',
          'c810-l3-t08-b02',
          'c1112-l3-t07-b02',
          'c1112-l3-t08-b02',
          'c1315-l1-t03-b01',
          'c1315-l3-t07-b02',
          'c1315-l3-t08-b02',
          'c1315-l3-t09-b02',
        }),
      );
      for (final lesson in rolePlayLessons) {
        final coreEnglish = lesson.sentences
            .map((sentence) => sentence.english)
            .toSet();
        final turns = lesson.rolePlay!.turns;
        expect(turns, isNotEmpty, reason: lesson.id);
        expect(
          turns.every((turn) => coreEnglish.contains(turn.english)),
          isTrue,
          reason: 'Role-play ${lesson.id} must use only its lesson targets.',
        );
      }

      expect(songLessons, hasLength(5));
      expect(
        <String, String>{
          for (final lesson in songLessons) lesson.id: lesson.songTitle!,
        },
        equals(const <String, String>{
          'c35-l1-t02-b02': 'Count with Me',
          'c35-l3-t09-b02': 'What Should I Wear?',
          'c35-l3-t10-b02': 'My Happy Day',
          'c67-l3-t08-b01': "Let's Play Together",
          'c810-l1-t01-b02': 'My Busy Day',
        }),
      );
      expect(
        songLessons.every(
          (lesson) =>
              lesson.hasV4SongStage &&
              lesson.songAudioId == '${lesson.code}_SONG' &&
              lesson.songAudioUri == null &&
              lesson.fullAudioUri == null,
        ),
        isTrue,
        reason:
            'V4 songs must retain their separate source-audio handoff and never reuse legacy full audio.',
      );
    });

    test('exports only approved V4 song cues and source-audio handoffs', () {
      Map<String, Object?> entryFor(String audioId) => audioManifestEntries
          .singleWhere((entry) => entry['audioId'] == audioId);

      expect(
        entryFor('SONG_PREALERT')['sourceText'],
        'Tiếp theo là hai câu thử thách. Xong rồi mình nghe bài hát [SONG_TITLE] nhé.',
      );
      expect(
        entryFor('SONG_START_CUE')['sourceText'],
        'Bây giờ cùng nghe [SONG_TITLE] nhé.',
      );

      final songReferences = audioManifestEntries
          .where((entry) => entry['kind'] == 'songReference')
          .toList(growable: false);
      expect(songReferences, hasLength(5));
      expect(
        <String, String>{
          for (final entry in songReferences)
            entry['audioId']! as String: entry['sourceText']! as String,
        },
        equals(const <String, String>{
          'C35-L1-T02-B02_SONG': 'Count with Me',
          'C35-L3-T09-B02_SONG': 'What Should I Wear?',
          'C35-L3-T10-B02_SONG': 'My Happy Day',
          'C67-L3-T08-B01_SONG': "Let's Play Together",
          'C810-L1-T01-B02_SONG': 'My Busy Day',
        }),
      );
      expect(
        songReferences.every(
          (entry) => entry['qaStatus'] == 'PENDING_SOURCE_AUDIO',
        ),
        isTrue,
        reason:
            'The V4 source names placements but provides no song lyrics/recording to synthesize.',
      );
    });
  });
}
