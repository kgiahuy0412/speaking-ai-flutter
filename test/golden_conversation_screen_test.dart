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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recording screen matches the selected mobile direction', (
    tester,
  ) async {
    await _loadGoldenFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller =
        ConversationController(
            audioInput: const _PreviewAudioInput(),
            playbackService: const _PreviewPlaybackService(),
            repository: const _PreviewRepository(),
            childAge: 6,
          )
          ..phase = ConversationPhase.recording
          ..amplitude = 0.58
          ..result = _previewResult;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: ConversationScreen(
          controller: controller,
          config: AppConfig(
            backendBaseUri: _previewBackendUri,
            useDemoBackend: true,
            childAge: 6,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/conversation-recording-390x844.png'),
    );
  });
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}

final _previewBackendUri = Uri.parse('https://api.example.com');

const _previewResult = ConversationResult(
  conversationId: 'conv_preview',
  sessionId: 'sess_preview',
  context: PracticeContext.school,
  vietnameseText: 'Con cần bút chì',
  englishText: 'I need a pencil, please.',
  audioUri: null,
  processingMode: 'rule',
  textSource: 'phrase_rule',
  audioSource: 'cache',
  asrMode: 'batch_chunks',
  latency: ConversationLatency(
    asrMs: 410,
    llmMs: 2,
    ttsMs: 1,
    timeToFirstAudioMs: 620,
  ),
);

class _PreviewAudioInput implements AudioInput {
  const _PreviewAudioInput();

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
  Future<AudioCapture> stop() {
    throw UnimplementedError();
  }
}

class _PreviewPlaybackService implements AudioPlaybackService {
  const _PreviewPlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) {
    throw UnimplementedError();
  }

  @override
  Future<void> stop() async {}
}

class _PreviewRepository implements ConversationRepository {
  const _PreviewRepository();

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> deleteHistoryItem(String conversationId) async {}

  @override
  Future<void> warmAudioCache() async {}

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
  }) async => _previewResult;

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async => _previewResult;

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
  Future<void> dispose() async {}
}
