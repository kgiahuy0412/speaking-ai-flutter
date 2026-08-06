import '../../../core/audio/audio_input.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../domain/conversation_models.dart';
import '../domain/conversation_repository.dart';

class DemoConversationRepository implements ConversationRepository {
  const DemoConversationRepository();

  static int _phraseIndex = 0;

  @override
  Future<void> warmAudioCache() async {}

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final phrase = _nextPhrase();
    return ConversationResult(
      conversationId: 'conv_demo_$_phraseIndex',
      sessionId: 'sess_demo',
      context: context,
      vietnameseText: phrase.vietnameseText,
      englishText: phrase.englishText,
      audioUri: null,
      processingMode: 'demo',
      textSource: 'demo_fixture',
      audioSource: 'demo',
      asrMode: 'batch_chunks',
      latency: const ConversationLatency(
        asrMs: 420,
        llmMs: 5,
        ttsMs: 3,
        timeToFirstAudioMs: 640,
      ),
    );
  }

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) {
    return processAudio(
      capture: AudioCapture(
        filePath: '',
        mimeType: '',
        duration: capture.duration,
        inputLabel: capture.inputLabel,
        isBluetoothInput: false,
        initialNoiseRms: null,
      ),
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
    );
  }

  @override
  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  }) async => null;

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
  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return ConversationLearningOutcome(
      status: approved ? 'promoted' : 'rejected',
      promoted: approved,
      useCount: approved ? 3 : 0,
      threshold: 3,
      message: approved
          ? 'Ứng dụng đã học câu này để phản hồi nhanh hơn lần sau.'
          : 'Đã bỏ câu này khỏi phần học tự động.',
    );
  }

  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async {
    return <ConversationHistoryItem>[
      ConversationHistoryItem(
        conversationId: 'conv_demo_1',
        vietnameseText: _demoPhrases[0].vietnameseText,
        englishText: _demoPhrases[0].englishText,
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
        qualityApproved: true,
        promotedToRule: true,
        learningStatus: 'promoted',
        learningReason: 'positive_feedback',
        learningUseCount: 3,
      ),
      ConversationHistoryItem(
        conversationId: 'conv_demo_2',
        vietnameseText: _demoPhrases[1].vietnameseText,
        englishText: _demoPhrases[1].englishText,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        qualityApproved: null,
        learningStatus: 'observing',
        learningUseCount: 2,
      ),
    ];
  }

  @override
  Future<void> deleteHistoryItem(String conversationId) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> dispose() async {}

  _DemoPhrase _nextPhrase() {
    final phrase = _demoPhrases[_phraseIndex % _demoPhrases.length];
    _phraseIndex++;
    return phrase;
  }
}

const List<_DemoPhrase> _demoPhrases = <_DemoPhrase>[
  _DemoPhrase(
    vietnameseText: 'Con mu\u1ed1n \u0103n c\u01a1m',
    englishText: 'I want to eat rice, please.',
  ),
  _DemoPhrase(
    vietnameseText: 'Con c\u1ea7n b\u00fat ch\u00ec',
    englishText: 'I need a pencil, please.',
  ),
  _DemoPhrase(
    vietnameseText: 'Con mu\u1ed1n u\u1ed1ng n\u01b0\u1edbc',
    englishText: 'Can I have some water, please?',
  ),
  _DemoPhrase(
    vietnameseText: 'Con mu\u1ed1n \u0111i v\u1ec7 sinh',
    englishText: 'I need to use the bathroom, please.',
  ),
];

class _DemoPhrase {
  const _DemoPhrase({required this.vietnameseText, required this.englishText});

  final String vietnameseText;
  final String englishText;
}
