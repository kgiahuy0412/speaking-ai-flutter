import '../../../core/device/active_learning_module.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../listening/domain/listening_content.dart';
import 'voice_navigation_intent_resolver.dart';

enum MainVoiceAssistantStage {
  idle,
  chooseFeature,
  chooseOtherLearning,
  chooseTranslationMode,
  activeLearning,
  askAge,
  chooseTopic,
  chooseTopicAfterCompletion,
  confirmReplayTopic,
  chooseLesson,
}

class MainVoiceAssistantTurn {
  const MainVoiceAssistantTurn({
    required this.promptText,
    required this.continueListening,
    this.navigationBeforePrompt,
    this.navigationAfterPrompt,
    this.activeLearningCommand,
  });

  final String promptText;
  final bool continueListening;
  final VoiceNavigationIntent? navigationBeforePrompt;
  final VoiceNavigationIntent? navigationAfterPrompt;
  final ActiveLearningCommand? activeLearningCommand;
}

/// Holds the multi-turn conversation started from the fixed Main button.
///
/// Topic and lesson counts are read from the same catalogs used by the UI, so
/// the spoken questions stay correct when learning content changes.
class MainVoiceAssistantFlow {
  MainVoiceAssistantFlow({
    List<ListeningAgeCatalog> catalogs = listeningCatalogs,
    Future<ListeningContentCatalog> Function()? contentLoader,
  }) : _catalogs = catalogs,
       _contentLoader = contentLoader ?? _loadDefaultContent;

  static const String openingPrompt =
      'Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?';
  static const String otherLearningPrompt =
      'Có chứ. Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?';
  static const String activeLearningPrompt = 'Con có muốn học nữa không?';

  final List<ListeningAgeCatalog> _catalogs;
  final Future<ListeningContentCatalog> Function() _contentLoader;

  MainVoiceAssistantStage _stage = MainVoiceAssistantStage.idle;
  int? _selectedAge;
  ListeningAgeCatalog? _selectedCatalog;
  int? _selectedTopicNumber;
  ListeningTopicContent? _selectedTopicContent;
  Set<int> _completedTopicNumbers = const <int>{};
  int? _pendingReplayTopicNumber;

  MainVoiceAssistantStage get stage => _stage;

  String begin() {
    reset();
    _stage = MainVoiceAssistantStage.chooseFeature;
    return openingPrompt;
  }

  String beginOtherLearning() {
    reset();
    _stage = MainVoiceAssistantStage.chooseOtherLearning;
    return otherLearningPrompt;
  }

  String beginActiveLearning() {
    reset();
    _stage = MainVoiceAssistantStage.activeLearning;
    return activeLearningPrompt;
  }

  String beginTopicSelectionAfterCompletion({
    required int childAge,
    required List<int> completedTopicNumbers,
  }) {
    reset();
    ListeningAgeCatalog? catalog;
    for (final candidate in _catalogs) {
      if (childAge >= candidate.startAge && childAge <= candidate.endAge) {
        catalog = candidate;
        break;
      }
    }
    if (catalog == null) {
      _stage = MainVoiceAssistantStage.chooseFeature;
      return openingPrompt;
    }

    final validCompletedTopicNumbers = completedTopicNumbers
        .where(
          (topicNumber) =>
              topicNumber >= 1 && topicNumber <= catalog!.topics.length,
        )
        .toSet();

    _selectedAge = childAge;
    _selectedCatalog = catalog;
    _completedTopicNumbers = validCompletedTopicNumbers;
    _stage = MainVoiceAssistantStage.chooseTopicAfterCompletion;
    return _topicSelectionPrompt;
  }

  void reset() {
    _stage = MainVoiceAssistantStage.idle;
    _selectedAge = null;
    _selectedCatalog = null;
    _selectedTopicNumber = null;
    _selectedTopicContent = null;
    _completedTopicNumbers = const <int>{};
    _pendingReplayTopicNumber = null;
  }

  bool canHandle(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty || _looksLikePromptEcho(normalized)) {
      return false;
    }
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature =>
        _isSpeakingChoice(normalized) ||
            _isTopicChoice(normalized) ||
            _isVocabularyChoice(normalized) ||
            _isTranslationChoice(normalized),
      MainVoiceAssistantStage.chooseOtherLearning =>
        _isTopicChoice(normalized) ||
            _isVocabularyChoice(normalized) ||
            _isTranslationChoice(normalized),
      MainVoiceAssistantStage.chooseTranslationMode =>
        _isSingleSentenceChoice(normalized) || _isContinuousChoice(normalized),
      MainVoiceAssistantStage.activeLearning =>
        _isAffirmativeChoice(normalized) || _isNegativeChoice(normalized),
      MainVoiceAssistantStage.confirmReplayTopic =>
        _isAffirmativeChoice(normalized) || _isNegativeChoice(normalized),
      MainVoiceAssistantStage.askAge ||
      MainVoiceAssistantStage.chooseTopic ||
      MainVoiceAssistantStage.chooseTopicAfterCompletion ||
      MainVoiceAssistantStage.chooseLesson =>
        _extractSpokenNumber(normalized) != null,
      MainVoiceAssistantStage.idle => false,
    };
  }

  Future<MainVoiceAssistantTurn> handle(String recognizedText) async {
    final normalized = _normalize(recognizedText);
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature => _handleFeature(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseOtherLearning => _handleOtherLearning(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseTranslationMode => _handleTranslationMode(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.activeLearning => _handleActiveLearning(
        normalized,
      ),
      MainVoiceAssistantStage.askAge => _handleAge(normalized),
      MainVoiceAssistantStage.chooseTopic => await _handleTopic(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        await _handleTopicAfterCompletion(recognizedText, normalized),
      MainVoiceAssistantStage.confirmReplayTopic =>
        await _handleReplayTopicConfirmation(recognizedText, normalized),
      MainVoiceAssistantStage.chooseLesson => _handleLesson(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.idle => const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      ),
    };
  }

  MainVoiceAssistantTurn _handleFeature(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      );
    }
    if (_isTopicChoice(normalized)) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: 'Mình cùng học từ mới nhé',
        continueListening: false,
        navigationAfterPrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.vocabulary,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'hoc tu moi',
        ),
      );
    }
    if (_isTranslationChoice(normalized) || _isSpeakingChoice(normalized)) {
      _stage = MainVoiceAssistantStage.chooseTranslationMode;
      return const MainVoiceAssistantTurn(
        promptText: 'Con muốn dịch một câu hay dịch liên tục?',
        continueListening: true,
      );
    }
    return const MainVoiceAssistantTurn(
      promptText: openingPrompt,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _handleOtherLearning(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: otherLearningPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: 'Mình cùng học từ vựng nhé',
        continueListening: false,
        navigationAfterPrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.vocabulary,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'hoc tu vung',
        ),
      );
    }
    if (_isTopicChoice(normalized)) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    if (_isTranslationChoice(normalized) || _isSpeakingChoice(normalized)) {
      _stage = MainVoiceAssistantStage.chooseTranslationMode;
      return const MainVoiceAssistantTurn(
        promptText: 'Con muốn dịch một câu hay dịch liên tục?',
        continueListening: true,
      );
    }
    return const MainVoiceAssistantTurn(
      promptText: otherLearningPrompt,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _handleTranslationMode(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: 'Con muốn dịch một câu hay dịch liên tục?',
        continueListening: true,
      );
    }
    if (_isSingleSentenceChoice(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: 'Con hãy nói một câu.',
        continueListening: false,
        navigationAfterPrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.conversation,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'mot cau',
          enterMainSpeakingMode: false,
        ),
      );
    }
    if (_isContinuousChoice(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: 'Con nói từng câu nhé. Muốn dừng thì nói dừng lại.',
        continueListening: false,
        navigationAfterPrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.conversation,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'lien tuc',
          enterMainSpeakingMode: true,
        ),
      );
    }
    return const MainVoiceAssistantTurn(
      promptText: 'Con muốn dịch một câu hay dịch liên tục?',
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _handleActiveLearning(String normalized) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: activeLearningPrompt,
        continueListening: true,
      );
    }
    if (_isAffirmativeChoice(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: 'Tiếp tục học nhé con',
        continueListening: false,
        activeLearningCommand: ActiveLearningCommand.resume,
      );
    }
    if (_isNegativeChoice(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: 'Tạm biệt con',
        continueListening: false,
        activeLearningCommand: ActiveLearningCommand.exitToHome,
      );
    }
    return const MainVoiceAssistantTurn(
      promptText: 'Con có muốn học nữa không? Con hãy nói có hoặc không nhé.',
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _handleAge(String normalized) {
    final age = _extractSpokenNumber(normalized);
    if (age == null) {
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi? Con hãy nói, ví dụ con 6 tuổi',
        continueListening: true,
      );
    }

    ListeningAgeCatalog? catalog;
    for (final candidate in _catalogs) {
      if (age >= candidate.startAge && age <= candidate.endAge) {
        catalog = candidate;
        break;
      }
    }
    if (catalog == null) {
      final minimumAge = _catalogs.isEmpty ? 0 : _catalogs.first.startAge;
      final maximumAge = _catalogs.isEmpty ? 0 : _catalogs.last.endAge;
      return MainVoiceAssistantTurn(
        promptText:
            'Bi cô có bài học cho các bạn từ $minimumAge đến $maximumAge tuổi. Con mấy tuổi',
        continueListening: true,
      );
    }

    _selectedAge = age;
    _selectedCatalog = catalog;
    _stage = MainVoiceAssistantStage.chooseTopic;
    return MainVoiceAssistantTurn(
      promptText:
          'Có ${catalog.topics.length} chủ đề. Con muốn học chủ đề số mấy',
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _handleTopic(
    String recognizedText,
    String normalized,
  ) async {
    final catalog = _selectedCatalog;
    final age = _selectedAge;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog?.topics.length ?? 0} chủ đề. Con muốn học chủ đề số mấy',
        continueListening: true,
      );
    }
    final topicNumber = _extractSpokenNumber(normalized);
    if (catalog == null || age == null) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    if (topicNumber == null ||
        topicNumber < 1 ||
        topicNumber > catalog.topics.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog.topics.length} chủ đề. Con hãy chọn chủ đề từ số 1 đến số ${catalog.topics.length}',
        continueListening: true,
      );
    }
    return _openTopic(recognizedText: recognizedText, topicNumber: topicNumber);
  }

  Future<MainVoiceAssistantTurn> _openTopic({
    required String recognizedText,
    required int topicNumber,
  }) async {
    final catalog = _selectedCatalog;
    final age = _selectedAge;
    if (catalog == null || age == null) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    try {
      final content = await _contentLoader();
      final topicContent = content.topic(
        startAge: catalog.startAge,
        endAge: catalog.endAge,
        topicNumber: topicNumber,
      );
      if (topicContent.lessons.isEmpty) {
        reset();
        return const MainVoiceAssistantTurn(
          promptText: 'Chủ đề này chưa có bài học. Con thử lại sau nhé',
          continueListening: false,
        );
      }
      _selectedTopicNumber = topicNumber;
      _selectedTopicContent = topicContent;
      _stage = MainVoiceAssistantStage.chooseLesson;
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${topicContent.lessons.length} bài học. Con muốn học bài số mấy',
        continueListening: true,
        navigationBeforePrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.topics,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'chu de so $topicNumber',
          topicNumber: topicNumber,
          childAge: age,
        ),
      );
    } catch (_) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Bi cô chưa tải được bài học. Con thử lại sau nhé',
        continueListening: false,
      );
    }
  }

  Future<MainVoiceAssistantTurn> _handleTopicAfterCompletion(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _topicSelectionPrompt,
        continueListening: true,
      );
    }
    final catalog = _selectedCatalog;
    final topicNumber = _extractSpokenNumber(normalized);
    if (catalog == null || _selectedAge == null) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    if (topicNumber == null ||
        topicNumber < 1 ||
        topicNumber > catalog.topics.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog.topics.length} chủ đề. Con hãy chọn chủ đề từ số 1 đến số ${catalog.topics.length}',
        continueListening: true,
      );
    }
    if (_completedTopicNumbers.contains(topicNumber)) {
      _pendingReplayTopicNumber = topicNumber;
      _stage = MainVoiceAssistantStage.confirmReplayTopic;
      return MainVoiceAssistantTurn(
        promptText:
            'Chủ đề số $topicNumber con đã học rồi. Con có muốn học lại không?',
        continueListening: true,
      );
    }
    return _openTopic(recognizedText: recognizedText, topicNumber: topicNumber);
  }

  Future<MainVoiceAssistantTurn> _handleReplayTopicConfirmation(
    String recognizedText,
    String normalized,
  ) async {
    final topicNumber = _pendingReplayTopicNumber;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Chủ đề số ${topicNumber ?? ''} con đã học rồi. Con có muốn học lại không?',
        continueListening: true,
      );
    }
    if (_isAffirmativeChoice(normalized) && topicNumber != null) {
      _pendingReplayTopicNumber = null;
      return _openTopic(
        recognizedText: recognizedText,
        topicNumber: topicNumber,
      );
    }
    if (_isNegativeChoice(normalized)) {
      _pendingReplayTopicNumber = null;
      _stage = MainVoiceAssistantStage.chooseTopicAfterCompletion;
      return MainVoiceAssistantTurn(
        promptText: _topicSelectionPrompt,
        continueListening: true,
      );
    }
    return MainVoiceAssistantTurn(
      promptText:
          'Con có muốn học lại chủ đề số ${topicNumber ?? ''} không? Con hãy nói có hoặc không nhé',
      continueListening: true,
    );
  }

  String get _topicSelectionPrompt =>
      'Có ${_selectedCatalog?.topics.length ?? 0} chủ đề. Con muốn học chủ đề số mấy';

  MainVoiceAssistantTurn _handleLesson(
    String recognizedText,
    String normalized,
  ) {
    final age = _selectedAge;
    final topicNumber = _selectedTopicNumber;
    final topicContent = _selectedTopicContent;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${topicContent?.lessons.length ?? 0} bài học. Con muốn học bài số mấy',
        continueListening: true,
      );
    }
    final lessonNumber = _extractSpokenNumber(normalized);
    if (age == null || topicNumber == null || topicContent == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Bi cô chưa chọn được chủ đề. Con thử lại nhé',
        continueListening: false,
      );
    }
    if (lessonNumber == null ||
        lessonNumber < 1 ||
        lessonNumber > topicContent.lessons.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${topicContent.lessons.length} bài học. Con hãy chọn bài từ số 1 đến số ${topicContent.lessons.length}',
        continueListening: true,
      );
    }

    return MainVoiceAssistantTurn(
      promptText: 'Bắt đầu học thôi con',
      continueListening: false,
      navigationAfterPrompt: VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'bai so $lessonNumber',
        topicNumber: topicNumber,
        lessonNumber: lessonNumber,
        childAge: age,
        openLesson: true,
      ),
    );
  }

  static bool _isSpeakingChoice(String normalized) =>
      _containsPhrase(normalized, 'luyen noi') ||
      _containsPhrase(normalized, 'luyen giao tiep') ||
      _containsPhrase(normalized, 'noi chuyen');

  static bool _isTopicChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc chu de') ||
      _containsPhrase(normalized, 'hoc theo chu de') ||
      _containsPhrase(normalized, 'chu de');

  static bool _isVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc tu vung') ||
      _containsPhrase(normalized, 'hoc tu moi') ||
      _containsPhrase(normalized, 'tu vung') ||
      _containsPhrase(normalized, 'tu moi');

  static bool _isTranslationChoice(String normalized) =>
      _containsPhrase(normalized, 'dich sang tieng anh') ||
      _containsPhrase(normalized, 'dich tieng anh') ||
      _containsPhrase(normalized, 'dich');

  static bool _isSingleSentenceChoice(String normalized) =>
      _containsPhrase(normalized, 'mot cau') ||
      _containsPhrase(normalized, 'dich mot cau');

  static bool _isContinuousChoice(String normalized) =>
      _containsPhrase(normalized, 'lien tuc') ||
      _containsPhrase(normalized, 'dich lien tuc') ||
      _containsPhrase(normalized, 'noi lien tuc');

  static bool _isAffirmativeChoice(String normalized) =>
      normalized == 'co' ||
      normalized == 'co a' ||
      normalized == 'da co' ||
      _containsPhrase(normalized, 'con co') ||
      _containsPhrase(normalized, 'muon hoc lai') ||
      _containsPhrase(normalized, 'hoc lai') ||
      _containsPhrase(normalized, 'tiep tuc') ||
      _containsPhrase(normalized, 'hoc tiep');

  static bool _isNegativeChoice(String normalized) =>
      normalized == 'khong' ||
      normalized == 'khong a' ||
      normalized == 'da khong' ||
      _containsPhrase(normalized, 'con khong') ||
      _containsPhrase(normalized, 'khong dau') ||
      _containsPhrase(normalized, 'khong muon') ||
      _containsPhrase(normalized, 'khong hoc') ||
      _containsPhrase(normalized, 'dung hoc');

  static bool _containsPhrase(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

  bool _looksLikePromptEcho(String normalized) {
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature =>
        (_isSpeakingChoice(normalized) && _isTopicChoice(normalized)) ||
            _containsPhrase(normalized, 'hay hoc chu de ne') ||
            normalized == 'hoc chu de ne',
      MainVoiceAssistantStage.chooseOtherLearning =>
        (_isTopicChoice(normalized) && _isVocabularyChoice(normalized)) ||
            _containsPhrase(normalized, 'hay hoc tu vung ne') ||
            normalized == 'hoc tu vung ne',
      MainVoiceAssistantStage.chooseTranslationMode =>
        (_isSingleSentenceChoice(normalized) &&
                _isContinuousChoice(normalized)) ||
            _containsPhrase(normalized, 'mot cau hay dich lien tuc'),
      MainVoiceAssistantStage.activeLearning => _containsPhrase(
        normalized,
        'con co muon hoc nua khong',
      ),
      MainVoiceAssistantStage.askAge => normalized == 'con may tuoi',
      MainVoiceAssistantStage.chooseTopic =>
        _containsPhrase(normalized, 'chu de so may') ||
            (_selectedCatalog != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedCatalog!.topics.length} chu de',
                )),
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        _containsPhrase(normalized, 'con muon hoc chu de so may') ||
            _containsPhrase(normalized, 'chu de so may') ||
            (_selectedCatalog != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedCatalog!.topics.length} chu de',
                )),
      MainVoiceAssistantStage.confirmReplayTopic =>
        _containsPhrase(normalized, 'con da hoc roi') ||
            _containsPhrase(normalized, 'co muon hoc lai khong'),
      MainVoiceAssistantStage.chooseLesson =>
        _containsPhrase(normalized, 'bai so may') ||
            (_selectedTopicContent != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedTopicContent!.lessons.length} bai hoc',
                )),
      MainVoiceAssistantStage.idle => false,
    };
  }

  static int? _extractSpokenNumber(String normalized) {
    final digitMatch = RegExp(r'(^| )(\d{1,2})( |$)').firstMatch(normalized);
    final numeric = int.tryParse(digitMatch?.group(2) ?? '');
    if (numeric != null) {
      return numeric;
    }

    const values = <String, int>{
      'muoi lam': 15,
      'muoi bon': 14,
      'muoi tu': 14,
      'muoi ba': 13,
      'muoi hai': 12,
      'muoi mot': 11,
      'muoi': 10,
      'chin': 9,
      'tam': 8,
      'bay': 7,
      'sau': 6,
      'nam': 5,
      'lam': 5,
      'bon': 4,
      'tu': 4,
      'ba': 3,
      'hai': 2,
      'mot': 1,
      'dau tien': 1,
    };
    for (final entry in values.entries) {
      if (_containsPhrase(normalized, entry.key)) {
        return entry.value;
      }
    }
    return null;
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
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<ListeningContentCatalog> _loadDefaultContent() =>
      AssetListeningContentRepository().load();
}
