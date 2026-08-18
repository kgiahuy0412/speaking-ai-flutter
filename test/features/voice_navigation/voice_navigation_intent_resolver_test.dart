import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = VoiceNavigationIntentResolver();

  group('VoiceNavigationIntentResolver', () {
    test('recognizes the Hey Pico wake phrase and common ASR variants', () {
      expect(resolver.containsWakeWord('Hey Pico'), isTrue);
      expect(resolver.containsWakeWord('hay pico'), isTrue);
      expect(resolver.containsWakeWord('Hey Piko'), isTrue);
      expect(resolver.containsWakeWord('Hey Pi Cô'), isTrue);
      expect(resolver.containsWakeWord('Hay Bi Cô'), isTrue);
      expect(resolver.containsWakeWord('Ê Pi Cô'), isTrue);
      expect(resolver.containsWakeWord('Hey Bigo'), isTrue);
      expect(resolver.containsWakeWord('Pico'), isFalse);
      expect(resolver.containsWakeWord('Hãy đi coi bài tập'), isFalse);
      expect(resolver.containsWakeWord('Em biết cô giáo'), isFalse);
    });

    test('recognizes vocabulary commands with and without accents', () {
      for (final command in <String>[
        'Con muốn học từ vựng',
        'Con muốn học từ mới',
        'Con muốn học từ',
        'Con muốn luyện từ',
        'mo kho tu vung cho con',
      ]) {
        expect(
          resolver.resolve(command)?.destination,
          VoiceNavigationDestination.vocabulary,
          reason: command,
        );
      }
    });

    test('recognizes all supported topic-learning synonyms', () {
      for (final command in <String>[
        'Học bài',
        'Học theo chủ đề',
        'Học khóa học',
        'Bắt đầu bài học',
      ]) {
        expect(
          resolver.resolve(command)?.destination,
          VoiceNavigationDestination.topics,
          reason: command,
        );
      }
    });

    test('recognizes the supported top-level destinations', () {
      expect(
        resolver.resolve('Con muốn học theo chủ đề')?.destination,
        VoiceNavigationDestination.topics,
      );
      expect(
        resolver.resolve('Cho con luyện giao tiếp')?.destination,
        VoiceNavigationDestination.conversation,
      );
      expect(
        resolver.resolve('Mở lịch sử gần đây')?.destination,
        VoiceNavigationDestination.history,
      );
      expect(
        resolver.resolve('Hãy mở cài đặt')?.destination,
        VoiceNavigationDestination.settings,
      );
    });

    test('recognizes a direct topic lesson command', () {
      final byName = resolver.resolve(
        'Con muốn học bài 2 trong chủ đề Gia đình và ngôi nhà',
      );
      expect(byName?.destination, VoiceNavigationDestination.topics);
      expect(byName?.openLesson, isTrue);
      expect(byName?.lessonNumber, 2);
      expect(byName?.topicNumber, isNull);

      final byNumber = resolver.resolve('Mở bài đầu tiên trong chủ đề số 3');
      expect(byNumber?.destination, VoiceNavigationDestination.topics);
      expect(byNumber?.openLesson, isTrue);
      expect(byNumber?.lessonNumber, 1);
      expect(byNumber?.topicNumber, 3);

      final contextual = resolver.resolve('Bài 2');
      expect(contextual?.openLesson, isTrue);
      expect(contextual?.lessonNumber, 2);
    });

    test('accepts a short destination name as a direct command', () {
      expect(
        resolver.resolve('Từ vựng')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(
        resolver.resolve('主题')?.destination,
        VoiceNavigationDestination.topics,
      );
    });

    test(
      'does not redirect a normal sentence that only mentions a feature',
      () {
        expect(
          resolver.resolve('Bài học hôm nay có phần từ vựng rất khó'),
          isNull,
        );
        expect(
          resolver.resolve('Cô giáo kể một câu chuyện về lịch sử Việt Nam'),
          isNull,
        );
        expect(resolver.resolve('Con muốn uống nước'), isNull);
      },
    );

    test('prefers the most specific phrase in an ambiguous command', () {
      expect(
        resolver.resolve('Con muốn học từ vựng theo chủ đề')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
    });
  });
}
