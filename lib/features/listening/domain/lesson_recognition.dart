/// Deterministic matching utilities for a child's spoken lesson answer.
///
/// The matcher deliberately separates text normalization from accepted answer
/// variants. A variant is for a harmless surface or ASR transcription change
/// (for example, a contraction expanded by the recognizer), not a semantic
/// synonym or an answer-option label. Curriculum scoring still requires the
/// authored target phrase.
enum LessonRecognitionMatchKind {
  noMatch,
  exact,
  acceptedVariant,
  containedExpected,
  fuzzy,
}

class LessonRecognitionResult {
  const LessonRecognitionResult({
    required this.kind,
    required this.normalizedExpectedEnglish,
    required this.normalizedTranscript,
    this.matchedText,
  });

  final LessonRecognitionMatchKind kind;
  final String normalizedExpectedEnglish;
  final String normalizedTranscript;

  /// The authored target or declared variant that produced the match.
  final String? matchedText;

  bool get matched => kind != LessonRecognitionMatchKind.noMatch;
}

/// Matches a transcript against one authored English target.
///
/// Keep [acceptedVariants] narrowly scoped to the current target. Do not add
/// free-form paraphrases, other question options, or "A"/"B" labels: V4
/// requires the child to say the full English target.
class LessonRecognitionMatcher {
  const LessonRecognitionMatcher({
    this.defaultFuzzyThreshold = 0.90,
    this.defaultMaxExtraTokens = 2,
  }) : assert(defaultFuzzyThreshold >= 0 && defaultFuzzyThreshold <= 1),
       assert(defaultMaxExtraTokens >= 0);

  /// A deliberately conservative character-similarity threshold. Fuzzy
  /// matching additionally requires token-by-token alignment, so it cannot
  /// turn a different answer option into a pass merely because it is similar.
  final double defaultFuzzyThreshold;

  /// Short harmless fillers such as "okay" may surround an otherwise exact
  /// answer. Longer utterances must be handled by a higher-level dialogue
  /// recognizer instead of this target matcher.
  final int defaultMaxExtraTokens;

  LessonRecognitionResult match({
    required String expectedEnglish,
    required String transcript,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = true,
    double? fuzzyThreshold,
    int? maxExtraTokens,
  }) {
    final normalizedExpected = normalizeLessonRecognitionText(expectedEnglish);
    final normalizedTranscript = normalizeLessonRecognitionText(transcript);
    final resultBase = _ResultBase(
      normalizedExpectedEnglish: normalizedExpected,
      normalizedTranscript: normalizedTranscript,
    );

    if (normalizedExpected.isEmpty || normalizedTranscript.isEmpty) {
      return resultBase.noMatch();
    }

    final candidates = <_RecognitionCandidate>[
      _RecognitionCandidate(
        original: expectedEnglish,
        normalized: normalizedExpected,
        isAcceptedVariant: false,
      ),
      ...acceptedVariants
          .map(
            (variant) => _RecognitionCandidate(
              original: variant,
              normalized: normalizeLessonRecognitionText(variant),
              isAcceptedVariant: true,
            ),
          )
          .where((candidate) => candidate.normalized.isNotEmpty),
    ];

    final uniqueCandidates = <String>{};
    final resolvedCandidates = candidates
        .where((candidate) => uniqueCandidates.add(candidate.normalized))
        .toList(growable: false);
    final transcriptTokens = normalizedTranscript.split(' ');
    final resolvedMaxExtraTokens = maxExtraTokens ?? defaultMaxExtraTokens;
    final resolvedThreshold = fuzzyThreshold ?? defaultFuzzyThreshold;

    for (final candidate in resolvedCandidates) {
      if (normalizedTranscript == candidate.normalized) {
        return resultBase.match(
          candidate.isAcceptedVariant
              ? LessonRecognitionMatchKind.acceptedVariant
              : LessonRecognitionMatchKind.exact,
          candidate.original,
        );
      }
    }

    for (final candidate in resolvedCandidates) {
      final candidateTokens = candidate.normalized.split(' ');
      if (_containsWholeTarget(
        transcriptTokens,
        candidateTokens,
        maxExtraTokens: resolvedMaxExtraTokens,
        requireAllExpectedTokens: requireAllExpectedTokens,
      )) {
        return resultBase.match(
          LessonRecognitionMatchKind.containedExpected,
          candidate.original,
        );
      }
    }

    for (final candidate in resolvedCandidates) {
      if (_isSafeFuzzyMatch(
        candidate.normalized,
        normalizedTranscript,
        requireAllExpectedTokens: requireAllExpectedTokens,
        fuzzyThreshold: resolvedThreshold,
      )) {
        return resultBase.match(
          LessonRecognitionMatchKind.fuzzy,
          candidate.original,
        );
      }
    }

    return resultBase.noMatch();
  }

  bool matches({
    required String expectedEnglish,
    required String transcript,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = true,
    double? fuzzyThreshold,
    int? maxExtraTokens,
  }) {
    return match(
      expectedEnglish: expectedEnglish,
      transcript: transcript,
      acceptedVariants: acceptedVariants,
      requireAllExpectedTokens: requireAllExpectedTokens,
      fuzzyThreshold: fuzzyThreshold,
      maxExtraTokens: maxExtraTokens,
    ).matched;
  }
}

/// Makes common presentation and recognizer differences comparable without
/// introducing semantic aliases.
String normalizeLessonRecognitionText(String value) {
  var normalized = value.toLowerCase();

  for (final entry in _unicodeReplacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  normalized = normalized.replaceAll(RegExp(r'[\u0300-\u036f]'), '');

  for (final entry in _contractionExpansions.entries) {
    normalized = normalized.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b'),
      entry.value,
    );
  }

  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  for (final entry in _numericTokenExpansions.entries) {
    normalized = normalized.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b'),
      entry.value,
    );
  }

  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _containsWholeTarget(
  List<String> transcriptTokens,
  List<String> candidateTokens, {
  required int maxExtraTokens,
  required bool requireAllExpectedTokens,
}) {
  if (candidateTokens.isEmpty ||
      transcriptTokens.length < candidateTokens.length) {
    return false;
  }

  if (requireAllExpectedTokens &&
      !_containsEveryExpectedToken(transcriptTokens, candidateTokens)) {
    return false;
  }

  final extras = transcriptTokens.length - candidateTokens.length;
  if (extras > maxExtraTokens) {
    return false;
  }

  for (
    var start = 0;
    start <= transcriptTokens.length - candidateTokens.length;
    start += 1
  ) {
    var matches = true;
    for (var index = 0; index < candidateTokens.length; index += 1) {
      if (transcriptTokens[start + index] != candidateTokens[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

bool _containsEveryExpectedToken(
  List<String> transcriptTokens,
  List<String> candidateTokens,
) {
  final remaining = <String, int>{};
  for (final token in candidateTokens) {
    remaining[token] = (remaining[token] ?? 0) + 1;
  }
  for (final token in transcriptTokens) {
    final needed = remaining[token] ?? 0;
    if (needed == 1) {
      remaining.remove(token);
    } else if (needed > 1) {
      remaining[token] = needed - 1;
    }
  }
  return remaining.isEmpty;
}

bool _isSafeFuzzyMatch(
  String candidate,
  String transcript, {
  required bool requireAllExpectedTokens,
  required double fuzzyThreshold,
}) {
  final candidateTokens = candidate.split(' ');
  final transcriptTokens = transcript.split(' ');

  // One-word targets are particularly vulnerable to semantic near misses
  // (for example, red/read). Require an exact or explicitly declared variant.
  if (candidateTokens.length < 2 || transcriptTokens.length < 2) {
    return false;
  }
  if (requireAllExpectedTokens &&
      candidateTokens.length != transcriptTokens.length) {
    return false;
  }
  if (!requireAllExpectedTokens &&
      (candidateTokens.length - transcriptTokens.length).abs() > 1) {
    return false;
  }
  if (candidateTokens.length != transcriptTokens.length) {
    return false;
  }

  final threshold = fuzzyThreshold.clamp(0.0, 1.0).toDouble();
  if (_similarity(candidate, transcript) < threshold) {
    return false;
  }

  var typoCount = 0;
  for (var index = 0; index < candidateTokens.length; index += 1) {
    final expectedToken = candidateTokens[index];
    final actualToken = transcriptTokens[index];
    if (expectedToken == actualToken) {
      continue;
    }
    if (!_isSafeSingleTokenTypo(expectedToken, actualToken)) {
      return false;
    }
    typoCount += 1;
    if (typoCount > 1) {
      return false;
    }
  }
  return typoCount == 1;
}

bool _isSafeSingleTokenTypo(String expected, String actual) {
  // Short words are commonly different answer options (for example, red/read
  // or cat/bat). A long, non-prefix word with one edit is a narrower signal of
  // an ASR spelling slip such as school/schol.
  if (expected.length < 6 || actual.length < 5) {
    return false;
  }
  if (expected.startsWith(actual) || actual.startsWith(expected)) {
    return false;
  }
  return _levenshteinDistance(expected, actual) == 1;
}

double _similarity(String left, String right) {
  final longest = left.length > right.length ? left.length : right.length;
  if (longest == 0) {
    return 0;
  }
  return 1 - (_levenshteinDistance(left, right) / longest);
}

int _levenshteinDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex;
    for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      final substitution =
          left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
          ? 0
          : 1;
      final insertion = current[rightIndex - 1] + 1;
      final deletion = previous[rightIndex] + 1;
      final replacement = previous[rightIndex - 1] + substitution;
      current[rightIndex] = _min3(insertion, deletion, replacement);
    }
    previous = current;
  }
  return previous.last;
}

int _min3(int first, int second, int third) {
  var result = first < second ? first : second;
  if (third < result) {
    result = third;
  }
  return result;
}

class _RecognitionCandidate {
  const _RecognitionCandidate({
    required this.original,
    required this.normalized,
    required this.isAcceptedVariant,
  });

  final String original;
  final String normalized;
  final bool isAcceptedVariant;
}

class _ResultBase {
  const _ResultBase({
    required this.normalizedExpectedEnglish,
    required this.normalizedTranscript,
  });

  final String normalizedExpectedEnglish;
  final String normalizedTranscript;

  LessonRecognitionResult noMatch() => LessonRecognitionResult(
    kind: LessonRecognitionMatchKind.noMatch,
    normalizedExpectedEnglish: normalizedExpectedEnglish,
    normalizedTranscript: normalizedTranscript,
  );

  LessonRecognitionResult match(
    LessonRecognitionMatchKind kind,
    String matchedText,
  ) => LessonRecognitionResult(
    kind: kind,
    normalizedExpectedEnglish: normalizedExpectedEnglish,
    normalizedTranscript: normalizedTranscript,
    matchedText: matchedText,
  );
}

const Map<String, String> _unicodeReplacements = <String, String>{
  '\u00a0': ' ',
  '\u1680': ' ',
  '\u2000': ' ',
  '\u2001': ' ',
  '\u2002': ' ',
  '\u2003': ' ',
  '\u2004': ' ',
  '\u2005': ' ',
  '\u2006': ' ',
  '\u2007': ' ',
  '\u2008': ' ',
  '\u2009': ' ',
  '\u200a': ' ',
  '\u202f': ' ',
  '\u205f': ' ',
  '\u3000': ' ',
  '\u2018': "'",
  '\u2019': "'",
  '\u201a': "'",
  '\u201b': "'",
  '\u02bc': "'",
  '\uff07': "'",
  '\u0060': "'",
  '\u2010': '-',
  '\u2011': '-',
  '\u2012': '-',
  '\u2013': '-',
  '\u2014': '-',
  '\u2015': '-',
  '\u2212': '-',
  '\u00ad': '',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ß': 'ss',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  '０': '0',
  '１': '1',
  '２': '2',
  '３': '3',
  '４': '4',
  '５': '5',
  '６': '6',
  '７': '7',
  '８': '8',
  '９': '9',
};

const Map<String, String> _contractionExpansions = <String, String>{
  "i'm": 'i am',
  "i'll": 'i will',
  "i'd": 'i would',
  "you're": 'you are',
  "we're": 'we are',
  "they're": 'they are',
  "he's": 'he is',
  "she's": 'she is',
  "it's": 'it is',
  "that's": 'that is',
  "what's": 'what is',
  "where's": 'where is',
  "let's": 'let us',
  "can't": 'cannot',
  "don't": 'do not',
  "doesn't": 'does not',
  "isn't": 'is not',
  "aren't": 'are not',
  "won't": 'will not',
};

const Map<String, String> _numericTokenExpansions = <String, String>{
  '0': 'zero',
  '1': 'one',
  '2': 'two',
  '3': 'three',
  '4': 'four',
  '5': 'five',
  '6': 'six',
  '7': 'seven',
  '8': 'eight',
  '9': 'nine',
  '10': 'ten',
  '11': 'eleven',
  '12': 'twelve',
  '13': 'thirteen',
  '14': 'fourteen',
  '15': 'fifteen',
  '16': 'sixteen',
  '17': 'seventeen',
  '18': 'eighteen',
  '19': 'nineteen',
  '20': 'twenty',
  '30': 'thirty',
  '40': 'forty',
  '50': 'fifty',
};
