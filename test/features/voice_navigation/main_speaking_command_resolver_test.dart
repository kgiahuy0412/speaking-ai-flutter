import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_command_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = MainSpeakingCommandResolver();

  test('detects requests to learn something else', () {
    for (final text in <String>[
      'Còn cái gì khác để học không?',
      'Có gì khác không?',
      'Con muốn học cái khác',
      'Con muốn học thứ khác',
      'Cho con học bài khác',
    ]) {
      expect(resolver.resolve(text), MainSpeakingCommand.otherLearning);
    }
  });

  test('keeps spoken stop phrases in the normal translation flow', () {
    for (final text in <String>[
      'Dừng lại',
      'Con muốn dừng lại',
      'Dừng dịch liên tục',
      'Ngừng lại',
      'Con muốn ngừng lại',
      'Con không dịch nữa',
      'Thoát dịch',
      'Dừng dịch liên tục nhé',
      'Con muốn dừng lại ạ',
      'Hãy dừng lại',
      'Làm ơn ngừng lại nhé ạ',
      'Dừng lại đi ạ',
      'Dừng luyện nói',
      'Thoát luyện nói',
      'Con không muốn luyện nói nữa',
    ]) {
      expect(resolver.resolve(text), isNull);
    }
  });

  test('keeps ordinary speaking sentences in the translation flow', () {
    for (final text in <String>[
      'Con muốn ăn cơm',
      'Hôm nay con học ở trường',
      'Con thích một bài hát khác',
    ]) {
      expect(resolver.resolve(text), isNull);
    }
  });
}
