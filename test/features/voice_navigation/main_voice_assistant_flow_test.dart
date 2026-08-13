import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enters Main speaking mode after the spoken confirmation', () async {
    final flow = MainVoiceAssistantFlow(contentLoader: _loadContent);

    expect(flow.begin(), MainVoiceAssistantFlow.openingPrompt);
    final turn = await flow.handle('Con ghi muốn luyện nói');

    expect(turn.promptText, 'Bắt đầu nói đi con');
    expect(turn.continueListening, isFalse);
    expect(
      turn.navigationAfterPrompt?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(turn.navigationAfterPrompt?.enterMainSpeakingMode, isTrue);
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
      'Có chứ. Con muốn học chủ đề hay học từ vựng nè',
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
