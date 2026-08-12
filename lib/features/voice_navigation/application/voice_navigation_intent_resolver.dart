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
  });

  final VoiceNavigationDestination destination;
  final String recognizedText;
  final String matchedPhrase;
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
        'hoc theo chu de',
        'hoc chu de',
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
        );
      }
    }

    return bestMatch;
  }

  bool containsWakeWord(String recognizedText) {
    final normalized = _normalize(recognizedText);
    return _wakePhrases.any((phrase) => _containsPhrase(normalized, phrase));
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
