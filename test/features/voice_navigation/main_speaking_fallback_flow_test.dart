import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_fallback_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FB-009 confirms an other-learning command before exiting translation',
    () {
      final flow = MainSpeakingFallbackFlow();

      final request = flow.handle('Mình muốn học cái khác');

      expect(request?.action, MainSpeakingFallbackAction.resumeTranslation);
      expect(
        request?.promptText,
        HomiFallbackCatalog.fallbackPolicyById['FB-009']!.firstPrompt,
      );
      expect(flow.isAwaitingConfirmation, isTrue);

      final confirmed = flow.handle('Có');

      expect(confirmed?.action, MainSpeakingFallbackAction.openOtherLearning);
      expect(confirmed?.promptText, isNull);
      expect(flow.isAwaitingConfirmation, isFalse);
    },
  );

  test('FB-009 keeps translation on a clear no and after an unclear reply', () {
    final policy = HomiFallbackCatalog.fallbackPolicyById['FB-009']!;
    final flow = MainSpeakingFallbackFlow();

    flow.handle('Mình muốn học cái khác');
    final declined = flow.handle('Không');
    expect(declined?.action, MainSpeakingFallbackAction.resumeTranslation);
    expect(declined?.promptText, isNull);
    expect(flow.isAwaitingConfirmation, isFalse);

    flow.handle('Mình muốn học cái khác');
    final unclear = flow.handle('Mình thích cá heo');
    expect(unclear?.action, MainSpeakingFallbackAction.resumeTranslation);
    expect(unclear?.promptText, policy.secondPrompt);
    expect(flow.isAwaitingConfirmation, isFalse);
  });

  test(
    'a global stop takes priority over a pending other-learning request',
    () {
      final flow = MainSpeakingFallbackFlow();

      flow.handle('Mình muốn học cái khác');
      final stop = flow.handle('Dừng lại');

      expect(stop?.action, MainSpeakingFallbackAction.openMainAssistant);
      expect(stop?.promptText, isNull);
      expect(flow.isAwaitingConfirmation, isFalse);
    },
  );

  test(
    'global stop and help phrases are recognized only in their full form',
    () {
      final flow = MainSpeakingFallbackFlow();

      final stop = flow.handle('Thôi');
      expect(
        stop?.promptText,
        HomiFallbackCatalog.fallbackPolicyById['FB-009']!.firstPrompt,
      );
      final confirmedStop = flow.handle('Dừng lại');
      expect(
        confirmedStop?.action,
        MainSpeakingFallbackAction.openMainAssistant,
      );

      final help = flow.handle('Giúp mình với');
      expect(help?.action, MainSpeakingFallbackAction.resumeTranslation);
      expect(
        help?.promptText,
        HomiFallbackCatalog.assistantPromptById['AI-022'],
      );

      expect(flow.handle('Hôm nay mình không hiểu bài này'), isNull);
    },
  );
}
