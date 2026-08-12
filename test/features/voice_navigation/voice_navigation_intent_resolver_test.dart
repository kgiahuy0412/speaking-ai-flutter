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
      expect(resolver.containsWakeWord('Pico'), isFalse);
    });

    test('recognizes vocabulary commands with and without accents', () {
      expect(
        resolver.resolve('Con muốn học từ vựng')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(
        resolver.resolve('mo kho tu vung cho con')?.destination,
        VoiceNavigationDestination.vocabulary,
      );
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
