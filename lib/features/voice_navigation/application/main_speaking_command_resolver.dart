enum MainSpeakingCommand { stop, otherLearning }

/// Resolves high-priority commands spoken while the automatic speaking
/// practice microphone is open. Unmatched sentences stay in the normal
/// translation pipeline.
class MainSpeakingCommandResolver {
  const MainSpeakingCommandResolver();

  MainSpeakingCommand? resolve(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty) {
      return null;
    }

    if (_stopPhrases.contains(normalized)) {
      return MainSpeakingCommand.stop;
    }

    final asksForSomethingElse =
        _containsPhrase(normalized, 'cai gi khac de hoc') ||
        _containsPhrase(normalized, 'gi khac de hoc') ||
        _containsPhrase(normalized, 'co gi khac khong') ||
        _containsPhrase(normalized, 'hoc cai khac') ||
        _containsPhrase(normalized, 'hoc thu khac') ||
        _containsPhrase(normalized, 'hoc mon khac') ||
        _containsPhrase(normalized, 'hoc bai khac') ||
        _containsPhrase(normalized, 'doi sang hoc khac');
    final wantsToLeaveSpeaking =
        _containsPhrase(normalized, 'khong muon luyen noi nua') ||
        _containsPhrase(normalized, 'dung luyen noi') ||
        _containsPhrase(normalized, 'thoat luyen noi');
    if (asksForSomethingElse || wantsToLeaveSpeaking) {
      return MainSpeakingCommand.otherLearning;
    }
    return null;
  }

  static const Set<String> _stopPhrases = <String>{
    'dung',
    'dung lai',
    'con muon dung',
    'con muon dung lai',
    'dung dich',
    'dung dich lai',
    'dung dich lien tuc',
    'ngung',
    'ngung lai',
    'con muon ngung',
    'con muon ngung lai',
    'ngung dich',
    'thoi dung lai',
    'thoi con dung lai',
    'khong dich nua',
    'con khong dich nua',
    'con khong muon dich nua',
    'thoat dich',
  };

  static bool _containsPhrase(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

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
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
