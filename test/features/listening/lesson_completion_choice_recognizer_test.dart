import 'package:ai_speaking_flutter_app/features/listening/application/lesson_completion_choice_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = LessonCompletionChoiceResolver();

  test('recognizes restart lesson variants', () {
    expect(
      resolver.resolve('Con muốn luyện lại từ đầu ạ'),
      LessonCompletionChoice.restartLesson,
    );
    expect(resolver.resolve('học lại'), LessonCompletionChoice.restartLesson);
  });

  test('recognizes next lesson variants', () {
    expect(
      resolver.resolve('Bài tiếp theo'),
      LessonCompletionChoice.nextLesson,
    );
    expect(
      resolver.resolve('Học bài kế tiếp nhé'),
      LessonCompletionChoice.nextLesson,
    );
  });

  test('does not guess an unrelated answer', () {
    expect(resolver.resolve('Con chưa biết'), isNull);
  });
}
