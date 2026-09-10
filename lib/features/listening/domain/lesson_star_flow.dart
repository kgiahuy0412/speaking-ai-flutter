import 'listening_content.dart';

/// Defines the stable Star slots that belong to one authored lesson run.
///
/// Mission Stars belong to the lesson that opened the Level Mission. They are
/// optional because only one lesson in a Level can own those four slots.
abstract final class LessonStarFlow {
  static const int missionStarCount = 4;

  static Set<String> expectedStarIds(
    ListeningLessonContent lesson, {
    bool includeMission = false,
  }) {
    final ids = <String>{
      for (final sentence in lesson.sentences) 'core:${sentence.id}',
      'challenge:1',
      'challenge:2',
    };
    final rolePlay = lesson.rolePlay;
    if (rolePlay != null) {
      for (final indexedTurn in rolePlay.turns.indexed) {
        if (indexedTurn.$2.speaker == ListeningRolePlaySpeaker.child) {
          ids.add('roleplay:${indexedTurn.$1 + 1}');
        }
      }
    }
    if (includeMission) {
      for (var index = 1; index <= missionStarCount; index += 1) {
        ids.add('mission:$index');
      }
    }
    return ids;
  }

  static bool hasEarnedMissionStar(Iterable<String> earnedStarIds) =>
      earnedStarIds.any((id) => id.startsWith('mission:'));

  static int remainingStarCount(
    ListeningLessonContent lesson,
    Set<String> earnedStarIds, {
    bool includeMission = false,
  }) {
    final expected = expectedStarIds(lesson, includeMission: includeMission);
    return expected.difference(earnedStarIds).length;
  }

  static bool shouldReplayPassedMission({
    required bool isRelearn,
    required bool hasMissionStarSlots,
    required Set<String> earnedStarIds,
  }) {
    if (!isRelearn || !hasMissionStarSlots) return false;
    for (var index = 1; index <= missionStarCount; index += 1) {
      if (!earnedStarIds.contains('mission:$index')) return true;
    }
    return false;
  }
}
