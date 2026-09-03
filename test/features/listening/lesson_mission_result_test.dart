import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_mission_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Level Mission passes at three of four resolved prompts', () {
    const result = LessonMissionResult(
      answers: <LessonMissionAnswer>[
        LessonMissionAnswer(
          missionId: 'M01',
          targetId: 'T01',
          correct: true,
          attempts: 1,
          outcome: LessonAttemptOutcome.good,
        ),
        LessonMissionAnswer(
          missionId: 'M02',
          targetId: 'T02',
          correct: true,
          attempts: 1,
          outcome: LessonAttemptOutcome.good,
        ),
        LessonMissionAnswer(
          missionId: 'M03',
          targetId: 'T03',
          correct: true,
          attempts: 2,
          outcome: LessonAttemptOutcome.good,
        ),
        LessonMissionAnswer(
          missionId: 'M04',
          targetId: 'T04',
          correct: false,
          attempts: 2,
          outcome: LessonAttemptOutcome.retry,
        ),
      ],
      score: 3,
      total: 4,
      weakTargetIds: <String>['T04'],
    );

    expect(result.passed, isTrue);
    expect(result.weakTargetIds, <String>['T04']);
  });

  test('Level Mission does not pass with fewer than four prompts', () {
    const result = LessonMissionResult(
      answers: <LessonMissionAnswer>[],
      score: 3,
      total: 3,
      weakTargetIds: <String>[],
    );

    expect(result.passed, isFalse);
  });
}
