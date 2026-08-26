import '../../../core/device/active_learning_module.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../listening/domain/listening_content.dart';
import '../../vocabulary/data/vocabulary_store.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';
import 'active_learning_command_resolver.dart';
import 'voice_navigation_intent_resolver.dart';

enum MainVoiceAssistantStage {
  idle,
  chooseFeature,
  chooseOtherLearning,
  chooseAlternativeAfterLearning,
  chooseVocabularyCollection,
  activeLearning,
  askAge,
  chooseTopic,
  chooseTopicAfterCompletion,
  confirmReplayTopic,
  chooseLesson,
  confirmReplayLesson,
}

class MainVoiceAssistantUtterance {
  const MainVoiceAssistantUtterance(this.text, {this.locale = 'vi-VN'});

  final String text;
  final String locale;
}

class MainVoiceAssistantTurn {
  const MainVoiceAssistantTurn({
    required this.promptText,
    required this.continueListening,
    this.promptSequence = const <MainVoiceAssistantUtterance>[],
    this.onPromptCompleted,
    this.navigationBeforePrompt,
    this.navigationAfterPrompt,
    this.activeLearningCommand,
  });

  final String promptText;
  final bool continueListening;
  final List<MainVoiceAssistantUtterance> promptSequence;
  final Future<void> Function()? onPromptCompleted;
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
    Future<List<VocabularyEntry>> Function()? vocabularyLoader,
    Future<void> Function(Iterable<String>)? vocabularyIntroducedMarker,
    int? childAge,
  }) : _catalogs = catalogs,
       _contentLoader = contentLoader ?? _loadDefaultContent,
       _vocabularyLoader = vocabularyLoader ?? _loadDefaultVocabulary,
       _vocabularyIntroducedMarker =
           vocabularyIntroducedMarker ?? _markDefaultVocabularyIntroduced,
       _configuredChildAge = childAge;

  static const String openingPrompt =
      'Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?';
  static const String noSpeechRetryPrompt = 'Con muốn làm gì?';
  static const String noSpeechExitPrompt =
      'Khi nào sẵn sàng, con nhấn MAIN gọi mình nhé.';
  static const String otherLearningPrompt =
      'Có chứ. Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?';
  static const String activeLearningPrompt =
      'Con muốn học câu tiếp theo, nghe câu trước, dừng lại hay không học nữa?';
  static const String alternativeAfterLearningPrompt =
      'Con muốn dịch sang tiếng Anh hay học từ vựng?';
  static const ActiveLearningCommandResolver _activeLearningCommandResolver =
      ActiveLearningCommandResolver();

  final List<ListeningAgeCatalog> _catalogs;
  final Future<ListeningContentCatalog> Function() _contentLoader;
  final Future<List<VocabularyEntry>> Function() _vocabularyLoader;
  final Future<void> Function(Iterable<String>) _vocabularyIntroducedMarker;

  int? _configuredChildAge;
  MainVoiceAssistantStage _stage = MainVoiceAssistantStage.idle;
  int? _selectedAge;
  ListeningAgeCatalog? _selectedCatalog;
  int? _selectedTopicNumber;
  ListeningTopicContent? _selectedTopicContent;
  Set<int> _completedTopicNumbers = const <int>{};
  int? _pendingReplayTopicNumber;
  Set<int> _completedLessonNumbers = const <int>{};
  int? _pendingReplayLessonNumber;

  MainVoiceAssistantStage get stage => _stage;

  void setChildAge(int age) {
    if (_configuredChildAge == age) {
      return;
    }
    _configuredChildAge = age;
    reset();
  }

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

  String beginLessonSelectionForTopic({
    required int childAge,
    required int topicNumber,
    required ListeningTopicContent topicContent,
    required List<int> completedLessonNumbers,
  }) {
    reset();
    if (topicContent.lessons.isEmpty) {
      _stage = MainVoiceAssistantStage.chooseFeature;
      return 'Chủ đề này chưa có bài học. Con chọn chủ đề khác nhé.';
    }
    _selectedAge = childAge;
    _selectedCatalog = _catalogForAge(childAge);
    _selectedTopicNumber = topicNumber;
    _selectedTopicContent = topicContent;
    _completedLessonNumbers = completedLessonNumbers
        .where((number) => number >= 1 && number <= topicContent.lessons.length)
        .toSet();
    _stage = MainVoiceAssistantStage.chooseLesson;
    return _lessonSelectionPrompt;
  }

  void reset() {
    _stage = MainVoiceAssistantStage.idle;
    _selectedAge = null;
    _selectedCatalog = null;
    _selectedTopicNumber = null;
    _selectedTopicContent = null;
    _completedTopicNumbers = const <int>{};
    _pendingReplayTopicNumber = null;
    _completedLessonNumbers = const <int>{};
    _pendingReplayLessonNumber = null;
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
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        _isVocabularyChoice(normalized) || _isTranslationChoice(normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        _isReviewVocabularyChoice(normalized) ||
            _isStarVocabularyChoice(normalized),
      MainVoiceAssistantStage.activeLearning =>
        _activeLearningCommandResolver.resolve(normalized) != null ||
            _isLeaveActiveLearningChoice(normalized),
      MainVoiceAssistantStage.confirmReplayTopic =>
        _isAffirmativeChoice(normalized) || _isNegativeChoice(normalized),
      MainVoiceAssistantStage.confirmReplayLesson =>
        _isReplayLessonChoice(normalized) ||
            _isContinueLessonChoice(normalized) ||
            _isAffirmativeChoice(normalized) ||
            _isNegativeChoice(normalized),
      MainVoiceAssistantStage.askAge ||
      MainVoiceAssistantStage.chooseTopic ||
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        _extractSpokenNumber(normalized) != null,
      MainVoiceAssistantStage.chooseLesson =>
        _extractSpokenNumber(normalized) != null ||
            _isContinueLessonChoice(normalized),
      MainVoiceAssistantStage.idle => false,
    };
  }

  Future<MainVoiceAssistantTurn> handle(String recognizedText) async {
    final normalized = _normalize(recognizedText);
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature => await _handleFeature(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseOtherLearning => await _handleOtherLearning(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        await _handleAlternativeAfterLearning(recognizedText, normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        await _handleVocabularyCollection(normalized),
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
      MainVoiceAssistantStage.confirmReplayLesson =>
        _handleReplayLessonConfirmation(recognizedText, normalized),
      MainVoiceAssistantStage.idle => const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      ),
    };
  }

  MainVoiceAssistantTurn _beginConfiguredTopicSelection() {
    final age = _configuredChildAge;
    final catalog = age == null ? null : _catalogForAge(age);
    if (age == null || catalog == null) {
      _stage = MainVoiceAssistantStage.askAge;
      return const MainVoiceAssistantTurn(
        promptText: 'Con mấy tuổi',
        continueListening: true,
      );
    }
    _selectedAge = age;
    _selectedCatalog = catalog;
    _selectedTopicNumber = null;
    _selectedTopicContent = null;
    _stage = MainVoiceAssistantStage.chooseTopic;
    return MainVoiceAssistantTurn(
      promptText:
          'Có ${catalog.topics.length} chủ đề. Con muốn học chủ đề số mấy',
      continueListening: true,
    );
  }

  ListeningAgeCatalog? _catalogForAge(int age) {
    for (final candidate in _catalogs) {
      if (age >= candidate.startAge && age <= candidate.endAge) {
        return candidate;
      }
    }
    return null;
  }

  Future<MainVoiceAssistantTurn> _handleFeature(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      );
    }
    if (_isTopicChoice(normalized)) {
      return _beginConfiguredTopicSelection();
    }
    if (_isVocabularyChoice(normalized)) {
      return _beginVocabularyLearning(
        recognizedText: recognizedText,
        matchedPhrase: 'hoc tu moi',
      );
    }
    if (_isTranslationChoice(normalized) || _isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: openingPrompt,
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _handleOtherLearning(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: otherLearningPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _beginVocabularyLearning(
        recognizedText: recognizedText,
        matchedPhrase: 'hoc tu vung',
      );
    }
    if (_isTopicChoice(normalized)) {
      return _beginConfiguredTopicSelection();
    }
    if (_isTranslationChoice(normalized) || _isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: otherLearningPrompt,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _beginContinuousTranslation(String recognizedText) {
    reset();
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

  Future<MainVoiceAssistantTurn> _handleAlternativeAfterLearning(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: alternativeAfterLearningPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _beginVocabularyLearning(
        recognizedText: recognizedText,
        matchedPhrase: 'hoc tu vung',
      );
    }
    if (_isTranslationChoice(normalized) || _isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: alternativeAfterLearningPrompt,
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _beginVocabularyLearning({
    required String recognizedText,
    required String matchedPhrase,
  }) async {
    final navigation = VoiceNavigationIntent(
      destination: VoiceNavigationDestination.vocabulary,
      recognizedText: recognizedText.trim(),
      matchedPhrase: matchedPhrase,
    );
    final entries = await _loadVocabularyOrNull();
    if (entries == null) {
      reset();
      return MainVoiceAssistantTurn(
        promptText: 'Mình chưa tải được từ vựng. Con thử lại sau nhé.',
        continueListening: false,
        navigationBeforePrompt: navigation,
      );
    }

    final family = _entriesIn(
      entries,
      VocabularyCollection.saved,
    ).where((entry) => entry.introducedAt == null).toList(growable: false);
    if (family.isEmpty) {
      _stage = MainVoiceAssistantStage.chooseVocabularyCollection;
      return MainVoiceAssistantTurn(
        promptText: 'Con muốn luyện lại hay nghe những ngôi sao của con?',
        continueListening: true,
        navigationBeforePrompt: navigation,
      );
    }

    final utterances = <MainVoiceAssistantUtterance>[
      const MainVoiceAssistantUtterance(
        'Ở đây đã có từ mới. Chúng mình cùng học nhé.',
      ),
    ];
    _appendVocabularyEntries(utterances, family);
    utterances.add(
      const MainVoiceAssistantUtterance(
        'Mình qua phần luyện lại và ngôi sao nhé.',
      ),
    );
    _appendVocabularyCollection(
      utterances,
      title: 'Phần luyện lại.',
      emptyPrompt: 'Phần luyện lại chưa có từ nào.',
      entries: _entriesIn(entries, VocabularyCollection.review),
    );
    _appendVocabularyCollection(
      utterances,
      title: 'Phần ngôi sao.',
      emptyPrompt: 'Phần ngôi sao chưa có từ nào.',
      entries: _entriesIn(entries, VocabularyCollection.star),
    );
    utterances.add(
      const MainVoiceAssistantUtterance('Mình đã học xong từ vựng rồi.'),
    );
    reset();
    return MainVoiceAssistantTurn(
      promptText: _plainPrompt(utterances),
      promptSequence: utterances,
      onPromptCompleted: () =>
          _vocabularyIntroducedMarker(family.map((entry) => entry.id)),
      continueListening: false,
      navigationBeforePrompt: navigation,
    );
  }

  Future<MainVoiceAssistantTurn> _handleVocabularyCollection(
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: 'Con muốn luyện lại hay nghe những ngôi sao của con?',
        continueListening: true,
      );
    }
    final collection = _isReviewVocabularyChoice(normalized)
        ? VocabularyCollection.review
        : _isStarVocabularyChoice(normalized)
        ? VocabularyCollection.star
        : null;
    if (collection == null) {
      return const MainVoiceAssistantTurn(
        promptText: 'Con muốn luyện lại hay nghe những ngôi sao của con?',
        continueListening: true,
      );
    }

    final entries = await _loadVocabularyOrNull();
    if (entries == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Mình chưa tải được từ vựng. Con thử lại sau nhé.',
        continueListening: false,
      );
    }
    final selected = _entriesIn(entries, collection);
    final title = collection == VocabularyCollection.review
        ? 'Phần luyện lại.'
        : 'Những ngôi sao của con.';
    final emptyPrompt = collection == VocabularyCollection.review
        ? 'Phần luyện lại chưa có từ nào.'
        : 'Con chưa có từ ngôi sao nào.';
    final utterances = <MainVoiceAssistantUtterance>[];
    _appendVocabularyCollection(
      utterances,
      title: title,
      emptyPrompt: emptyPrompt,
      entries: selected,
    );
    utterances.add(
      const MainVoiceAssistantUtterance('Mình đã học xong từ vựng rồi.'),
    );
    reset();
    return MainVoiceAssistantTurn(
      promptText: _plainPrompt(utterances),
      promptSequence: utterances,
      continueListening: false,
    );
  }

  Future<List<VocabularyEntry>?> _loadVocabularyOrNull() async {
    try {
      return await _vocabularyLoader();
    } catch (_) {
      return null;
    }
  }

  static List<VocabularyEntry> _entriesIn(
    List<VocabularyEntry> entries,
    VocabularyCollection collection,
  ) => entries
      .where(
        (entry) =>
            entry.collection == collection && entry.word.trim().isNotEmpty,
      )
      .toList(growable: false);

  static void _appendVocabularyCollection(
    List<MainVoiceAssistantUtterance> utterances, {
    required String title,
    required String emptyPrompt,
    required List<VocabularyEntry> entries,
  }) {
    if (entries.isEmpty) {
      utterances.add(MainVoiceAssistantUtterance(emptyPrompt));
      return;
    }
    utterances.add(MainVoiceAssistantUtterance(title));
    _appendVocabularyEntries(utterances, entries);
  }

  static void _appendVocabularyEntries(
    List<MainVoiceAssistantUtterance> utterances,
    List<VocabularyEntry> entries,
  ) {
    for (final entry in entries) {
      utterances.add(
        MainVoiceAssistantUtterance(entry.word.trim(), locale: 'en-US'),
      );
      final meaning = entry.meaning.trim();
      if (meaning.isNotEmpty) {
        utterances.add(MainVoiceAssistantUtterance(meaning));
      }
    }
  }

  static String _plainPrompt(List<MainVoiceAssistantUtterance> utterances) =>
      utterances.map((item) => item.text).join(' ');

  MainVoiceAssistantTurn _handleActiveLearning(String normalized) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: activeLearningPrompt,
        continueListening: true,
      );
    }
    if (_isLeaveActiveLearningChoice(normalized)) {
      _stage = MainVoiceAssistantStage.chooseAlternativeAfterLearning;
      return const MainVoiceAssistantTurn(
        promptText: alternativeAfterLearningPrompt,
        continueListening: true,
      );
    }
    final command = _activeLearningCommandResolver.resolve(normalized);
    if (command != null) {
      return _activeLearningTurn(command);
    }
    return const MainVoiceAssistantTurn(
      promptText: activeLearningPrompt,
      continueListening: true,
    );
  }

  static MainVoiceAssistantTurn _activeLearningTurn(
    ActiveLearningCommand command,
  ) {
    final promptText = switch (command) {
      ActiveLearningCommand.resume => 'Cùng học tiếp nhé',
      ActiveLearningCommand.replayCurrent => 'Mình nghe lại câu này nhé',
      ActiveLearningCommand.nextItem => 'Mình học câu tiếp theo nhé',
      ActiveLearningCommand.previousItem => 'Mình nghe lại câu trước nhé',
      ActiveLearningCommand.nextLesson => 'Mình chuyển sang bài tiếp theo nhé',
      ActiveLearningCommand.previousLesson => 'Mình quay lại bài trước nhé',
      ActiveLearningCommand.restart => 'Mình học lại bài này từ đầu nhé',
      ActiveLearningCommand.stop => 'Đã dừng.',
      ActiveLearningCommand.exitToHome => 'Mình kết thúc bài học nhé',
      ActiveLearningCommand.vocabularyPracticeAgain =>
        'Mình cùng luyện lại nhé',
      ActiveLearningCommand.vocabularyStars =>
        'Mình xem lại những ngôi sao của con nhé',
    };
    return MainVoiceAssistantTurn(
      promptText: promptText,
      continueListening: false,
      activeLearningCommand: command,
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

    final catalog = _catalogForAge(age);
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
      return _beginConfiguredTopicSelection();
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
      return _beginConfiguredTopicSelection();
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
      _completedLessonNumbers = const <int>{};
      _pendingReplayLessonNumber = null;
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
      return _beginConfiguredTopicSelection();
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
        promptText: _lessonSelectionPrompt,
        continueListening: true,
      );
    }
    if (age == null || topicNumber == null || topicContent == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Bi cô chưa chọn được chủ đề. Con thử lại nhé',
        continueListening: false,
      );
    }
    if (_isContinueLessonChoice(normalized)) {
      final nextLesson = _nextIncompleteLessonNumber;
      if (nextLesson != null) {
        return _openLessonTurn(
          recognizedText: recognizedText,
          lessonNumber: nextLesson,
        );
      }
      return MainVoiceAssistantTurn(
        promptText:
            'Con đã học xong cả ${topicContent.lessons.length} bài rồi. Con muốn học lại bài số mấy?',
        continueListening: true,
      );
    }
    final lessonNumber = _extractSpokenNumber(normalized);
    if (lessonNumber == null ||
        lessonNumber < 1 ||
        lessonNumber > topicContent.lessons.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${topicContent.lessons.length} bài học. Con hãy chọn bài từ số 1 đến số ${topicContent.lessons.length}',
        continueListening: true,
      );
    }

    if (_completedLessonNumbers.contains(lessonNumber)) {
      _pendingReplayLessonNumber = lessonNumber;
      _stage = MainVoiceAssistantStage.confirmReplayLesson;
      final nextLesson = _nextIncompleteLessonNumber;
      return MainVoiceAssistantTurn(
        promptText: nextLesson == null
            ? 'Bài $lessonNumber con đã học xong rồi. Con có muốn học lại bài $lessonNumber không?'
            : 'Bài $lessonNumber con đã học xong rồi. Con muốn học lại bài $lessonNumber hay tiếp tục bài $nextLesson?',
        continueListening: true,
      );
    }

    return _openLessonTurn(
      recognizedText: recognizedText,
      lessonNumber: lessonNumber,
    );
  }

  MainVoiceAssistantTurn _handleReplayLessonConfirmation(
    String recognizedText,
    String normalized,
  ) {
    final replayLesson = _pendingReplayLessonNumber;
    if (replayLesson == null || _selectedTopicContent == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Bi cô chưa chọn được bài học. Con thử lại nhé.',
        continueListening: false,
      );
    }
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _replayLessonConfirmationPrompt(replayLesson),
        continueListening: true,
      );
    }
    if (_isContinueLessonChoice(normalized) || _isNegativeChoice(normalized)) {
      final nextLesson = _nextIncompleteLessonNumber;
      if (nextLesson != null) {
        _pendingReplayLessonNumber = null;
        return _openLessonTurn(
          recognizedText: recognizedText,
          lessonNumber: nextLesson,
        );
      }
      _stage = MainVoiceAssistantStage.chooseLesson;
      return MainVoiceAssistantTurn(
        promptText:
            'Con đã học xong cả ${_selectedTopicContent!.lessons.length} bài rồi. Con hãy chọn một bài để học lại nhé.',
        continueListening: true,
      );
    }
    if (_isReplayLessonChoice(normalized) || _isAffirmativeChoice(normalized)) {
      _pendingReplayLessonNumber = null;
      return _openLessonTurn(
        recognizedText: recognizedText,
        lessonNumber: replayLesson,
      );
    }
    return MainVoiceAssistantTurn(
      promptText: _replayLessonConfirmationPrompt(replayLesson),
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _openLessonTurn({
    required String recognizedText,
    required int lessonNumber,
  }) {
    final age = _selectedAge;
    final topicNumber = _selectedTopicNumber;
    if (age == null || topicNumber == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'Bi cô chưa chọn được chủ đề. Con thử lại nhé',
        continueListening: false,
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

  String get _lessonSelectionPrompt {
    final topicContent = _selectedTopicContent;
    if (topicContent == null) {
      return 'Con muốn học bài số mấy?';
    }
    final total = topicContent.lessons.length;
    if (_completedLessonNumbers.isEmpty) {
      return 'Chủ đề ${topicContent.titleVi} có $total bài học. Con muốn học bài số mấy?';
    }
    final completed = _completedLessonNumbers.toList()..sort();
    final completedText = completed.join(' và bài ');
    final nextLesson = _nextIncompleteLessonNumber;
    if (nextLesson == null) {
      return 'Chủ đề ${topicContent.titleVi} có $total bài học. Con đã học xong cả $total bài. Con muốn học lại bài số mấy?';
    }
    return 'Chủ đề ${topicContent.titleVi} có $total bài học. Con đã học xong bài $completedText. Con muốn tiếp tục bài $nextLesson hay học lại bài nào?';
  }

  int? get _nextIncompleteLessonNumber {
    final topicContent = _selectedTopicContent;
    if (topicContent == null) {
      return null;
    }
    for (final lesson in topicContent.lessons) {
      if (!_completedLessonNumbers.contains(lesson.number)) {
        return lesson.number;
      }
    }
    return null;
  }

  String _replayLessonConfirmationPrompt(int replayLesson) {
    final nextLesson = _nextIncompleteLessonNumber;
    return nextLesson == null
        ? 'Bài $replayLesson con đã học xong rồi. Con có muốn học lại bài $replayLesson không?'
        : 'Bài $replayLesson con đã học xong rồi. Con muốn học lại bài $replayLesson hay tiếp tục bài $nextLesson?';
  }

  static bool _isSpeakingChoice(String normalized) =>
      _containsPhrase(normalized, 'luyen noi') ||
      _containsPhrase(normalized, 'luyen giao tiep') ||
      _containsPhrase(normalized, 'noi chuyen') ||
      _containsPhrase(normalized, 'dich lien tuc') ||
      _containsPhrase(normalized, 'con muon noi') ||
      normalized == 'noi';

  static bool _isTopicChoice(String normalized) =>
      _containsPhrase(normalized, 'bat dau bai hoc') ||
      _containsPhrase(normalized, 'hoc khoa hoc') ||
      _containsPhrase(normalized, 'hoc theo chu de') ||
      _containsPhrase(normalized, 'hoc chu de') ||
      _containsPhrase(normalized, 'hoc bai') ||
      _containsPhrase(normalized, 'chu de');

  static bool _isVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc tu vung') ||
      _containsPhrase(normalized, 'hoc tu moi') ||
      _containsPhrase(normalized, 'luyen tu') ||
      _containsPhrase(normalized, 'hoc tu') ||
      _containsPhrase(normalized, 'tu vung') ||
      _containsPhrase(normalized, 'tu moi');

  static bool _isReviewVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'luyen lai') ||
      _containsPhrase(normalized, 'on lai') ||
      _containsPhrase(normalized, 'tu chua vung') ||
      _containsPhrase(normalized, 'chua vung');

  static bool _isStarVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'ngoi sao') ||
      _containsPhrase(normalized, 'tu yeu thich') ||
      _containsPhrase(normalized, 'yeu thich');

  static bool _isTranslationChoice(String normalized) =>
      _containsPhrase(normalized, 'dich sang tieng anh') ||
      _containsPhrase(normalized, 'dich tieng anh') ||
      _containsPhrase(normalized, 'dich');

  static bool _isNextSentenceChoice(String normalized) =>
      _containsPhrase(normalized, 'tiep theo') ||
      normalized == 'cau tiep' ||
      _containsPhrase(normalized, 'cau tiep theo') ||
      _containsPhrase(normalized, 'hoc cau tiep') ||
      _containsPhrase(normalized, 'qua cau tiep');

  static bool _isPreviousSentenceChoice(String normalized) =>
      normalized == 'cau truoc' ||
      normalized == 'quay lai' ||
      _containsPhrase(normalized, 'nghe cau truoc') ||
      _containsPhrase(normalized, 'quay lai cau truoc') ||
      _containsPhrase(normalized, 'cau vua roi');

  static bool _isLeaveActiveLearningChoice(String normalized) =>
      normalized == 'khong' ||
      _containsPhrase(normalized, 'khong hoc nua') ||
      _containsPhrase(normalized, 'khong muon hoc') ||
      _containsPhrase(normalized, 'muon hoc cai khac') ||
      _containsPhrase(normalized, 'hoc cai khac') ||
      _containsPhrase(normalized, 'dung hoc');

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

  static bool _isReplayLessonChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc lai') ||
      _containsPhrase(normalized, 'lam lai') ||
      _containsPhrase(normalized, 'nghe lai');

  static bool _isContinueLessonChoice(String normalized) =>
      normalized == 'tiep' ||
      _containsPhrase(normalized, 'tiep tuc') ||
      _containsPhrase(normalized, 'hoc tiep') ||
      _containsPhrase(normalized, 'bai tiep theo');

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
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        _isTranslationChoice(normalized) && _isVocabularyChoice(normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        _isReviewVocabularyChoice(normalized) &&
            _isStarVocabularyChoice(normalized),
      MainVoiceAssistantStage.activeLearning =>
        (_isNextSentenceChoice(normalized) &&
                _isPreviousSentenceChoice(normalized)) ||
            (_isNextSentenceChoice(normalized) &&
                _isLeaveActiveLearningChoice(normalized)) ||
            (_isPreviousSentenceChoice(normalized) &&
                _isLeaveActiveLearningChoice(normalized)),
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
            _containsPhrase(normalized, 'tiep tuc bai') ||
            (_selectedTopicContent != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedTopicContent!.lessons.length} bai hoc',
                )),
      MainVoiceAssistantStage.confirmReplayLesson =>
        _containsPhrase(normalized, 'con da hoc xong roi') ||
            (_containsPhrase(normalized, 'hoc lai bai') &&
                _containsPhrase(normalized, 'hay tiep tuc bai')),
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

  static Future<List<VocabularyEntry>> _loadDefaultVocabulary() =>
      const VocabularyStore().read();

  static Future<void> _markDefaultVocabularyIntroduced(
    Iterable<String> entryIds,
  ) => const VocabularyStore().markIntroduced(entryIds);
}
