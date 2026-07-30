import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/speak_action_bar.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/voice_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      <
        ({
          ConversationProcessingStage stage,
          String heroLabel,
          String actionLabel,
        })
      >[
        (
          stage: ConversationProcessingStage.recognizing,
          heroLabel: 'Đang nhận giọng nói…',
          actionLabel: 'Đang nhận giọng nói…',
        ),
        (
          stage: ConversationProcessingStage.translating,
          heroLabel: 'Đang dịch sang tiếng Anh…',
          actionLabel: 'Đang dịch…',
        ),
        (
          stage: ConversationProcessingStage.preparingAudio,
          heroLabel: 'Đang chuẩn bị âm thanh…',
          actionLabel: 'Đang chuẩn bị âm thanh…',
        ),
      ];

  for (final testCase in cases) {
    testWidgets('shows the ${testCase.stage.name} processing status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Expanded(
                  child: VoiceHero(
                    phase: ConversationPhase.processing,
                    processingStage: testCase.stage,
                    amplitude: 0,
                    onStop: () {},
                  ),
                ),
                SpeakActionBar(
                  phase: ConversationPhase.processing,
                  processingStage: testCase.stage,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text(testCase.heroLabel), findsWidgets);
      expect(find.text(testCase.actionLabel), findsWidgets);
    });
  }
}
