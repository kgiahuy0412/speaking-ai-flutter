import '../domain/homi_fallback_catalog.dart';

enum MainSpeakingCommand { otherLearning, stopTranslation, help }

/// Resolves high-priority commands spoken while the automatic speaking
/// practice microphone is open. Unmatched sentences stay in the normal
/// translation pipeline.
class MainSpeakingCommandResolver {
  const MainSpeakingCommandResolver();

  // Keep the established child-addressed variants as well as the new workbook
  // wording, since older installed audio prompts use "con" rather than
  // "mình".
  static const Set<String> _legacyOtherLearningPhrases = <String>{
    'cai gi khac de hoc',
    'gi khac de hoc',
    'co gi khac khong',
    'hoc cai khac',
    'hoc thu khac',
    'hoc mon khac',
    'hoc bai khac',
    'doi sang hoc khac',
    'con cai gi khac de hoc khong',
    'con muon hoc cai khac',
    'con muon hoc thu khac',
    'con muon hoc mon khac',
    'con muon hoc bai khac',
    'cho con hoc cai khac',
    'cho con hoc thu khac',
    'cho con hoc mon khac',
    'cho con hoc bai khac',
    'con doi sang hoc khac',
  };

  MainSpeakingCommand? resolve(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty) {
      return null;
    }

    if (_matchesIntent(normalized, 'INT-017') ||
        _legacyOtherLearningPhrases.contains(normalized)) {
      return MainSpeakingCommand.otherLearning;
    }
    // INT-001 is global in the approved catalog.  It is deliberately applied
    // here only while the continuous-translation session is active (the app
    // owns that state guard), so a normal one-shot translation is not
    // swallowed by a generic word such as "thôi".
    if (_matchesIntent(normalized, 'INT-018') ||
        _matchesIntent(normalized, 'INT-001')) {
      return MainSpeakingCommand.stopTranslation;
    }
    if (_matchesIntent(normalized, 'INT-016')) {
      return MainSpeakingCommand.help;
    }
    return null;
  }

  /// This resolver runs only during continuous translation. A whole approved
  /// utterance is required to avoid treating a sentence to translate as a
  /// command. Legacy child-addressed variants are listed in their full form.
  static bool _matchesIntent(String normalized, String intentId) {
    final phrases = HomiFallbackCatalog.childPhrasesByIntent[intentId];
    return phrases != null &&
        phrases.any(
          (phrase) =>
              normalized == HomiFallbackCatalog.normalizeVietnamese(phrase),
        );
  }

  static String _normalize(String value) =>
      HomiFallbackCatalog.normalizeVietnamese(value);
}
