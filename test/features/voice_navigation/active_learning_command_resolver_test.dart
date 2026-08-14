import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/active_learning_command_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = ActiveLearningCommandResolver();

  test('maps Vietnamese active lesson commands deterministically', () {
    expect(
      resolver.resolve('Con muốn nghe lại'),
      ActiveLearningCommand.replayCurrent,
    );
    expect(
      resolver.resolve('Cho con học bài tiếp theo'),
      ActiveLearningCommand.nextLesson,
    );
    expect(resolver.resolve('Luyện lại từ đầu'), ActiveLearningCommand.restart);
    expect(resolver.resolve('Tạm dừng'), ActiveLearningCommand.stop);
    expect(resolver.resolve('Tiếp tục'), ActiveLearningCommand.resume);
  });

  test('does not treat lesson content as a control command', () {
    expect(resolver.resolve('Monday Tuesday off we go'), isNull);
    expect(resolver.resolve('Con thích học tiếng Anh'), isNull);
  });
}
