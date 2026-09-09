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
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('conversation-animated-waveform')),
        findsOneWidget,
      );
    });
  }

  testWidgets('active waveform travels smoothly at frame cadence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoiceHero(
          phase: ConversationPhase.processing,
          processingStage: ConversationProcessingStage.recognizing,
          amplitude: 0,
          onStop: () {},
        ),
      ),
    );

    final waveform = find.byKey(const Key('conversation-animated-waveform'));
    Finder waveBar(int index) => find.descendant(
      of: waveform,
      matching: find.byKey(ValueKey<String>('homi-wave-bar-$index')),
    );
    var previous = <double>[
      tester.getSize(waveBar(4)).height,
      tester.getSize(waveBar(10)).height,
      tester.getSize(waveBar(16)).height,
    ];
    var changed = false;
    var largestFrameStep = 0.0;

    for (var frame = 0; frame < 24; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = <double>[
        tester.getSize(waveBar(4)).height,
        tester.getSize(waveBar(10)).height,
        tester.getSize(waveBar(16)).height,
      ];
      for (var index = 0; index < current.length; index += 1) {
        final step = (current[index] - previous[index]).abs();
        if (step > 0.01) changed = true;
        if (step > largestFrameStep) largestFrameStep = step;
      }
      previous = current;
    }

    expect(changed, isTrue);
    expect(largestFrameStep, lessThan(3.5));
  });
}
