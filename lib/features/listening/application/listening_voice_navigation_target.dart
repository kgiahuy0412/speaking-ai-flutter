import 'package:flutter/foundation.dart';

import '../domain/listening_catalog.dart';

/// A voice deep link into the topic-learning journey.
@immutable
class ListeningVoiceNavigationTarget {
  const ListeningVoiceNavigationTarget({
    required this.recognizedText,
    required this.openLesson,
    this.topicNumber,
    this.lessonNumber,
    this.childAge,
    this.fallbackTopicIndex,
  });

  final String recognizedText;
  final bool openLesson;
  final int? topicNumber;
  final int? lessonNumber;
  final int? childAge;

  /// The topic currently visible when a child only says "Mở bài 2".
  final int? fallbackTopicIndex;

  int get resolvedLessonNumber => lessonNumber ?? 1;

  int? resolveTopicIndex(ListeningAgeCatalog catalog) {
    final explicitTopicNumber = topicNumber;
    if (explicitTopicNumber != null &&
        explicitTopicNumber >= 1 &&
        explicitTopicNumber <= catalog.topics.length) {
      return explicitTopicNumber - 1;
    }

    final query = normalizeListeningVoiceText(recognizedText);
    final queryWords = query.split(' ').where(_isMeaningfulWord).toSet();
    final normalizedTitles = catalog.topics
        .map((topic) => normalizeListeningVoiceText(topic.titleVi))
        .toList(growable: false);
    final topicWordSets = normalizedTitles
        .map((title) => title.split(' ').where(_isMeaningfulWord).toSet())
        .toList(growable: false);
    final wordTopicCounts = <String, int>{};
    for (final titleWords in topicWordSets) {
      for (final word in titleWords) {
        wordTopicCounts[word] = (wordTopicCounts[word] ?? 0) + 1;
      }
    }
    var bestIndex = -1;
    var bestScore = -1;
    var bestScoreIsTied = false;

    for (var index = 0; index < catalog.topics.length; index += 1) {
      final title = normalizedTitles[index];
      if (title.isEmpty) {
        continue;
      }
      if (' $query '.contains(' $title ')) {
        final score = 10000 + title.length;
        if (score > bestScore) {
          bestIndex = index;
          bestScore = score;
          bestScoreIsTied = false;
        }
        continue;
      }

      final titleWords = topicWordSets[index];
      final matchedWords = titleWords.intersection(queryWords);
      if (matchedWords.length < 2) {
        final singleMatch = matchedWords.isEmpty ? null : matchedWords.first;
        if (singleMatch == null ||
            singleMatch.length < 3 ||
            wordTopicCounts[singleMatch] != 1) {
          continue;
        }
      }
      final score =
          (matchedWords.length * 100) +
          ((matchedWords.length * 10) ~/ titleWords.length);
      if (score > bestScore) {
        bestIndex = index;
        bestScore = score;
        bestScoreIsTied = false;
      } else if (score == bestScore) {
        bestScoreIsTied = true;
      }
    }

    if (bestIndex >= 0 && !bestScoreIsTied) {
      return bestIndex;
    }
    if (!openLesson) {
      return null;
    }
    final fallback = fallbackTopicIndex;
    if (fallback != null && fallback >= 0 && fallback < catalog.topics.length) {
      return fallback;
    }
    return catalog.continueTopicIndex.clamp(0, catalog.topics.length - 1);
  }

  static bool _isMeaningfulWord(String word) =>
      word.length >= 2 && !_ignoredWords.contains(word);

  static const Set<String> _ignoredWords = <String>{
    'bai',
    'chu',
    'de',
    'hoc',
    'mo',
    'vao',
    'xem',
    'con',
    'toi',
    'muon',
    'cho',
    'giup',
    'hay',
    'di',
    'den',
    'chuyen',
    'sang',
    'trong',
    'so',
    'va',
    'cua',
    'nhung',
    'mot',
    'hai',
    'ba',
    'bon',
    'nam',
    'sau',
    'bay',
    'tam',
    'chin',
    'muoi',
    'dau',
    'tien',
  };
}

String normalizeListeningVoiceText(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = <String, String>{
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
