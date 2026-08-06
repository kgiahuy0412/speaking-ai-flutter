import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/history_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'history shows distinct review states and filters rejected items',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = ConversationController(
        audioInput: const _FakeAudioInput(),
        playbackService: const _FakePlaybackService(),
        repository: _FakeHistoryRepository(),
        childAge: 6,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: HistorySheet(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lịch sử gần đây'), findsOneWidget);
      expect(find.text('3 lượt đã lưu'), findsOneWidget);
      expect(find.text('Đúng ý'), findsWidgets);
      expect(find.text('Sai ý'), findsWidgets);
      expect(find.text('Chưa đánh giá'), findsWidgets);
      expect(find.text('Câu đã duyệt'), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Sai ý'));
      await tester.pumpAndSettle();

      expect(find.text('Câu bị từ chối'), findsOneWidget);
      expect(find.text('Câu đã duyệt'), findsNothing);
      expect(find.text('Câu chưa đánh giá'), findsNothing);
    },
  );
}

class _FakeHistoryRepository implements ConversationRepository {
  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async {
    final now = DateTime.now();
    return <ConversationHistoryItem>[
      ConversationHistoryItem(
        conversationId: 'approved',
        vietnameseText: 'Câu đã duyệt',
        englishText: 'Approved sentence.',
        createdAt: now,
        qualityApproved: true,
        learningStatus: 'promoted',
        learningUseCount: 3,
      ),
      ConversationHistoryItem(
        conversationId: 'rejected',
        vietnameseText: 'Câu bị từ chối',
        englishText: 'Rejected sentence.',
        createdAt: now.subtract(const Duration(minutes: 1)),
        qualityApproved: false,
        learningStatus: 'rejected',
      ),
      ConversationHistoryItem(
        conversationId: 'pending',
        vietnameseText: 'Câu chưa đánh giá',
        englishText: 'Pending sentence.',
        createdAt: now.subtract(const Duration(minutes: 2)),
        qualityApproved: null,
        learningStatus: 'observing',
        learningUseCount: 2,
      ),
    ];
  }

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> deleteHistoryItem(String conversationId) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> patchPlaybackLatency({
    required String conversationId,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
    int? responseToPlaybackMs,
    bool? audioPreloadLoadedData,
    bool? audioPreloadCanPlay,
    int? audioPreloadLoadedDataMs,
    int? audioPreloadCanPlayMs,
  }) async {}

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) {
    throw UnimplementedError();
  }

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

class _FakeAudioInput implements AudioInput {
  const _FakeAudioInput();

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Mic test';

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

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

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
