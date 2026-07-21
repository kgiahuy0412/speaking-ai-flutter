import 'dart:typed_data';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/offline_intent_recognizer.dart';
import '../../../core/audio/streaming_speech_input.dart';
import 'conversation_models.dart';

abstract interface class ConversationRepository {
  Future<void> warmAudioCache();

  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
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
  });

  Future<List<ConversationHistoryItem>> fetchHistory();

  Future<void> deleteHistoryItem(String conversationId);

  Future<void> clearHistory();

  Future<void> dispose();
}

abstract interface class BatchChunkUploadSession {
  void addAudioChunk(Uint8List bytes);

  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  });

  Future<void> discard();
}

abstract interface class ChunkedConversationRepository {
  Future<BatchChunkUploadSession> startBatchChunkUpload();
}

abstract interface class RealtimeTranscriptionSession {
  Stream<String> get partialText;

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
