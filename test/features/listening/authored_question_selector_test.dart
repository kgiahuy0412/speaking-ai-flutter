import 'package:ai_speaking_flutter_app/features/listening/domain/authored_question_selector.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const selector = AuthoredQuestionSelector();

  group('AuthoredQuestionSelector lesson challenges', () {
    final challengeBank = <ListeningChallengeContent>[
      _challenge('Q01', targetId: 'T01', format: 'VI_TO_EN'),
      _challenge('Q02', targetId: 'T02', format: 'CONTROLLED_COMPLETE'),
      _challenge('Q03', targetId: 'T03', format: 'VI_TO_EN'),
      _challenge('Q04', targetId: 'T04', format: 'CONTROLLED_COMPLETE'),
      _challenge('Q05', targetId: 'T05', format: 'VI_TO_EN'),
      _challenge('Q06', targetId: 'T06', format: 'CONTROLLED_COMPLETE'),
      _challenge('Q07', targetId: 'T07', format: 'VI_TO_EN'),
      _challenge('Q08', targetId: 'T08', format: 'CONTROLLED_COMPLETE'),
    ];

    test('selects two authored challenges with varied target and format', () {
      final selected = selector.selectLessonChallenges(
        challengeBank,
        seed: 3,
        counter: 2,
      );

      expect(selected, hasLength(2));
      expect(
        selected.map((question) => question.targetId).toSet(),
        hasLength(2),
      );
      expect(selected.map((question) => question.format).toSet(), hasLength(2));
    });

    test('is deterministic and does not immediately repeat an exact pair', () {
      final first = selector.selectLessonChallenges(
        challengeBank,
        seed: 4,
        counter: 1,
      );
      final repeated = selector.selectLessonChallenges(
        challengeBank,
        seed: 4,
        counter: 1,
      );
      final next = selector.selectLessonChallenges(
        challengeBank,
        seed: 4,
        counter: 1,
        previousChallengeIds: first.map((question) => question.id),
      );

      expect(
        repeated.map((question) => question.id),
        first.map((question) => question.id),
      );
      expect(
        next.map((question) => question.id).toSet(),
        isNot(first.map((question) => question.id).toSet()),
      );
    });

    test('prefers weak targets and honors retest exclusions', () {
      final weakFirst = selector.selectLessonChallenges(
        challengeBank,
        weakTargetIds: const <String>['T07'],
      );
      final excluded = selector.selectLessonChallenges(
        challengeBank,
        excludedQuestionIds: const <String>['Q07'],
        weakTargetIds: const <String>['T07'],
      );

      expect(weakFirst.map((question) => question.targetId), contains('T07'));
      expect(excluded.map((question) => question.id), isNot(contains('Q07')));
    });
  });

  group('AuthoredQuestionSelector missions', () {
    test('uses the Level 1/2 authored 2 + 1 + 1 topic distribution', () {
      final selected = selector.selectMissions(
        levelNumber: 1,
        topicNumbers: const <int>[1, 2, 3],
        missionBank: <ListeningMissionContent>[
          _mission('L1-T1-A', topic: 1, targetId: 'T1-A'),
          _mission('L1-T1-B', topic: 1, targetId: 'T1-B'),
          _mission('L1-T1-C', topic: 1, targetId: 'T1-C'),
          _mission('L1-T2-A', topic: 2, targetId: 'T2-A'),
          _mission('L1-T2-B', topic: 2, targetId: 'T2-B'),
          _mission('L1-T2-C', topic: 2, targetId: 'T2-C'),
          _mission('L1-T3-A', topic: 3, targetId: 'T3-A'),
          _mission('L1-T3-B', topic: 3, targetId: 'T3-B'),
          _mission('L1-T3-C', topic: 3, targetId: 'T3-C'),
        ],
        weakTargetIds: const <String>['T2-B'],
        seed: 2,
      );
      final byTopic = <int, List<ListeningMissionContent>>{};
      for (final mission in selected) {
        byTopic
            .putIfAbsent(mission.topicNumber, () => <ListeningMissionContent>[])
            .add(mission);
      }
      final doubleTopic = byTopic.entries.singleWhere(
        (entry) => entry.value.length == 2,
      );

      expect(selected, hasLength(4));
      expect(byTopic.keys, containsAll(<int>[1, 2, 3]));
      final topicDistribution =
          byTopic.values.map((missions) => missions.length).toList()..sort();
      expect(topicDistribution, <int>[1, 1, 2]);
      expect(
        doubleTopic.value.map((mission) => mission.coverageTargetId).toSet(),
        hasLength(2),
      );
      expect(
        selected.map((mission) => mission.coverageTargetId),
        contains('T2-B'),
      );
    });

    test('uses one authored mission for each of the four Level 3 topics', () {
      final level = ListeningLevelContent(
        id: 'level-3',
        number: 3,
        titleVi: 'Level 3',
        topicNumbers: const <int>[7, 8, 9, 10],
        missionBank: <ListeningMissionContent>[
          _mission('L3-T7-A', topic: 7, targetId: 'T7-A'),
          _mission('L3-T7-B', topic: 7, targetId: 'T7-B'),
          _mission('L3-T8-A', topic: 8, targetId: 'T8-A'),
          _mission('L3-T8-B', topic: 8, targetId: 'T8-B'),
          _mission('L3-T9-A', topic: 9, targetId: 'T9-A'),
          _mission('L3-T9-B', topic: 9, targetId: 'T9-B'),
          _mission('L3-T10-A', topic: 10, targetId: 'T10-A'),
          _mission('L3-T10-B', topic: 10, targetId: 'T10-B'),
        ],
      );

      final selected = selector.selectMissionsForLevel(
        level,
        weakTargetIds: const <String>['T9-B'],
        excludedQuestionIds: const <String>['L3-T7-B'],
        seed: 9,
        counter: 1,
      );

      expect(selected, hasLength(4));
      expect(selected.map((mission) => mission.topicNumber).toSet(), <int>{
        7,
        8,
        9,
        10,
      });
      expect(selected.map((mission) => mission.id), isNot(contains('L3-T7-B')));
      expect(
        selected.map((mission) => mission.coverageTargetId),
        contains('T9-B'),
      );
    });
  });
}

ListeningChallengeContent _challenge(
  String id, {
  required String targetId,
  required String format,
}) {
  return ListeningChallengeContent(
    id: id,
    format: format,
    prompt: id,
    choices: const <String>['A', 'B'],
    correctAnswer: 'A',
    correctVietnamese: id,
    targetId: targetId,
  );
}

ListeningMissionContent _mission(
  String id, {
  required int topic,
  required String targetId,
}) {
  return ListeningMissionContent(
    id: id,
    topicNumber: topic,
    format: 'VI_TO_EN',
    prompt: id,
    choices: const <String>['A', 'B'],
    correctAnswer: 'A',
    coverageTargetId: targetId,
  );
}
