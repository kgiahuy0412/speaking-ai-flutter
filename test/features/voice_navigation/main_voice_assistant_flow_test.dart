import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chooses continuous translation after the Main menu', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(flow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final translationTurn = await flow.handle('Con muốn luyện nói');
    expect(
      translationTurn.promptText,
      'Con muốn dịch một câu hay dịch liên tục?',
    );
    expect(translationTurn.continueListening, isTrue);

    final turn = await flow.handle('Dịch liên tục');

    expect(turn.promptText, contains('Muốn dừng thì nói dừng lại'));
    expect(turn.continueListening, isFalse);
    expect(
      turn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
  });

  test('offers all three top-level choices from Main', () async {
    final vocabularyFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    expect(vocabularyFlow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final vocabulary = await vocabularyFlow.handle('Học từ mới');
    expect(
      vocabulary.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.vocabulary,
    );

    final singleFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    singleFlow.begin();
    final translation = await singleFlow.handle('Dịch sang tiếng Anh');
    expect(translation.continueListening, isTrue);
    final single = await singleFlow.handle('Một câu');
    expect(single.continueListening, isFalse);
    expect(single.promptText, contains('bấm nút MAIN để bắt đầu nói'));
    expect(single.promptText, contains('bấm nút MAIN lần nữa'));
    expect(single.promptText, contains('nhấn giữ nút MAIN'));
    expect(
      single.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(single.navigationAfterPrompt?.enterMainSpeakingMode, isFalse);
  });

  test('continues an active lesson when the child answers yes', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    expect(
      flow.beginActiveLearning(),
      MainVoiceAssistantFlow.activeLearningPrompt,
    );
    expect(flow.canHandle('Có'), isTrue);

    final turn = await flow.handle('Có');
    expect(turn.promptText, 'Tiếp tục học nhé con');
    expect(turn.activeLearningCommand, ActiveLearningCommand.resume);
    expect(turn.continueListening, isFalse);
  });

  test('leaves an active lesson when the child answers no', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);
    flow.beginActiveLearning();
    expect(flow.canHandle('Không'), isTrue);

    final turn = await flow.handle('Không');
    expect(turn.promptText, 'Tạm biệt con');
    expect(turn.activeLearningCommand, ActiveLearningCommand.exitToHome);
    expect(turn.continueListening, isFalse);
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
    expect(listeningCatalogs[1].topics[2].titleVi, 'Cặp sách và lớp học');
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

  test('offers topics or vocabulary after leaving speaking practice', () async {
    final vocabularyFlow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(
      vocabularyFlow.beginOtherLearning(),
      MainVoiceAssistantFlow.otherLearningPrompt,
    );
    final vocabularyTurn = await vocabularyFlow.handle('Con muốn học từ vựng');
    expect(vocabularyTurn.promptText, 'Mình cùng học từ vựng nhé');
    expect(vocabularyTurn.continueListening, isFalse);
    expect(
      vocabularyTurn.navigationAfterPrompt?.destination,
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
      expect(invalidTopic.promptText, contains('từ số 1 đến số 10'));
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
