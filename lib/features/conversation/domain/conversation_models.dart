enum PracticeContext {
  home('home', 'Ở nhà'),
  school('school', 'Ở trường'),
  outside('outside', 'Ra ngoài');

  const PracticeContext(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

enum AsrMode {
  androidStreaming('android_streaming', 'Android streaming'),
  openAiRealtime('openai_realtime', 'OpenAI Realtime'),
  bleOfflineIntent('ble_offline_intent', 'BLE offline intent'),
  batchChunks('batch_chunks', 'Batch Chunks dự phòng'),
  deviceStreaming('device_streaming', 'BLE streaming');

  const AsrMode(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isBackendSupported => this != AsrMode.deviceStreaming;

  bool get isUserSelectable =>
      this != AsrMode.batchChunks && this != AsrMode.bleOfflineIntent;
}

enum ConversationPhase { idle, recording, processing, ready, error }

class ConversationLearningOutcome {
  const ConversationLearningOutcome({
    required this.status,
    required this.promoted,
    required this.useCount,
    required this.threshold,
    required this.message,
  });

  factory ConversationLearningOutcome.fromJson(
    dynamic value, {
    bool? approved,
  }) {
    if (value is Map<String, dynamic>) {
      return ConversationLearningOutcome(
        status: value['status'] as String? ?? 'unknown',
        promoted: value['promoted'] as bool? ?? false,
        useCount: _readInt(value['useCount']),
        threshold: _readInt(value['threshold'], fallback: 3),
        message: value['message'] as String? ?? '',
      );
    }

    return ConversationLearningOutcome(
      status: approved == false ? 'rejected' : 'unknown',
      promoted: false,
      useCount: 0,
      threshold: 3,
      message: '',
    );
  }

  final String status;
  final bool promoted;
  final int useCount;
  final int threshold;
  final String message;

  static int _readInt(dynamic value, {int fallback = 0}) =>
      value is num ? value.round() : fallback;
}

class ConversationLatency {
  const ConversationLatency({
    required this.asrMs,
    required this.llmMs,
    required this.ttsMs,
    required this.timeToFirstAudioMs,
    this.audioLoadMs,
    this.audioFromDeviceCache,
    this.ttsFirstByteMs,
    this.audioStartedAfterStopMs,
  });

  factory ConversationLatency.fromJson(Map<String, dynamic> json) {
    return ConversationLatency(
      asrMs: _readInt(json['asrMs']),
      llmMs: _readInt(json['llmMs']),
      ttsMs: _readInt(json['ttsMs']),
      timeToFirstAudioMs: _readInt(json['timeToFirstAudioMs']),
      audioLoadMs:
          _readNullableInt(json['audioLoadMs']) ??
          _readNullableInt(json['ttsFirstByteMs']),
      audioFromDeviceCache: json['audioFromDeviceCache'] as bool?,
      ttsFirstByteMs: _readNullableInt(json['ttsFirstByteMs']),
      audioStartedAfterStopMs: _readNullableInt(
        json['audioStartedAfterStopMs'],
      ),
    );
  }

  final int asrMs;
  final int llmMs;
  final int ttsMs;
  final int timeToFirstAudioMs;
  final int? audioLoadMs;
  final bool? audioFromDeviceCache;
  @Deprecated('Use audioLoadMs')
  final int? ttsFirstByteMs;
  final int? audioStartedAfterStopMs;

  static int _readInt(dynamic value) => value is num ? value.round() : 0;

  static int? _readNullableInt(dynamic value) =>
      value is num ? value.round() : null;
}

class ConversationPreview {
  const ConversationPreview({
    required this.sourceText,
    required this.englishText,
    required this.textSource,
    required this.audioUri,
  });

  final String sourceText;
  final String englishText;
  final String textSource;
  final Uri? audioUri;
}

class ConversationResult {
  const ConversationResult({
    required this.conversationId,
    required this.sessionId,
    required this.context,
    required this.vietnameseText,
    required this.englishText,
    required this.audioUri,
    required this.processingMode,
    required this.textSource,
    required this.audioSource,
    required this.asrMode,
    required this.latency,
    this.learning,
  });

  factory ConversationResult.fromJson(
    Map<String, dynamic> json, {
    required Uri backendBaseUri,
  }) {
    final rawAudioUrl = json['audioUrl'] as String?;
    return ConversationResult(
      conversationId: json['conversationId'] as String,
      sessionId: json['sessionId'] as String,
      context: PracticeContext.values.firstWhere(
        (item) => item.apiValue == json['context'],
        orElse: () => PracticeContext.home,
      ),
      vietnameseText: json['vietnameseText'] as String? ?? '',
      englishText: json['englishText'] as String? ?? '',
      audioUri: rawAudioUrl == null
          ? null
          : backendBaseUri.resolve(rawAudioUrl),
      processingMode: json['processingMode'] as String? ?? 'fallback',
      textSource: json['textSource'] as String? ?? 'fallback',
      audioSource: json['audioSource'] as String? ?? 'openai_tts',
      asrMode: json['asrMode'] as String? ?? 'batch_chunks',
      latency: ConversationLatency.fromJson(
        json['latency'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      learning: json['learning'] == null
          ? null
          : ConversationLearningOutcome.fromJson(json['learning']),
    );
  }

  final String conversationId;
  final String sessionId;
  final PracticeContext context;
  final String vietnameseText;
  final String englishText;
  final Uri? audioUri;
  final String processingMode;
  final String textSource;
  final String audioSource;
  final String asrMode;
  final ConversationLatency latency;
  final ConversationLearningOutcome? learning;
}

class ConversationHistoryItem {
  const ConversationHistoryItem({
    required this.conversationId,
    required this.vietnameseText,
    required this.englishText,
    required this.createdAt,
    required this.qualityApproved,
    this.promotedToRule = false,
    this.learningStatus = 'unknown',
    this.learningReason,
    this.learningUseCount,
    this.audioUri,
    this.context = PracticeContext.home,
    this.processingMode = 'unknown',
    this.textSource = 'unknown',
    this.audioSource = 'unknown',
    this.asrMode = 'unknown',
    this.inputMode = 'unknown',
    this.latency = const ConversationLatency(
      asrMs: 0,
      llmMs: 0,
      ttsMs: 0,
      timeToFirstAudioMs: 0,
    ),
  });

  factory ConversationHistoryItem.fromJson(
    Map<String, dynamic> json, {
    Uri? backendBaseUri,
  }) {
    final parsedCreatedAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final rawAudioUrl = json['audioUrl'] as String?;

    return ConversationHistoryItem(
      conversationId: json['conversationId'] as String? ?? '',
      vietnameseText: json['vietnameseText'] as String? ?? '',
      englishText: json['englishText'] as String? ?? '',
      createdAt: (parsedCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal(),
      qualityApproved: json['qualityApproved'] as bool?,
      promotedToRule: json['promotedToRule'] as bool? ?? false,
      learningStatus: json['learningStatus'] as String? ?? 'unknown',
      learningReason: json['learningReason'] as String?,
      learningUseCount: _readNullableInt(json['learningUseCount']),
      audioUri: rawAudioUrl == null
          ? null
          : backendBaseUri?.resolve(rawAudioUrl) ?? Uri.tryParse(rawAudioUrl),
      context: PracticeContext.values.firstWhere(
        (item) => item.apiValue == json['context'],
        orElse: () => PracticeContext.home,
      ),
      processingMode: json['processingMode'] as String? ?? 'unknown',
      textSource: json['textSource'] as String? ?? 'unknown',
      audioSource: json['audioSource'] as String? ?? 'unknown',
      asrMode: json['asrMode'] as String? ?? 'unknown',
      inputMode: json['inputMode'] as String? ?? 'unknown',
      latency: ConversationLatency.fromJson(
        json['latency'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  final String conversationId;
  final String vietnameseText;
  final String englishText;
  final DateTime createdAt;
  final bool? qualityApproved;
  final bool promotedToRule;
  final String learningStatus;
  final String? learningReason;
  final int? learningUseCount;
  final Uri? audioUri;
  final PracticeContext context;
  final String processingMode;
  final String textSource;
  final String audioSource;
  final String asrMode;
  final String inputMode;
  final ConversationLatency latency;

  HistoryReviewStatus get reviewStatus => switch (qualityApproved) {
    true => HistoryReviewStatus.approved,
    false => HistoryReviewStatus.rejected,
    null => HistoryReviewStatus.pending,
  };

  ConversationHistoryItem copyWithReview(
    bool approved, {
    ConversationLearningOutcome? learning,
  }) {
    return ConversationHistoryItem(
      conversationId: conversationId,
      vietnameseText: vietnameseText,
      englishText: englishText,
      createdAt: createdAt,
      qualityApproved: approved,
      promotedToRule: learning?.promoted ?? promotedToRule,
      learningStatus:
          learning?.status ?? (approved ? learningStatus : 'rejected'),
      learningReason: learning == null
          ? learningReason
          : approved
          ? 'positive_feedback'
          : 'negative_feedback',
      learningUseCount: learning?.useCount ?? learningUseCount,
      audioUri: audioUri,
      context: context,
      processingMode: processingMode,
      textSource: textSource,
      audioSource: audioSource,
      asrMode: asrMode,
      inputMode: inputMode,
      latency: latency,
    );
  }

  static int? _readNullableInt(dynamic value) =>
      value is num ? value.round() : null;
}

enum HistoryReviewStatus { approved, rejected, pending }

class ConversationBenchmark {
  const ConversationBenchmark({
    required this.utteranceDurationMs,
    required this.vadSilenceMs,
    required this.requestedAsrMode,
    required this.audioInputLabel,
    required this.bluetoothAudioInput,
    required this.initialNoiseRms,
  });

  final int utteranceDurationMs;
  final int vadSilenceMs;
  final AsrMode requestedAsrMode;
  final String audioInputLabel;
  final bool bluetoothAudioInput;
  final double? initialNoiseRms;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'device': 'mobile',
    'browser': 'flutter_android',
    'utteranceDurationMs': utteranceDurationMs,
    'vadSilenceMs': vadSilenceMs,
    'requestedAsrMode': requestedAsrMode.apiValue,
    'audioInputLabel': audioInputLabel,
    'bluetoothAudioInput': bluetoothAudioInput,
    if (initialNoiseRms != null) 'initialNoiseRms': initialNoiseRms,
  };
}
