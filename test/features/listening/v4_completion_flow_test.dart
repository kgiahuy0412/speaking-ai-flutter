import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the approved V4.1 completion prompts verbatim', () {
    expect(
      v4CompletionPrompt(V4CompletionStage.lessonEnd),
      'Bạn muốn học bài tiếp theo hay học lại bài này?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.topicEnd),
      'Bạn muốn học chủ đề tiếp theo hay học lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.topicRelearnScope),
      'Bạn muốn học lại toàn bộ chủ đề hay chỉ học lại bài này?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.nextLevel, nextLevel: 2),
      'Bạn muốn bắt đầu Level 2 hay dừng lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.courseEnd),
      'Bạn muốn học khóa mới hay học lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.courseRelearnLevel),
      'Bạn muốn học lại Level 1, Level 2 hay Level 3?',
    );
  });

  test('resolves spoken V4 choices within the active completion stage', () {
    const resolver = V4CompletionChoiceResolver();

    expect(
      resolver.resolve(
        'Con muốn học bài tiếp theo',
        stage: V4CompletionStage.lessonEnd,
      ),
      V4CompletionAction.nextLesson,
    );
    expect(
      resolver.resolve('Học lại bài này ạ', stage: V4CompletionStage.lessonEnd),
      V4CompletionAction.relearnCurrentLesson,
    );
    expect(
      resolver.resolve(
        'Học lại toàn bộ chủ đề',
        stage: V4CompletionStage.topicRelearnScope,
      ),
      V4CompletionAction.relearnTopic,
    );
    expect(
      resolver.resolve(
        'Cho con học lại level hai',
        stage: V4CompletionStage.courseRelearnLevel,
      ),
      V4CompletionAction.relearnLevel2,
    );
    expect(
      resolver.resolve('Dừng lại', stage: V4CompletionStage.nextLevel),
      V4CompletionAction.stop,
    );
  });

  test('does not return a choice that is not offered on screen', () {
    expect(
      const V4CompletionChoiceResolver().resolve(
        'Dừng lại',
        stage: V4CompletionStage.lessonEnd,
        allowedActions: const <V4CompletionAction>[
          V4CompletionAction.nextLesson,
          V4CompletionAction.relearnCurrentLesson,
        ],
      ),
      isNull,
    );
  });
}
