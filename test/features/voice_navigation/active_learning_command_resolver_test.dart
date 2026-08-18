import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/active_learning_command_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = ActiveLearningCommandResolver();

  test('maps Vietnamese active lesson commands deterministically', () {
    const cases = <String, ActiveLearningCommand>{
      'Câu tiếp theo': ActiveLearningCommand.nextItem,
      'Con muốn tiếp theo': ActiveLearningCommand.nextItem,
      'Câu trước': ActiveLearningCommand.previousItem,
      'Nghe câu vừa rồi': ActiveLearningCommand.previousItem,
      'Con muốn nghe lại': ActiveLearningCommand.replayCurrent,
      'Học lại từ đầu': ActiveLearningCommand.restart,
      'Luyện lại từ đầu': ActiveLearningCommand.restart,
      'Cho con học bài tiếp theo': ActiveLearningCommand.nextLesson,
      'Bài trước': ActiveLearningCommand.previousLesson,
      'Tạm dừng': ActiveLearningCommand.stop,
      'Tiếp tục': ActiveLearningCommand.resume,
    };
    for (final entry in cases.entries) {
      expect(resolver.resolve(entry.key), entry.value, reason: entry.key);
    }
  });

  test('does not treat lesson content as a control command', () {
    expect(resolver.resolve('Monday Tuesday off we go'), isNull);
    expect(resolver.resolve('Con thích học tiếng Anh'), isNull);
  });
}
