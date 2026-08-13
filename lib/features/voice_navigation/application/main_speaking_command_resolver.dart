enum MainSpeakingCommand { otherLearning }

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
