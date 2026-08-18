enum VoiceNavigationDestination {
  conversation,
  vocabulary,
  topics,
  history,
  settings,
}

class VoiceNavigationIntent {
  const VoiceNavigationIntent({
    required this.destination,
    required this.recognizedText,
    required this.matchedPhrase,
    this.topicNumber,
    this.lessonNumber,
    this.childAge,
    this.openLesson = false,
    this.enterMainSpeakingMode = false,
  });

  final VoiceNavigationDestination destination;
  final String recognizedText;
  final String matchedPhrase;
  final int? topicNumber;
  final int? lessonNumber;
  final int? childAge;
  final bool openLesson;
  final bool enterMainSpeakingMode;
}

class VoiceNavigationIntentResolver {
  const VoiceNavigationIntentResolver();

  static const List<String> _wakePhrases = <String>[
    'hey pico',
    'hey piko',
    'hay pico',
    'hey pipo',
    'hey pi co',
    'hay pi co',
    'hey bi co',
    'hay bi co',
    'hey bico',
    'hay bico',
    'hey bigo',
    'hay bigo',
    'e pico',
    'e pi co',
  ];

  static const List<String> _commandCues = <String>[
    'con muon',
    'cho con',
    'giup con',
    'toi muon',
    'hay mo',
    'di den',
    'chuyen den',
    'chuyen sang',
    'quay ve',
    'tro ve',
    '我想',
    '帮我',
    '打开',
    '进入',
    '前往',
    '学习',
    '练习',
    '查看',
  ];

  static const List<String> _leadingCommandCues = <String>[
    'mo',
    'vao',
    'xem',
    'hoc',
    'luyen',
    'bat dau',
    'quay ve',
    'tro ve',
  ];

  static const List<
    ({VoiceNavigationDestination destination, List<String> phrases})
  >
  _rules = <({VoiceNavigationDestination destination, List<String> phrases})>[
    (
      destination: VoiceNavigationDestination.vocabulary,
      phrases: <String>[
        'hoc tu vung',
        'on tu vung',
        'hoc tu moi',
        'luyen tu',
        'hoc tu',
        'kho tu vung',
        'tu vung',
        'tu moi',
        '词汇',
        '生词',
      ],
    ),
    (
      destination: VoiceNavigationDestination.topics,
      phrases: <String>[
        'luyen nghe theo chu de',
        'bat dau bai hoc',
        'hoc khoa hoc',
        'hoc theo chu de',
        'hoc chu de',
        'hoc bai',
        'chu de',
        '主题听力',
        '主题',
      ],
    ),
    (
      destination: VoiceNavigationDestination.conversation,
      phrases: <String>[
        'luyen giao tiep',
        'trang giao tiep',
        'giao tiep',
        'luyen noi',
        'noi chuyen',
        '沟通',
        '口语练习',
      ],
    ),
    (
      destination: VoiceNavigationDestination.history,
      phrases: <String>[
        'lich su gan day',
        'lich su hoc',
        'lich su',
        'cau da hoc',
        '历史记录',
        '历史',
      ],
    ),
    (
      destination: VoiceNavigationDestination.settings,
      phrases: <String>[
        'mo cai dat',
        'cai dat',
        'thiet lap',
        'doi giao dien',
        '设置',
      ],
    ),
  ];

  VoiceNavigationIntent? resolve(
    String recognizedText, {
    bool allowShortDirectCommand = true,
  }) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty) {
      return null;
    }

    final hasCommandCue = _hasCommandCue(normalized);
    final wordCount = normalized.split(' ').length;
    final topicNumber = _numberAfter(normalized, 'chu de');
    final lessonNumber = _numberAfter(normalized, 'bai');
    final hasLessonRequest = _hasLessonRequest(normalized);
    final isShortLessonRequest =
        allowShortDirectCommand &&
        wordCount <= 4 &&
        (normalized == 'bai hoc' || normalized.startsWith('bai '));
    if (hasLessonRequest && (hasCommandCue || isShortLessonRequest)) {
      return VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'bai hoc',
        topicNumber: topicNumber,
        lessonNumber: lessonNumber ?? 1,
        openLesson: true,
      );
    }
    VoiceNavigationIntent? bestMatch;
    var bestScore = -1;

    for (final rule in _rules) {
      for (final phrase in rule.phrases) {
        if (!_containsPhrase(normalized, phrase)) {
          continue;
        }

        // A short destination name such as "Từ vựng" is a useful command on
        // its own. Longer sentences need an action cue to avoid redirecting a
        // normal question that merely mentions a feature.
        final isShortDirectCommand =
            allowShortDirectCommand &&
            (normalized == phrase ||
                (wordCount <= 4 && normalized.endsWith(phrase)));
        if (!hasCommandCue && !isShortDirectCommand) {
          continue;
        }

        final score = phrase.runes.length + (normalized == phrase ? 100 : 0);
        if (score <= bestScore) {
          continue;
        }
        bestScore = score;
        bestMatch = VoiceNavigationIntent(
          destination: rule.destination,
          recognizedText: recognizedText.trim(),
          matchedPhrase: phrase,
          topicNumber: rule.destination == VoiceNavigationDestination.topics
              ? topicNumber
              : null,
        );
      }
    }

    return bestMatch;
  }

  bool containsWakeWord(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (_wakePhrases.any((phrase) => _containsPhrase(normalized, phrase))) {
      return true;
    }

    // Vietnamese ASR commonly turns the English brand name into variants such
    // as "hay bi co" or "ê pi cô". Only allow fuzzy matching after an
    // explicit wake-like first word so ordinary speech containing "Pico" does
    // not open a page accidentally.
    final words = normalized.split(' ');
    const wakeStarts = <String>{'hey', 'hay', 'hei', 'e'};
    const compactWakePhrases = <String>{'heypico', 'haypico', 'epico'};
    for (var start = 0; start < words.length; start += 1) {
      if (!wakeStarts.contains(words[start])) {
        continue;
      }
      var candidate = '';
      final endLimit = (start + 3).clamp(0, words.length - 1);
      for (var end = start; end <= endLimit; end += 1) {
        candidate += words[end];
        if (compactWakePhrases.any(
          (phrase) => _editDistanceAtMost(candidate, phrase, 1),
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _editDistanceAtMost(String left, String right, int limit) {
    if ((left.length - right.length).abs() > limit) {
      return false;
    }
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex;
      var rowMinimum = current[0];
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
        final substitutionCost =
            left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
            ? 0
            : 1;
        current[rightIndex] = _minimumOfThree(
          current[rightIndex - 1] + 1,
          previous[rightIndex] + 1,
          previous[rightIndex - 1] + substitutionCost,
        );
        if (current[rightIndex] < rowMinimum) {
          rowMinimum = current[rightIndex];
        }
      }
      if (rowMinimum > limit) {
        return false;
      }
      previous = current;
    }
    return previous.last <= limit;
  }

  static int _minimumOfThree(int first, int second, int third) {
    final firstTwo = first < second ? first : second;
    return firstTwo < third ? firstTwo : third;
  }

  static bool _containsPhrase(String value, String phrase) {
    if (phrase.runes.any((rune) => rune > 127)) {
      return value.contains(phrase);
    }
    return ' $value '.contains(' $phrase ');
  }

  static bool _hasCommandCue(String value) {
    if (_commandCues.any((cue) => _containsPhrase(value, cue))) {
      return true;
    }
    return _leadingCommandCues.any(
      (cue) =>
          value == cue ||
          value.startsWith('$cue ') ||
          value.startsWith('con $cue ') ||
          value.startsWith('toi $cue '),
    );
  }

  static bool _hasLessonRequest(String value) {
    if (_containsPhrase(value, 'bai hat')) {
      return false;
    }
    return _containsPhrase(value, 'bai hoc') ||
        _numberAfter(value, 'bai') != null ||
        RegExp(r'(^| )(mo|vao|hoc|luyen|bat dau) bai( |$)').hasMatch(value);
  }

  static int? _numberAfter(String value, String marker) {
    final match = RegExp(
      '(^| )$marker(?: hoc)?(?: so)? '
      r'(\d+|mot|hai|ba|bon|nam|sau|bay|tam|chin|muoi|dau tien)( |$)',
    ).firstMatch(value);
    final token = match?.group(2);
    if (token == null) {
      return null;
    }
    final numeric = int.tryParse(token);
    if (numeric != null) {
      return numeric;
    }
    return const <String, int>{
      'mot': 1,
      'dau tien': 1,
      'hai': 2,
      'ba': 3,
      'bon': 4,
      'nam': 5,
      'sau': 6,
      'bay': 7,
      'tam': 8,
      'chin': 9,
      'muoi': 10,
    }[token];
  }

  static String _normalize(String value) {
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
        .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
