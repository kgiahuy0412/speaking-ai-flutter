import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'main flow supports 200 percent text, small screens and reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final controller =
          ConversationController(
              audioInput: const _AccessibleAudioInput(),
              playbackService: const _AccessiblePlaybackService(),
              repository: const _AccessibleRepository(),
              childAge: 6,
            )
            ..phase = ConversationPhase.ready
            ..result = _result;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ConversationScreen(
            controller: controller,
            config: AppConfig(
              backendBaseUri: Uri.parse('https://api.example.com'),
              useDemoBackend: true,
              childAge: 6,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Nói câu mới',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Cài đặt'), findsOneWidget);

      final topicShortcut = find.byKey(const Key('topic-listening-shortcut'));
      await tester.ensureVisible(topicShortcut);
      await tester.tapAt(
        tester.getTopLeft(topicShortcut) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(find.text('Luyện nghe theo chủ đề'), findsOneWidget);
      expect(find.byKey(const Key('topic-listening-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cài đặt'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Ngữ cảnh'), findsNothing);
      expect(find.text('Dữ liệu và quyền riêng tư'), findsNothing);
      expect(find.text('Xem hoặc xóa dữ liệu'), findsNothing);
      expect(find.text('Xem lịch sử gần đây'), findsOneWidget);
      semantics.dispose();
    },
  );
}

const _result = ConversationResult(
  conversationId: 'conv_accessibility',
  sessionId: 'sess_accessibility',
  context: PracticeContext.home,
  vietnameseText: 'Mình ăn gì vậy bố?',
  englishText: 'What are we going to eat, Dad?',
  audioUri: null,
  processingMode: 'rule',
  textSource: 'phrase_rule',
  audioSource: 'cache',
  asrMode: 'batch_chunks',
  latency: ConversationLatency(
    asrMs: 400,
    llmMs: 1,
    ttsMs: 1,
    timeToFirstAudioMs: 620,
  ),
);

class _AccessibleAudioInput implements AudioInput {
  const _AccessibleAudioInput();

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Mic điện thoại';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> start() async {}

  @override
  Future<AudioCapture> stop() => throw UnimplementedError();
}

class _AccessiblePlaybackService implements AudioPlaybackService {
  const _AccessiblePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) => throw UnimplementedError();

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> stop() async {}
}

class _AccessibleRepository implements ConversationRepository {
  const _AccessibleRepository();

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> deleteHistoryItem(String conversationId) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async =>
      const <ConversationHistoryItem>[];

  @override
  Future<void> patchPlaybackLatency({
    required String conversationId,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
  }) async {}

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async => _result;

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async => _result;

  @override
  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  }) async => null;

  @override
  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  }) async => ConversationLearningOutcome(
    status: approved ? 'promoted' : 'rejected',
    promoted: approved,
    useCount: approved ? 3 : 0,
    threshold: 3,
    message: '',
  );

  @override
  Future<void> warmAudioCache() async {}
}
