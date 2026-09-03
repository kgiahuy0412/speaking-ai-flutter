import 'homi_fallback_catalog.dart';

enum ControlledSpeechState {
  root,
  translateMenu,
  translateContinuous,
  course,
  translationResult,
  vocabulary,
}

enum ControlledSpeechIntent {
  navCourse,
  navVocabulary,
  navTranslate,
  globalHelp,
  globalStop,
  translateSingle,
  translateContinuous,
  courseContinue,
  courseNextSentence,
  coursePreviousSentence,
  courseReplayCurrent,
  courseRestartCurrent,
  courseNextLesson,
  coursePreviousLesson,
  vocabularyPracticeAgain,
  vocabularyStars,
}

class ControlledSpeechRule {
  const ControlledSpeechRule({
    required this.intent,
    required this.states,
    required this.priority,
    required this.phrases,
    this.global = false,
  });

  final ControlledSpeechIntent intent;
  final Set<ControlledSpeechState> states;
  final int priority;
  final List<String> phrases;
  final bool global;
}

class ControlledSpeechMatch {
  const ControlledSpeechMatch({
    required this.intent,
    required this.matchedPhrase,
    required this.normalizedTranscript,
    required this.priority,
    required this.candidateIndex,
    required this.stateSpecific,
  });

  final ControlledSpeechIntent intent;
  final String matchedPhrase;
  final String normalizedTranscript;
  final int priority;
  final int candidateIndex;
  final bool stateSpecific;
}

/// Versioned, deterministic speech grammar transcribed from sheet 01_受控表.
///
/// The spreadsheet remains the product source of truth. This runtime copy is
/// intentionally exact-match after normalization: it never guesses an intent
/// from open-ended child speech. VOCAB_NEW_AUTO is excluded because it is a
/// system trigger rather than something a child says.
class ControlledSpeechLexicon {
  const ControlledSpeechLexicon();

  static const String version = 'V0.2-homi-fallback';

  /// The original controlled grammar plus the approved HOMI child variants.
  ///
  /// Each fallback intent is added only to its matching interaction state.
  /// This is deliberate: phrases such as "nói lại" and "học lại" have
  /// different meanings in a lesson, a vocabulary review, and a root menu.
  static final List<ControlledSpeechRule> rules = <ControlledSpeechRule>[
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.globalStop,
      states: <ControlledSpeechState>{},
      priority: 0,
      global: true,
      phrases: _mergePhrases('INT-001', <String>[
        'Dừng lại',
        'Dừng',
        'Thôi',
        'Không học nữa',
        'Tạm dừng',
        'Stop',
        'Dừng đi',
        'Thôi nha',
        'Không muốn nữa',
        'Con không thích',
        'Im lặng',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.navCourse,
      states: <ControlledSpeechState>{ControlledSpeechState.root},
      priority: 1,
      phrases: _mergePhrases('INT-002', <String>[
        'Học theo chủ đề',
        'Bắt đầu học',
        'Con muốn học',
        'Học chủ đề',
        'Học tình huống',
        'Con muốn học theo Chủ đề',
        'Học đi',
        'Con học',
        'Học cái này',
        'Học bây giờ',
        'Chủ đề',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.navVocabulary,
      states: <ControlledSpeechState>{ControlledSpeechState.root},
      priority: 1,
      phrases: _mergePhrases('INT-003', <String>[
        'Học từ mới',
        'Con muốn học từ',
        'Học từ vựng',
        'Luyện từ mới',
        'Từ mới',
        'Học từ',
        'Học mới',
        'Con học từ này',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.navTranslate,
      states: <ControlledSpeechState>{ControlledSpeechState.root},
      priority: 1,
      phrases: _mergePhrases('INT-004', <String>[
        'Dịch sang tiếng Anh',
        'Dịch',
        'Con muốn dịch',
        'Dịch giúp con',
        'Dịch tiếng Anh',
        'Dịch cho con',
        'Dịch đi',
        'Con muốn nói tiếng Anh',
        'Dịch câu này',
        'Dịch cái này',
        'Dịch từ',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.translateSingle,
      states: <ControlledSpeechState>{ControlledSpeechState.translateMenu},
      priority: 1,
      phrases: <String>[
        'Dịch một câu',
        'Dịch câu này',
        'Dịch chữ này',
        'Phiên dịch',
        'Dịch từng câu',
        'Dịch cho con một câu',
        'Dịch',
        'Dịch câu',
        'Dịch chữ',
        'Câu này tiếng Anh sao',
        'Dịch cái này',
        'Dịch tiếng Anh',
        'Làm sao để nói tiếng Anh',
        'Nói tiếng Anh',
      ],
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.translateContinuous,
      states: <ControlledSpeechState>{ControlledSpeechState.translateMenu},
      priority: 1,
      phrases: _mergePhrases('INT-006', <String>[
        'Dịch liên tục',
        'Dịch nhiều',
        'Dịch liên tiếp',
        'Dịch tiếp đi',
        'Con nói liên tục',
        'Dịch hoài',
        'Dịch nhiều câu',
        'Dịch tiếp',
        'Nói tiếp',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.courseContinue,
      states: <ControlledSpeechState>{
        ControlledSpeechState.root,
        ControlledSpeechState.course,
      },
      priority: 1,
      phrases: _mergePhrases('INT-007', <String>[
        'Tiếp tục học',
        'Học tiếp',
        'Tiếp tục bài này',
        'Học tiếp đi',
        'Con muốn học nữa',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.courseNextSentence,
      states: <ControlledSpeechState>{ControlledSpeechState.course},
      priority: 1,
      phrases: _mergePhrases('INT-008', <String>[
        'Câu tiếp theo',
        'Qua câu tiếp',
        'Câu sau',
        'Nói câu khác',
        'Câu nữa',
        'Tiếp đi',
        'Câu tiếp',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.coursePreviousSentence,
      states: <ControlledSpeechState>{ControlledSpeechState.course},
      priority: 1,
      phrases: _mergePhrases('INT-009', <String>[
        'Câu trước',
        'Quay lại câu trước',
        'Lùi một câu',
        'Câu hồi nãy',
        'Quay lại',
        'Về trước',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.courseReplayCurrent,
      states: <ControlledSpeechState>{
        ControlledSpeechState.course,
        ControlledSpeechState.translationResult,
      },
      priority: 1,
      phrases: _mergePhrases('INT-010', <String>[
        'Nghe lại',
        'Nói lại',
        'Đọc lại câu này',
        'Cho con nghe lại',
        'Nghe nữa',
        'Nói lại đi',
        'Lặp lại',
        'Lần nữa',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.courseRestartCurrent,
      states: <ControlledSpeechState>{ControlledSpeechState.course},
      priority: 1,
      phrases: _mergePhrases('INT-011', <String>[
        'Học lại từ đầu',
        'Học từ đầu',
        'Làm lại bài này',
        'Học lại',
        'Lại từ đầu',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.courseNextLesson,
      states: <ControlledSpeechState>{ControlledSpeechState.course},
      priority: 1,
      phrases: _mergePhrases('INT-012', <String>[
        'Bài tiếp theo',
        'Qua bài mới',
        'Bài sau',
        'Bài tiếp',
        'Bài nữa',
        'Học bài khác',
        'Bài mới',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.coursePreviousLesson,
      states: <ControlledSpeechState>{ControlledSpeechState.course},
      priority: 1,
      phrases: _mergePhrases('INT-013', <String>[
        'Bài trước',
        'Quay lại bài trước',
        'Bài hồi nãy',
        'Bài trước đó',
        'Quay lại bài cũ',
        'Bài lúc nãy',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.vocabularyPracticeAgain,
      states: <ControlledSpeechState>{ControlledSpeechState.vocabulary},
      priority: 1,
      phrases: _mergePhrases('INT-014', <String>[
        'Luyện lại',
        'Học lại phần chưa thuộc',
        'Luyện từ khó',
        'Nói lại',
        'Học lại',
        'Mấy câu khó',
        'Luyện nữa',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.vocabularyStars,
      states: <ControlledSpeechState>{ControlledSpeechState.vocabulary},
      priority: 1,
      phrases: _mergePhrases('INT-015', <String>[
        'Ngôi sao của con',
        'Xem ngôi sao',
        'Học phần con đã thuộc',
        'Ngôi sao',
        'Con giỏi',
        'Xem sao',
        'Muốn ngôi sao',
        'Nhìn ngôi sao',
      ]),
    ),
    ControlledSpeechRule(
      intent: ControlledSpeechIntent.globalHelp,
      states: <ControlledSpeechState>{},
      priority: 2,
      global: true,
      phrases: _mergePhrases('INT-016', <String>[
        'Giúp con với',
        'Con không biết',
        'Phải làm gì?',
        'Nói lại đi',
        'Giúp',
        'Giúp con',
        'Không biết',
        'Không hiểu',
        'Sao đây?',
        'Nói gì?',
      ]),
    ),
  ];

  static final Map<
    ControlledSpeechState,
    Map<String, List<_IndexedControlledSpeechRule>>
  >
  _index = _buildIndex();

  static List<String> _mergePhrases(
    String fallbackIntentId,
    List<String> existingPhrases,
  ) {
    return <String>{
      ...existingPhrases,
      ...?HomiFallbackCatalog.childPhrasesByIntent[fallbackIntentId],
    }.toList(growable: false);
  }

  ControlledSpeechMatch? resolve(
    String transcript, {
    required ControlledSpeechState state,
  }) => resolveCandidates(<String>[transcript], state: state);

  ControlledSpeechMatch? resolveCandidates(
    Iterable<String> transcripts, {
    required ControlledSpeechState state,
  }) {
    ControlledSpeechMatch? best;
    var candidateIndex = 0;
    for (final transcript in transcripts) {
      final normalizedTranscript = normalize(transcript);
      if (normalizedTranscript.isEmpty) {
        candidateIndex += 1;
        continue;
      }
      final indexedRules =
          _index[state]?[normalizedTranscript] ??
          const <_IndexedControlledSpeechRule>[];
      for (final indexed in indexedRules) {
        final rule = indexed.rule;
        final stateSpecific = rule.states.contains(state);
        final candidate = ControlledSpeechMatch(
          intent: rule.intent,
          matchedPhrase: indexed.phrase,
          normalizedTranscript: normalizedTranscript,
          priority: rule.priority,
          candidateIndex: candidateIndex,
          stateSpecific: stateSpecific,
        );
        if (_isBetter(candidate, best)) {
          best = candidate;
        }
      }
      candidateIndex += 1;
    }
    return best;
  }

  static Map<
    ControlledSpeechState,
    Map<String, List<_IndexedControlledSpeechRule>>
  >
  _buildIndex() {
    final index =
        <
          ControlledSpeechState,
          Map<String, List<_IndexedControlledSpeechRule>>
        >{};
    for (final state in ControlledSpeechState.values) {
      final phrases = <String, List<_IndexedControlledSpeechRule>>{};
      for (final rule in rules) {
        if (!rule.global && !rule.states.contains(state)) {
          continue;
        }
        for (final phrase in rule.phrases) {
          (phrases[normalize(phrase)] ??= <_IndexedControlledSpeechRule>[]).add(
            _IndexedControlledSpeechRule(rule: rule, phrase: phrase),
          );
        }
      }
      index[state] = phrases;
    }
    return index;
  }

  static bool _isBetter(
    ControlledSpeechMatch candidate,
    ControlledSpeechMatch? current,
  ) {
    if (current == null) {
      return true;
    }
    if (candidate.priority != current.priority) {
      return candidate.priority < current.priority;
    }
    if (candidate.stateSpecific != current.stateSpecific) {
      return candidate.stateSpecific;
    }
    return candidate.candidateIndex < current.candidateIndex;
  }

  static String normalize(String value) {
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
}

class _IndexedControlledSpeechRule {
  const _IndexedControlledSpeechRule({
    required this.rule,
    required this.phrase,
  });

  final ControlledSpeechRule rule;
  final String phrase;
}
