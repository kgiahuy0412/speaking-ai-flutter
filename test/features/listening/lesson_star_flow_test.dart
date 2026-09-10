import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_star_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'builds stable slots for core, child role-play, challenge and mission',
    () {
      final ids = LessonStarFlow.expectedStarIds(_lesson, includeMission: true);

      expect(ids, <String>{
        'core:core-1',
        'core:core-2',
        'roleplay:2',
        'roleplay:3',
        'challenge:1',
        'challenge:2',
        'mission:1',
        'mission:2',
        'mission:3',
        'mission:4',
      });
    },
  );

  test('counts only missing stable slots and ignores unrelated earned IDs', () {
    final remaining = LessonStarFlow.remainingStarCount(_lesson, <String>{
      'core:core-1',
      'roleplay:2',
      'challenge:1',
      'mission:1',
      'legacy:unrelated',
    }, includeMission: true);

    expect(remaining, 6);
  });

  test(
    'replays a passed mission only during relearn when a slot is missing',
    () {
      expect(
        LessonStarFlow.shouldReplayPassedMission(
          isRelearn: true,
          hasMissionStarSlots: true,
          earnedStarIds: const <String>{'mission:1', 'mission:2', 'mission:3'},
        ),
        isTrue,
      );
      expect(
        LessonStarFlow.shouldReplayPassedMission(
          isRelearn: true,
          hasMissionStarSlots: true,
          earnedStarIds: const <String>{
            'mission:1',
            'mission:2',
            'mission:3',
            'mission:4',
          },
        ),
        isFalse,
      );
      expect(
        LessonStarFlow.shouldReplayPassedMission(
          isRelearn: false,
          hasMissionStarSlots: true,
          earnedStarIds: const <String>{'mission:1'},
        ),
        isFalse,
      );
    },
  );
}

const _lesson = ListeningLessonContent(
  id: 'lesson-1',
  number: 1,
  titleVi: 'Bài kiểm tra',
  titleEn: 'Test lesson',
  intro: '',
  outro: '',
  estimatedMinutes: 4,
  sentences: <ListeningSentenceContent>[
    ListeningSentenceContent(
      id: 'core-1',
      number: 1,
      english: 'One.',
      vietnamese: 'Một.',
    ),
    ListeningSentenceContent(
      id: 'core-2',
      number: 2,
      english: 'Two.',
      vietnamese: 'Hai.',
    ),
  ],
  rolePlay: ListeningRolePlayContent(
    scenarioVi: 'Kiểm tra',
    turns: <ListeningRolePlayTurn>[
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.homi,
        english: 'Hello.',
        vietnamese: 'Xin chào.',
      ),
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.child,
        english: 'Hi.',
        vietnamese: 'Chào bạn.',
      ),
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.child,
        english: 'Bye.',
        vietnamese: 'Tạm biệt.',
      ),
    ],
  ),
);
