import 'dart:async';
import 'dart:typed_data';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/offline_intent_recognizer.dart';
import '../../../core/audio/streaming_speech_input.dart';
import 'conversation_models.dart';

abstract interface class CodedConversationException {
  String get message;
  String? get errorCode;
}

/// An API failure for which retrying or using an on-device result is safe.
abstract interface class RetryableConversationException {
  bool get isRetryable;
}

abstract interface class ConversationRepository {
  Future<void> warmAudioCache();

  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  });

  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  });

  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  });

  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  });

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
  });

  Future<List<ConversationHistoryItem>> fetchHistory();

  Future<void> deleteHistoryItem(String conversationId);

  Future<void> clearHistory();

  Future<void> dispose();
}

/// Optional capability for conversation paths that produce a transcript first
/// and therefore cannot attach the original recording to `/api/conversation`.
///
/// The upload is deliberately separate from [processStreamingText] so showing
/// the Vietnamese/English response and starting TTS never wait for Cloudinary.
abstract interface class UserAudioArchiveRepository {
  Future<void> archiveUserAudio({
    required ConversationResult result,
    required AudioCapture capture,
  });
}

abstract interface class BatchChunkUploadSession {
  void addAudioChunk(Uint8List bytes);

  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  });

  Future<void> discard({String reason = 'unspecified'});
}

/// Optional capability used by low-latency Batch Chunks clients to recognize
/// a nearly complete utterance while recording is still active. Finalization
/// remains authoritative and validates the audio tail before reusing it.
abstract interface class SpeculativeBatchChunkUploadSession {
  Stream<ConversationPreview> get speculativePreviews;

  void configureSpeculativePreview({
    required PracticeContext context,
    required int childAge,
  });

  void markSpeculativeSpeechDetected();

  void markSpeculativeVoiceActive();

  void markSpeculativeVoiceInactive();

  /// Adds Web-only recorder/VAD timing to the authoritative benchmark. This
  /// does not influence finalization; it only explains whether an early
  /// terminal request really preceded a manual or automatic stop.
  void updateClientTerminalTelemetry(Map<String, dynamic> telemetry);

  /// Captures the newest uploaded PCM snapshot after the recorder has stopped.
  /// This preview is allowed to finish alongside authoritative finalization.
  void requestTerminalSpeculativePreview({bool atRecorderStop = false});
}

abstract interface class ChunkedConversationRepository {
  Future<BatchChunkUploadSession> startBatchChunkUpload();
}

abstract interface class RealtimeTranscriptionSession {
  Stream<String> get partialText;

  void markRecordingStarted(DateTime startedAt);

  void addAudioChunk(Uint8List bytes);

  Future<StreamingSpeechCapture> finalize();

  Future<void> discard();
}

abstract interface class RealtimeConversationRepository {
  Future<RealtimeTranscriptionSession> startRealtimeTranscription({
    required String audioInputLabel,
    required bool bluetoothAudioInput,
  });
}

abstract interface class OfflineIntentCatalogRepository {
  Future<OfflineIntentManifest> fetchOfflineIntentManifest();
}
