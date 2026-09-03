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

  test(
    'routes approved INT-018 stop phrases out of continuous translation',
    () {
      for (final text in <String>[
        'Dừng lại',
        'Mình muốn dừng',
        'Dừng dịch liên tục',
        'Ngừng dịch',
        'Không dịch nữa',
        'Thoát dịch',
        'Hổng dịch nữa',
        'Dừng dịch giúp mình',
      ]) {
        expect(resolver.resolve(text), MainSpeakingCommand.stopTranslation);
      }
    },
  );

  test('keeps unapproved non-translation stop requests out of this flow', () {
    for (final text in <String>[
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
      'Tôi muốn học bài khác bằng tiếng Anh',
    ]) {
      expect(resolver.resolve(text), isNull);
    }
  });
}
