import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fast path accepts unambiguous fallback phrases but defers broad input',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();

      expect(flow.canHandlePartial('Con muốn học từ vựng'), isTrue);
      expect(flow.canHandlePartial('Học theo chủ đề'), isTrue);
      expect(flow.canHandlePartial('Mình muốn học'), isFalse);
      expect(flow.canHandlePartial('Dừng lại'), isTrue);

      await flow.handle('Học theo chủ đề');
      expect(flow.stage, MainVoiceAssistantStage.askAge);
      expect(flow.canHandlePartial('Con 6 tuổi'), isFalse);
    },
  );

  test('chooses continuous translation after the Main menu', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(flow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final turn = await flow.handle('Con muốn luyện nói');

    expect(turn.promptText, MainVoiceAssistantFlow.continuousTranslationPrompt);
    expect(turn.continueListening, isFalse);
    expect(
      turn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
  });

  test('accepts short child-friendly continuous speaking choices', () async {
    for (final choice in <String>['Nói', 'Con muốn nói']) {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.begin();

      final turn = await flow.handle(choice);

      expect(
        turn.navigationAfterPrompt?.destination,
        VoiceNavigationDestination.conversation,
        reason: choice,
      );
      expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
    }
  });

  test('uses the approved two-step translation-mode state', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.begin();

    final chooseTranslation = await flow.handle('Dịch sang tiếng Anh');
    expect(chooseTranslation.continueListening, isTrue);
    expect(
      chooseTranslation.promptText,
      MainVoiceAssistantFlow.translationModePrompt,
    );
    expect(flow.stage, MainVoiceAssistantStage.chooseTranslationMode);

    final continuous = await flow.handle('Dịch liên tục');
    expect(
      continuous.promptText,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    );
    expect(continuous.continueListening, isFalse);
    expect(continuous.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test('offers all three top-level choices from Main', () async {
    final introducedIds = <String>[];
    final vocabularyFlow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: _loadVocabularyAcrossCollections,
      vocabularyIntroducedMarker: (ids) async => introducedIds.addAll(ids),
    );
    expect(vocabularyFlow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final vocabulary = await vocabularyFlow.handle('Học từ mới');
    expect(
      vocabulary.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );
    expect(vocabulary.continueListening, isFalse);
    expect(
      vocabulary.promptSequence.map((item) => item.text),
      containsAllInOrder(<String>[
        'Ở đây đã có từ mới. Chúng mình cùng học nhé.',
        'Apple',
        'Quả táo',
        'Mình qua phần luyện lại và ngôi sao nhé.',
        'Phần luyện lại.',
        'Open your book',
        'Mở sách ra',
        'Phần ngôi sao.',
        'Good morning',
        'Chào buổi sáng',
      ]),
    );
    expect(
      vocabulary.promptSequence
          .firstWhere((item) => item.text == 'Apple')
          .locale,
      'en-US',
    );
    expect(introducedIds, isEmpty);
    await vocabulary.onPromptCompleted?.call();
    expect(introducedIds, <String>['parent-apple']);

    final translationFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    translationFlow.begin();
    final chooseTranslation = await translationFlow.handle(
      'Dịch sang tiếng Anh',
    );
    expect(chooseTranslation.continueListening, isTrue);
    expect(
      chooseTranslation.promptText,
      MainVoiceAssistantFlow.translationModePrompt,
    );
    final translation = await translationFlow.handle('Dịch liên tục');
    expect(translation.continueListening, isFalse);
    expect(
      translation.promptText,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    );
    expect(
      translation.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(translation.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
  });

  test('already introduced Family words follow the no-new branch', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: () async => <VocabularyEntry>[
        VocabularyEntry(
          id: 'parent-apple',
          word: 'Apple',
          meaning: 'Quả táo',
          addedAt: DateTime(2026, 8, 18),
          introducedAt: DateTime(2026, 8, 18, 9),
        ),
      ],
    );
    flow.begin();

    final turn = await flow.handle('Học từ mới');

    expect(
      turn.promptText,
      'Con muốn luyện lại hay nghe những ngôi sao của con?',
    );
    expect(turn.continueListening, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.chooseVocabularyCollection);
  });

  test('accepts every D04 topic-learning synonym from Main', () async {
    for (final command in <String>[
      'Học bài',
      'Học theo chủ đề',
      'Học khóa học',
      'Bắt đầu bài học',
    ]) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.begin();

      final turn = await flow.handle(command);

      expect(turn.promptText, 'Con mấy tuổi', reason: command);
      expect(turn.continueListening, isTrue, reason: command);
      expect(flow.stage, MainVoiceAssistantStage.askAge, reason: command);
    }
  });

  test('accepts every D05 vocabulary-learning synonym from Main', () async {
    for (final command in <String>['Học từ mới', 'Học từ', 'Luyện từ']) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.begin();

      final turn = await flow.handle(command);

      expect(
        turn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.vocabulary,
        reason: command,
      );
      expect(turn.continueListening, isTrue, reason: command);
      expect(
        turn.promptText,
        'Con muốn luyện lại hay nghe những ngôi sao của con?',
        reason: command,
      );
      expect(
        flow.stage,
        MainVoiceAssistantStage.chooseVocabularyCollection,
        reason: command,
      );
    }
  });

  test('without new family words the child chooses Review or Stars', () async {
    for (final choice in <String, String>{
      'Luyện lại': 'Open your book',
      'Ngôi sao của con': 'Good morning',
    }.entries) {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadReviewAndStarsVocabulary,
      );
      flow.begin();

      final menu = await flow.handle('Học từ mới');
      expect(menu.continueListening, isTrue);
      expect(flow.canHandle(choice.key), isTrue);

      final selected = await flow.handle(choice.key);

      expect(selected.continueListening, isFalse);
      expect(
        selected.promptSequence.map((item) => item.text),
        contains(choice.value),
      );
      expect(flow.stage, MainVoiceAssistantStage.idle);
    }
  });

  test('moves to the next sentence in an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    expect(
      flow.beginActiveLearning(),
      MainVoiceAssistantFlow.activeLearningPrompt,
    );
    expect(flow.canHandle('Câu tiếp theo'), isTrue);

    final turn = await flow.handle('Câu tiếp theo');
    expect(turn.promptText, 'Mình học câu tiếp theo nhé');
    expect(turn.activeLearningCommand, ActiveLearningCommand.nextItem);
    expect(turn.continueListening, isFalse);
  });

  test('active lesson prompt offers pause and leaving the lesson', () {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(
      flow.beginActiveLearning(),
      MainVoiceAssistantFlow.activeLearningPrompt,
    );
  });

  test('accepts a natural phrase containing next', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();

    expect(flow.canHandle('Con muốn tiếp theo'), isTrue);
    final turn = await flow.handle('Con muốn tiếp theo');

    expect(turn.activeLearningCommand, ActiveLearningCommand.nextItem);
  });

  test('moves to the previous sentence in an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();
    expect(flow.canHandle('Nghe câu trước'), isTrue);

    final turn = await flow.handle('Nghe câu trước');
    expect(turn.promptText, 'Mình nghe lại câu trước nhé');
    expect(turn.activeLearningCommand, ActiveLearningCommand.previousItem);
    expect(turn.continueListening, isFalse);
  });

  test('maps every D07 and D08 command to the active lesson module', () async {
    const cases = <String, ActiveLearningCommand>{
      'Câu tiếp theo': ActiveLearningCommand.nextItem,
      'Câu trước': ActiveLearningCommand.previousItem,
      'Nghe lại': ActiveLearningCommand.replayCurrent,
      'Học lại từ đầu': ActiveLearningCommand.restart,
      'Bài tiếp theo': ActiveLearningCommand.nextLesson,
      'Bài trước': ActiveLearningCommand.previousLesson,
    };

    for (final entry in cases.entries) {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginActiveLearning();

      expect(flow.canHandle(entry.key), isTrue, reason: entry.key);
      final turn = await flow.handle(entry.key);

      expect(turn.activeLearningCommand, entry.value, reason: entry.key);
      expect(turn.continueListening, isFalse, reason: entry.key);
    }
  });

  test(
    'routes the workbook phrase Học bài khác to the next lesson in an active course',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginActiveLearning(kind: ActiveLearningModuleKind.listeningLesson);

      final turn = await flow.handle('Học bài khác');

      expect(turn.activeLearningCommand, ActiveLearningCommand.nextLesson);
      expect(turn.promptText, 'Mình chuyển sang bài tiếp theo nhé');
      expect(turn.continueListening, isFalse);
    },
  );

  test(
    'offers translation or vocabulary after leaving an active lesson',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        vocabularyLoader: _loadEmptyVocabulary,
      );
      flow.beginActiveLearning();

      final leaveTurn = await flow.handle('Con muốn học cái khác');
      expect(
        leaveTurn.promptText,
        MainVoiceAssistantFlow.alternativeAfterLearningPrompt,
      );
      expect(leaveTurn.continueListening, isTrue);
      expect(
        flow.stage,
        MainVoiceAssistantStage.chooseAlternativeAfterLearning,
      );

      final vocabularyTurn = await flow.handle('Con muốn học từ vựng');
      expect(
        vocabularyTurn.promptText,
        'Con muốn luyện lại hay nghe những ngôi sao của con?',
      );
      expect(vocabularyTurn.continueListening, isTrue);
      expect(
        vocabularyTurn.navigationBeforePrompt?.destination,
        VoiceNavigationDestination.vocabulary,
      );
    },
  );

  test('can choose translation after leaving an active lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();
    await flow.handle('Con không muốn học nữa');

    final chooseTranslation = await flow.handle('Dịch sang tiếng Anh');
    expect(chooseTranslation.continueListening, isTrue);
    expect(flow.stage, MainVoiceAssistantStage.chooseTranslationMode);

    final translationTurn = await flow.handle('Dịch liên tục');
    expect(
      translationTurn.promptText,
      MainVoiceAssistantFlow.continuousTranslationPrompt,
    );
    expect(translationTurn.continueListening, isFalse);
    expect(
      translationTurn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(
      translationTurn.navigationAfterPrompt?.enterMainSpeakingMode,
      isTrue,
    );
    expect(flow.stage, MainVoiceAssistantStage.idle);
  });

  test('selects age, topic 3 and lesson 1 across multiple turns', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    flow.begin();
    final featureTurn = await flow.handle('Con muốn học theo chủ đề');
    expect(featureTurn.promptText, 'Con mấy tuổi');
    expect(flow.stage, MainVoiceAssistantStage.askAge);

    final ageTurn = await flow.handle('Con 6 tuổi');
    expect(ageTurn.promptText, 'Có 10 chủ đề. Con muốn học chủ đề số mấy');
    expect(flow.stage, MainVoiceAssistantStage.chooseTopic);

    final topicTurn = await flow.handle('Con muốn học chủ đề số 3');
    expect(listeningCatalogs[1].topics[2].titleVi, 'Động vật thú vị');
    expect(topicTurn.promptText, 'Có 2 bài học. Con muốn học bài số mấy');
    expect(topicTurn.navigationBeforePrompt?.childAge, 6);
    expect(topicTurn.navigationBeforePrompt?.topicNumber, 3);
    expect(topicTurn.navigationBeforePrompt?.openLesson, isFalse);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);

    final lessonTurn = await flow.handle('Con học bài số 1');
    expect(lessonTurn.promptText, 'Bắt đầu học thôi con');
    expect(lessonTurn.continueListening, isFalse);
    expect(lessonTurn.navigationAfterPrompt?.childAge, 6);
    expect(lessonTurn.navigationAfterPrompt?.topicNumber, 3);
    expect(lessonTurn.navigationAfterPrompt?.lessonNumber, 1);
    expect(lessonTurn.navigationAfterPrompt?.openLesson, isTrue);
  });

  test('uses the saved age and skips asking age for topic learning', () async {
    final flow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      childAge: 6,
    );

    flow.begin();
    final featureTurn = await flow.handle('Con muốn học theo chủ đề');

    expect(featureTurn.promptText, 'Có 10 chủ đề. Con muốn học chủ đề số mấy');
    expect(featureTurn.promptText, isNot(contains('mấy tuổi')));
    expect(flow.stage, MainVoiceAssistantStage.chooseTopic);

    final topicTurn = await flow.handle('Chủ đề số 3');
    expect(topicTurn.navigationBeforePrompt?.childAge, 6);
    expect(topicTurn.navigationBeforePrompt?.topicNumber, 3);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
  });

  test('offers topics or vocabulary after leaving speaking practice', () async {
    final vocabularyFlow = MainVoiceAssistantFlow(
      contentLoader: _loadContent,
      vocabularyLoader: _loadEmptyVocabulary,
    );

    expect(
      vocabularyFlow.beginOtherLearning(),
      MainVoiceAssistantFlow.otherLearningPrompt,
    );
    final vocabularyTurn = await vocabularyFlow.handle('Con muốn học từ vựng');
    expect(
      vocabularyTurn.promptText,
      'Con muốn luyện lại hay nghe những ngôi sao của con?',
    );
    expect(vocabularyTurn.continueListening, isTrue);
    expect(
      vocabularyTurn.navigationBeforePrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );

    final topicFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    topicFlow.beginOtherLearning();
    final topicTurn = await topicFlow.handle('Con muốn học chủ đề');
    expect(topicTurn.promptText, 'Con mấy tuổi');
    expect(topicTurn.continueListening, isTrue);
    expect(topicFlow.stage, MainVoiceAssistantStage.askAge);
  });

  test(
    'understands Vietnamese number words and rejects out-of-range choices',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      flow.begin();
      await flow.handle('Học chủ đề');
      final ageTurn = await flow.handle('Con sáu tuổi');
      expect(ageTurn.promptText, contains('10 chủ đề'));

      final invalidTopic = await flow.handle('Con chọn chủ đề số mười lăm');
      expect(invalidTopic.continueListening, isTrue);
      expect(
        invalidTopic.promptText,
        HomiFallbackCatalog.fallbackPolicyById['FB-004']!.firstPrompt,
      );
    },
  );

  test('does not treat its own spoken prompts as child selections', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    flow.begin();
    final openingEcho = await flow.handle(
      'Con muốn luyện nói hay học chủ đề nè',
    );
    expect(openingEcho.continueListening, isTrue);
    expect(openingEcho.navigationAfterPrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.chooseFeature);

    await flow.handle('Con muốn học theo chủ đề');
    await flow.handle('Con 6 tuổi');
    final topicPromptEcho = await flow.handle(
      'Có 10 chủ đề. Con muốn học chủ đề số mấy',
    );
    expect(topicPromptEcho.navigationBeforePrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.chooseTopic);

    await flow.handle('Con muốn học chủ đề số 3');
    final lessonPromptEcho = await flow.handle(
      'Có 2 bài học. Con muốn học bài số mấy',
    );
    expect(lessonPromptEcho.navigationAfterPrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
  });

  test(
    'asks before reopening a completed topic after lesson completion',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

      expect(
        flow.beginTopicSelectionAfterCompletion(
          childAge: 6,
          completedTopicNumbers: const <int>[3, 5],
        ),
        'Có 10 chủ đề. Con muốn học chủ đề số mấy',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);
      expect(
        flow.canHandle('Có 10 chủ đề. Con muốn học chủ đề số mấy'),
        isFalse,
      );

      final completedTopic = await flow.handle('Con chọn chủ đề số 3');
      expect(completedTopic.continueListening, isTrue);
      expect(completedTopic.navigationBeforePrompt, isNull);
      expect(
        completedTopic.promptText,
        'Chủ đề số 3 con đã học rồi. Con có muốn học lại không?',
      );
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);

      final declineTurn = await flow.handle('Không');
      expect(
        declineTurn.promptText,
        'Có 10 chủ đề. Con muốn học chủ đề số mấy',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);

      await flow.handle('Chủ đề số 3');
      final replayTurn = await flow.handle('Có');
      expect(replayTurn.promptText, 'Có 2 bài học. Con muốn học bài số mấy');
      expect(replayTurn.navigationBeforePrompt?.childAge, 6);
      expect(replayTurn.navigationBeforePrompt?.topicNumber, 3);
      expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
    },
  );

  test(
    'accepts natural yes and no answers when confirming topic replay',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      flow.beginTopicSelectionAfterCompletion(
        childAge: 6,
        completedTopicNumbers: const <int>[3],
      );

      await flow.handle('Chủ đề số 3');
      expect(flow.canHandle('Dạ không'), isTrue);
      final declineTurn = await flow.handle('Dạ không');
      expect(
        declineTurn.promptText,
        'Có 10 chủ đề. Con muốn học chủ đề số mấy',
      );
      expect(flow.stage, MainVoiceAssistantStage.chooseTopicAfterCompletion);

      await flow.handle('Chủ đề số 3');
      expect(flow.canHandle('Con muốn học lại'), isTrue);
      final replayTurn = await flow.handle('Con muốn học lại');
      expect(replayTurn.promptText, 'Có 2 bài học. Con muốn học bài số mấy');
      expect(replayTurn.navigationBeforePrompt?.topicNumber, 3);
      expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
    },
  );

  test(
    'uses the FB-007 retry instead of treating Mình muốn bài khác as yes',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      final policy = HomiFallbackCatalog.fallbackPolicyById['FB-007']!;
      flow.beginTopicSelectionAfterCompletion(
        childAge: 6,
        completedTopicNumbers: const <int>[3],
      );
      await flow.handle('Chủ đề số 3');

      final retry = await flow.handle('Mình muốn bài khác');

      expect(retry.promptText, policy.firstPrompt);
      expect(retry.continueListening, isTrue);
      expect(retry.navigationBeforePrompt, isNull);
      expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
    },
  );

  test('uses the FB-007 retry instead of treating Không biết as no', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final policy = HomiFallbackCatalog.fallbackPolicyById['FB-007']!;
    flow.beginTopicSelectionAfterCompletion(
      childAge: 6,
      completedTopicNumbers: const <int>[3],
    );
    await flow.handle('Chủ đề số 3');

    final retry = await flow.handle('Không biết');

    expect(retry.promptText, policy.firstPrompt);
    expect(retry.continueListening, isTrue);
    expect(retry.navigationBeforePrompt, isNull);
    expect(flow.stage, MainVoiceAssistantStage.confirmReplayTopic);
  });

  test(
    'uses the first FB-004 source prompt for an invalid topic number',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        childAge: 6,
      );
      final policy = HomiFallbackCatalog.fallbackPolicyById['FB-004']!;
      flow.begin();
      await flow.handle('Học chủ đề');

      final retry = await flow.handle('Chủ đề số 15');

      expect(retry.promptText, policy.firstPrompt);
      expect(retry.continueListening, isTrue);
      expect(flow.stage, MainVoiceAssistantStage.chooseTopic);
    },
  );

  test(
    'uses the second FB-004 source prompt for a repeated invalid topic',
    () async {
      final flow = MainVoiceAssistantFlow(
        contentLoader: _loadContent,
        childAge: 6,
      );
      final policy = HomiFallbackCatalog.fallbackPolicyById['FB-004']!;
      flow.begin();
      await flow.handle('Học chủ đề');
      await flow.handle('Chủ đề số 15');

      final retry = await flow.handle('Chủ đề số 0');

      expect(retry.promptText, policy.secondPrompt);
      expect(retry.continueListening, isFalse);
      expect(flow.stage, MainVoiceAssistantStage.chooseTopic);
    },
  );

  test(
    'uses the first FB-005 source prompt for an invalid lesson number',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      final policy = HomiFallbackCatalog.fallbackPolicyById['FB-005']!;
      final content = (await _loadContent()).topic(
        startAge: 6,
        endAge: 7,
        topicNumber: 3,
      );
      flow.beginLessonSelectionForTopic(
        childAge: 6,
        topicNumber: 3,
        topicContent: content,
        completedLessonNumbers: const <int>[],
      );

      final retry = await flow.handle('Bài số 3');

      expect(retry.promptText, policy.firstPrompt);
      expect(retry.continueListening, isTrue);
      expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
    },
  );

  test(
    'uses the second FB-005 source prompt for a repeated invalid lesson',
    () async {
      final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
      final policy = HomiFallbackCatalog.fallbackPolicyById['FB-005']!;
      final content = (await _loadContent()).topic(
        startAge: 6,
        endAge: 7,
        topicNumber: 3,
      );
      flow.beginLessonSelectionForTopic(
        childAge: 6,
        topicNumber: 3,
        topicContent: content,
        completedLessonNumbers: const <int>[],
      );
      await flow.handle('Bài số 3');

      final retry = await flow.handle('Bài số 0');

      expect(retry.promptText, policy.secondPrompt);
      expect(retry.continueListening, isFalse);
      expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
    },
  );

  test('opens an unfinished topic without asking to replay it', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginTopicSelectionAfterCompletion(
      childAge: 6,
      completedTopicNumbers: const <int>[1, 2],
    );

    final topicTurn = await flow.handle('Con muốn học chủ đề số 3');
    expect(topicTurn.promptText, 'Có 2 bài học. Con muốn học bài số mấy');
    expect(topicTurn.navigationBeforePrompt?.childAge, 6);
    expect(topicTurn.navigationBeforePrompt?.topicNumber, 3);
    expect(flow.stage, MainVoiceAssistantStage.chooseLesson);
  });

  test('offers the next unfinished lesson from real topic progress', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );

    final prompt = flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[1],
    );

    expect(prompt, contains('đã học xong bài 1'));
    expect(prompt, contains('tiếp tục bài 2'));
    expect(flow.canHandle('Con muốn tiếp tục'), isTrue);

    final turn = await flow.handle('Con muốn tiếp tục');
    expect(turn.continueListening, isFalse);
    expect(turn.navigationAfterPrompt?.topicNumber, 3);
    expect(turn.navigationAfterPrompt?.lessonNumber, 2);
    expect(turn.navigationAfterPrompt?.openLesson, isTrue);
  });

  test('confirms before replaying a completed lesson', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    final content = (await _loadContent()).topic(
      startAge: 6,
      endAge: 7,
      topicNumber: 3,
    );
    flow.beginLessonSelectionForTopic(
      childAge: 6,
      topicNumber: 3,
      topicContent: content,
      completedLessonNumbers: const <int>[1],
    );

    final confirmation = await flow.handle('Con chọn bài 1');
    expect(confirmation.continueListening, isTrue);
    expect(confirmation.promptText, contains('học lại bài 1'));
    expect(confirmation.promptText, contains('tiếp tục bài 2'));
    expect(flow.stage, MainVoiceAssistantStage.confirmReplayLesson);

    final replay = await flow.handle('Con muốn học lại');
    expect(replay.continueListening, isFalse);
    expect(replay.navigationAfterPrompt?.lessonNumber, 1);
  });
}

Future<ListeningContentCatalog> _loadContent() async {
  return ListeningContentCatalog(
    groups: <ListeningContentAgeGroup>[
      ListeningContentAgeGroup(
        startAge: 6,
        endAge: 7,
        topics: <ListeningTopicContent>[
          ListeningTopicContent(
            id: 'a067_t03',
            number: 3,
            titleVi: 'Cặp sách và lớp học',
            titleEn: 'School Bag and Classroom',
            lessons: <ListeningLessonContent>[
              _lesson(1, 'Đồ dùng học tập'),
              _lesson(2, 'Trong lớp học'),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<List<VocabularyEntry>> _loadEmptyVocabulary() async =>
    const <VocabularyEntry>[];

Future<List<VocabularyEntry>> _loadReviewAndStarsVocabulary() async =>
    (await _loadVocabularyAcrossCollections())
        .where((entry) => entry.collection != VocabularyCollection.saved)
        .toList(growable: false);

Future<List<VocabularyEntry>> _loadVocabularyAcrossCollections() async =>
    <VocabularyEntry>[
      VocabularyEntry(
        id: 'parent-apple',
        word: 'Apple',
        meaning: 'Quả táo',
        addedAt: DateTime(2026, 8, 18),
      ),
      VocabularyEntry(
        id: 'review-book',
        word: 'Open your book',
        meaning: 'Mở sách ra',
        addedAt: DateTime(2026, 8, 18),
        collection: VocabularyCollection.review,
      ),
      VocabularyEntry(
        id: 'star-morning',
        word: 'Good morning',
        meaning: 'Chào buổi sáng',
        addedAt: DateTime(2026, 8, 18),
        collection: VocabularyCollection.star,
      ),
    ];

ListeningLessonContent _lesson(int number, String title) {
  return ListeningLessonContent(
    id: 'lesson-$number',
    number: number,
    titleVi: title,
    titleEn: title,
    intro: '',
    outro: '',
    estimatedMinutes: 3,
    sentences: const <ListeningSentenceContent>[],
  );
}
