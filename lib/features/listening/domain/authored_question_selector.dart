import 'listening_content.dart';

/// Selects authored V4 questions without synthesising or mutating content.
///
/// The selector is deliberately stateless. Persist the [seed] and increment a
/// caller-owned [counter] to make successive attempts reproducible while still
/// rotating through equally suitable authored questions.
class AuthoredQuestionSelector {
  const AuthoredQuestionSelector();

  /// Returns up to two lesson challenges from an authored challenge bank.
  ///
  /// A pair with different targets and different formats wins over a less
  /// varied pair. Within equally varied pairs, targets listed in
  /// [weakTargetIds] are preferred. [previousChallengeIds] is treated as the
  /// immediately preceding pair; the same pair is skipped whenever another
  /// pair is available. [excludedQuestionIds] are never selected.
  List<ListeningChallengeContent> selectLessonChallenges(
    Iterable<ListeningChallengeContent> challengeBank, {
    int seed = 0,
    int counter = 0,
    Iterable<String> excludedQuestionIds = const <String>[],
    Iterable<String> weakTargetIds = const <String>[],
    Iterable<String> previousChallengeIds = const <String>[],
  }) {
    final excludedIds = _normalizedIds(excludedQuestionIds);
    final weakIds = _normalizedIds(weakTargetIds);
    final candidates = _availableChallenges(challengeBank, excludedIds);

    if (candidates.length < 2) {
      return candidates;
    }

    final pairs = <_ChallengePair>[];
    for (var firstIndex = 0; firstIndex < candidates.length - 1; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < candidates.length;
        secondIndex++
      ) {
        pairs.add(
          _ChallengePair(
            candidates[firstIndex],
            candidates[secondIndex],
            weakTargetIds: weakIds,
          ),
        );
      }
    }

    final previousPair = _normalizedIds(previousChallengeIds);
    final alternatives = previousPair.length == 2
        ? pairs
              .where((pair) => !pair.hasExactlyIds(previousPair))
              .toList(growable: false)
        : pairs;
    final eligiblePairs = alternatives.isNotEmpty ? alternatives : pairs;

    final bestPairs = _bestBy(
      eligiblePairs,
      (left, right) => left.comparePriorityTo(right),
    );
    final selected = _rotatePick(
      bestPairs,
      seed: seed,
      counter: counter,
      keyOf: (pair) => pair.key,
    );
    return selected.questions;
  }

  /// Convenience entry point for selecting the challenges authored for a
  /// lesson.
  List<ListeningChallengeContent> selectChallengesForLesson(
    ListeningLessonContent lesson, {
    int seed = 0,
    int counter = 0,
    Iterable<String> excludedQuestionIds = const <String>[],
    Iterable<String> weakTargetIds = const <String>[],
    Iterable<String> previousChallengeIds = const <String>[],
  }) {
    return selectLessonChallenges(
      lesson.challengeBank,
      seed: seed,
      counter: counter,
      excludedQuestionIds: excludedQuestionIds,
      weakTargetIds: weakTargetIds,
      previousChallengeIds: previousChallengeIds,
    );
  }

  /// Returns an authored four-question mission set for a V4 level.
  ///
  /// Levels 1 and 2 use a 2 + 1 + 1 topic distribution: two questions from
  /// one topic (with distinct coverage targets when possible) and one question
  /// from each of two other topics. Level 3 returns one question for each of
  /// its four topics. If exclusions make the authored distribution impossible,
  /// this returns the best smaller/fallback authored set rather than inventing
  /// questions or changing learner progress.
  List<ListeningMissionContent> selectMissions({
    required int levelNumber,
    required Iterable<ListeningMissionContent> missionBank,
    Iterable<int> topicNumbers = const <int>[],
    int seed = 0,
    int counter = 0,
    Iterable<String> excludedQuestionIds = const <String>[],
    Iterable<String> weakTargetIds = const <String>[],
  }) {
    final excludedIds = _normalizedIds(excludedQuestionIds);
    final weakIds = _normalizedIds(weakTargetIds);
    final candidates = _availableMissions(missionBank, excludedIds);
    if (candidates.isEmpty) {
      return const <ListeningMissionContent>[];
    }

    final byTopic = <int, List<ListeningMissionContent>>{};
    for (final mission in candidates) {
      byTopic
          .putIfAbsent(mission.topicNumber, () => <ListeningMissionContent>[])
          .add(mission);
    }
    for (final missions in byTopic.values) {
      missions.sort((left, right) => left.id.compareTo(right.id));
    }

    final requestedTopics = _orderedTopics(topicNumbers, byTopic.keys);
    return switch (levelNumber) {
      1 || 2 => _selectEarlyLevelMissions(
        byTopic: byTopic,
        requestedTopics: requestedTopics,
        weakTargetIds: weakIds,
        seed: seed,
        counter: counter,
      ),
      3 => _selectLevelThreeMissions(
        byTopic: byTopic,
        requestedTopics: requestedTopics,
        weakTargetIds: weakIds,
        seed: seed,
        counter: counter,
      ),
      _ => _selectFallbackMissions(
        candidates,
        weakTargetIds: weakIds,
        seed: seed,
        counter: counter,
      ),
    };
  }

  /// Convenience entry point that preserves the topic ordering authored for a
  /// [ListeningLevelContent].
  List<ListeningMissionContent> selectMissionsForLevel(
    ListeningLevelContent level, {
    int seed = 0,
    int counter = 0,
    Iterable<String> excludedQuestionIds = const <String>[],
    Iterable<String> weakTargetIds = const <String>[],
  }) {
    return selectMissions(
      levelNumber: level.number,
      missionBank: level.missionBank,
      topicNumbers: level.topicNumbers,
      seed: seed,
      counter: counter,
      excludedQuestionIds: excludedQuestionIds,
      weakTargetIds: weakTargetIds,
    );
  }

  List<ListeningMissionContent> _selectEarlyLevelMissions({
    required Map<int, List<ListeningMissionContent>> byTopic,
    required List<int> requestedTopics,
    required Set<String> weakTargetIds,
    required int seed,
    required int counter,
  }) {
    final availableTopics = requestedTopics
        .where((topic) => (byTopic[topic]?.isNotEmpty ?? false))
        .toList(growable: false);
    if (availableTopics.length < 3) {
      return _selectFallbackMissions(
        byTopic.values.expand((missions) => missions),
        weakTargetIds: weakTargetIds,
        seed: seed,
        counter: counter,
      );
    }

    final plans = <_MissionPlan>[];
    for (final topicSet in _topicTriples(availableTopics)) {
      for (
        var doubleTopicIndex = 0;
        doubleTopicIndex < topicSet.length;
        doubleTopicIndex++
      ) {
        final doubleTopic = topicSet[doubleTopicIndex];
        final doubleCandidates = byTopic[doubleTopic]!;
        if (doubleCandidates.length < 2) {
          continue;
        }

        final singleTopics = topicSet
            .where((topic) => topic != doubleTopic)
            .toList(growable: false);
        for (final pair in _missionPairs(doubleCandidates)) {
          for (final firstSingle in byTopic[singleTopics[0]]!) {
            for (final secondSingle in byTopic[singleTopics[1]]!) {
              plans.add(
                _MissionPlan(
                  questions: <ListeningMissionContent>[
                    ...pair,
                    firstSingle,
                    secondSingle,
                  ],
                  doubleTopic: doubleTopic,
                  weakTargetIds: weakTargetIds,
                ),
              );
            }
          }
        }
      }
    }

    if (plans.isEmpty) {
      return _selectFallbackMissions(
        byTopic.values.expand((missions) => missions),
        weakTargetIds: weakTargetIds,
        seed: seed,
        counter: counter,
      );
    }

    final bestPlans = _bestBy(
      plans,
      (left, right) => left.comparePriorityTo(right),
    );
    return _rotatePick(
      bestPlans,
      seed: seed,
      counter: counter,
      keyOf: (plan) => plan.key,
    ).questions;
  }

  List<ListeningMissionContent> _selectLevelThreeMissions({
    required Map<int, List<ListeningMissionContent>> byTopic,
    required List<int> requestedTopics,
    required Set<String> weakTargetIds,
    required int seed,
    required int counter,
  }) {
    final selection = <ListeningMissionContent>[];
    for (final topic in requestedTopics.take(4)) {
      final candidates = byTopic[topic];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }
      final weakCandidates = candidates
          .where((mission) => weakTargetIds.contains(mission.coverageTargetId))
          .toList(growable: false);
      final pool = weakCandidates.isEmpty ? candidates : weakCandidates;
      selection.add(
        _rotatePick(
          pool,
          seed: seed,
          counter: counter,
          keyOf: (mission) => '$topic:${mission.id}',
        ),
      );
    }
    return selection;
  }

  List<ListeningMissionContent> _selectFallbackMissions(
    Iterable<ListeningMissionContent> source, {
    required Set<String> weakTargetIds,
    required int seed,
    required int counter,
  }) {
    final remaining = source.toList(growable: true)
      ..sort((left, right) => left.id.compareTo(right.id));
    final selection = <ListeningMissionContent>[];
    final selectedTargets = <String>{};

    while (selection.length < 4 && remaining.isNotEmpty) {
      final ranked = remaining.toList(growable: false)
        ..sort((left, right) {
          final leftPriority = _missionFallbackPriority(
            left,
            weakTargetIds: weakTargetIds,
            selectedTargets: selectedTargets,
          );
          final rightPriority = _missionFallbackPriority(
            right,
            weakTargetIds: weakTargetIds,
            selectedTargets: selectedTargets,
          );
          final priorityOrder = rightPriority.compareTo(leftPriority);
          return priorityOrder != 0
              ? priorityOrder
              : left.id.compareTo(right.id);
        });
      final highestPriority = _missionFallbackPriority(
        ranked.first,
        weakTargetIds: weakTargetIds,
        selectedTargets: selectedTargets,
      );
      final best = ranked
          .where(
            (mission) =>
                _missionFallbackPriority(
                  mission,
                  weakTargetIds: weakTargetIds,
                  selectedTargets: selectedTargets,
                ) ==
                highestPriority,
          )
          .toList(growable: false);
      final selected = _rotatePick(
        best,
        seed: seed,
        counter: counter + selection.length,
        keyOf: (mission) => mission.id,
      );
      selection.add(selected);
      selectedTargets.add(selected.coverageTargetId);
      remaining.remove(selected);
    }
    return selection;
  }
}

class _ChallengePair {
  _ChallengePair(this.first, this.second, {required Set<String> weakTargetIds})
    : targetVariety = first.targetId != second.targetId ? 1 : 0,
      formatVariety = first.format != second.format ? 1 : 0,
      weakTargetCount =
          (weakTargetIds.contains(first.targetId) ? 1 : 0) +
          (weakTargetIds.contains(second.targetId) ? 1 : 0);

  final ListeningChallengeContent first;
  final ListeningChallengeContent second;
  final int targetVariety;
  final int formatVariety;
  final int weakTargetCount;

  List<ListeningChallengeContent> get questions => <ListeningChallengeContent>[
    first,
    second,
  ];

  String get key {
    final ids = <String>[first.id, second.id]..sort();
    return ids.join('|');
  }

  bool hasExactlyIds(Set<String> ids) =>
      ids.contains(first.id) && ids.contains(second.id);

  int comparePriorityTo(_ChallengePair other) {
    final varietyOrder = (targetVariety + formatVariety).compareTo(
      other.targetVariety + other.formatVariety,
    );
    if (varietyOrder != 0) return varietyOrder;

    final targetOrder = targetVariety.compareTo(other.targetVariety);
    if (targetOrder != 0) return targetOrder;

    final formatOrder = formatVariety.compareTo(other.formatVariety);
    if (formatOrder != 0) return formatOrder;

    return weakTargetCount.compareTo(other.weakTargetCount);
  }
}

class _MissionPlan {
  _MissionPlan({
    required this.questions,
    required this.doubleTopic,
    required Set<String> weakTargetIds,
  }) : doubleTargetVariety =
           questions[0].coverageTargetId != questions[1].coverageTargetId
           ? 1
           : 0,
       uniqueTargetCount = questions
           .map((question) => question.coverageTargetId)
           .toSet()
           .length,
       weakTargetCount = questions
           .where(
             (question) => weakTargetIds.contains(question.coverageTargetId),
           )
           .length;

  final List<ListeningMissionContent> questions;
  final int doubleTopic;
  final int doubleTargetVariety;
  final int uniqueTargetCount;
  final int weakTargetCount;

  String get key {
    final ids = questions.map((question) => question.id).toList()..sort();
    return '$doubleTopic:${ids.join('|')}';
  }

  int comparePriorityTo(_MissionPlan other) {
    final doubleTargetOrder = doubleTargetVariety.compareTo(
      other.doubleTargetVariety,
    );
    if (doubleTargetOrder != 0) return doubleTargetOrder;

    final uniqueTargetOrder = uniqueTargetCount.compareTo(
      other.uniqueTargetCount,
    );
    if (uniqueTargetOrder != 0) return uniqueTargetOrder;

    return weakTargetCount.compareTo(other.weakTargetCount);
  }
}

List<ListeningChallengeContent> _availableChallenges(
  Iterable<ListeningChallengeContent> source,
  Set<String> excludedIds,
) {
  final seenIds = <String>{};
  final candidates = <ListeningChallengeContent>[];
  for (final challenge in source) {
    if (excludedIds.contains(challenge.id) || !seenIds.add(challenge.id)) {
      continue;
    }
    candidates.add(challenge);
  }
  candidates.sort((left, right) => left.id.compareTo(right.id));
  return candidates;
}

List<ListeningMissionContent> _availableMissions(
  Iterable<ListeningMissionContent> source,
  Set<String> excludedIds,
) {
  final seenIds = <String>{};
  final candidates = <ListeningMissionContent>[];
  for (final mission in source) {
    if (excludedIds.contains(mission.id) || !seenIds.add(mission.id)) {
      continue;
    }
    candidates.add(mission);
  }
  candidates.sort((left, right) => left.id.compareTo(right.id));
  return candidates;
}

Set<String> _normalizedIds(Iterable<String> ids) {
  return ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
}

List<int> _orderedTopics(
  Iterable<int> requestedTopics,
  Iterable<int> available,
) {
  final availableSet = available.toSet();
  final ordered = <int>[];
  for (final topic in requestedTopics) {
    if (availableSet.contains(topic) && !ordered.contains(topic)) {
      ordered.add(topic);
    }
  }
  final extras =
      availableSet.where((topic) => !ordered.contains(topic)).toList()..sort();
  return <int>[...ordered, ...extras];
}

Iterable<List<int>> _topicTriples(List<int> topics) sync* {
  for (var firstIndex = 0; firstIndex < topics.length - 2; firstIndex++) {
    for (
      var secondIndex = firstIndex + 1;
      secondIndex < topics.length - 1;
      secondIndex++
    ) {
      for (
        var thirdIndex = secondIndex + 1;
        thirdIndex < topics.length;
        thirdIndex++
      ) {
        yield <int>[
          topics[firstIndex],
          topics[secondIndex],
          topics[thirdIndex],
        ];
      }
    }
  }
}

Iterable<List<ListeningMissionContent>> _missionPairs(
  List<ListeningMissionContent> candidates,
) sync* {
  for (var firstIndex = 0; firstIndex < candidates.length - 1; firstIndex++) {
    for (
      var secondIndex = firstIndex + 1;
      secondIndex < candidates.length;
      secondIndex++
    ) {
      yield <ListeningMissionContent>[
        candidates[firstIndex],
        candidates[secondIndex],
      ];
    }
  }
}

int _missionFallbackPriority(
  ListeningMissionContent mission, {
  required Set<String> weakTargetIds,
  required Set<String> selectedTargets,
}) {
  var priority = 0;
  if (weakTargetIds.contains(mission.coverageTargetId)) {
    priority += 2;
  }
  if (!selectedTargets.contains(mission.coverageTargetId)) {
    priority += 1;
  }
  return priority;
}

List<T> _bestBy<T>(List<T> values, int Function(T left, T right) compare) {
  if (values.isEmpty) return <T>[];

  var best = values.first;
  for (final value in values.skip(1)) {
    if (compare(value, best) > 0) {
      best = value;
    }
  }
  return values
      .where((value) => compare(value, best) == 0)
      .toList(growable: false);
}

T _rotatePick<T>(
  List<T> values, {
  required int seed,
  required int counter,
  required String Function(T value) keyOf,
}) {
  assert(values.isNotEmpty);
  final ordered = values.toList(growable: false)
    ..sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  final index = _positiveModulo(seed + counter, ordered.length);
  return ordered[index];
}

int _positiveModulo(int value, int modulus) {
  final remainder = value % modulus;
  return remainder < 0 ? remainder + modulus : remainder;
}
