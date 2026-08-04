import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/speech_gated_batch_upload_session.dart';

void main() {
  test(
    'keeps pre-roll and forwards only audio around confirmed speech',
    () async {
      final delegate = _FakeBatchUploadSession();
      final upload = SpeechGatedBatchUploadSession(delegate: delegate);
      final chunkBytes = pcm16ChunkByteLength(sampleRate: pcm16SampleRate);

      upload.addAudioChunk(_filledBytes(chunkBytes, 1));
      upload.addAudioChunk(_filledBytes(chunkBytes, 2));
      upload.addAudioChunk(_filledBytes(chunkBytes, 3));

      expect(delegate.chunks, isEmpty);
      upload.markSpeechDetected();
      upload.addAudioChunk(_filledBytes(chunkBytes, 4));

      expect(delegate.chunks, hasLength(3));
      expect(delegate.chunks.map((chunk) => chunk.first), <int>[2, 3, 4]);

      await upload.finalize(
        capture: AudioCapture(
          filePath: 'full.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 800),
          inputLabel: 'Mic điện thoại',
          isBluetoothInput: false,
          initialNoiseRms: 0.01,
          streamHeaderBytes: buildPcm16WavHeader(
            pcmByteLength: chunkBytes * 4,
            sampleRate: pcm16SampleRate,
          ),
          streamedAudioBytes: chunkBytes * 4,
          recordingSampleRate: pcm16SampleRate,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      final capture = delegate.finalizedCapture!;
      expect(capture.streamedAudioBytes, chunkBytes * 3);
      expect(capture.duration, const Duration(milliseconds: 600));
      expect(
        ByteData.sublistView(
          capture.streamHeaderBytes!,
        ).getUint32(40, Endian.little),
        chunkBytes * 3,
      );
    },
  );

  test('buffers confirmed speech until the network session is attached', () {
    final upload = SpeechGatedBatchUploadSession();
    final chunk = _filledBytes(
      pcm16ChunkByteLength(sampleRate: pcm16SampleRate),
      7,
    );

    upload.addAudioChunk(chunk);
    upload.markSpeechDetected();
    final delegate = _FakeBatchUploadSession();
    upload.attachDelegate(delegate);

    expect(delegate.chunks, hasLength(1));
    expect(delegate.chunks.single, chunk);
  });

  test(
    'drops trailing silence but keeps a pause when speech resumes',
    () async {
      final delegate = _FakeBatchUploadSession();
      final upload = SpeechGatedBatchUploadSession(delegate: delegate);
      final chunkBytes = pcm16ChunkByteLength(sampleRate: pcm16SampleRate);

      upload.addAudioChunk(_filledBytes(chunkBytes, 1));
      upload.markSpeechDetected();
      upload.addAudioChunk(_filledBytes(chunkBytes, 2));
      upload.markVoiceInactive();
      upload.addAudioChunk(_filledBytes(chunkBytes, 3));
      upload.markVoiceActive();
      upload.addAudioChunk(_filledBytes(chunkBytes, 4));
      upload.markVoiceInactive();
      upload.addAudioChunk(_filledBytes(chunkBytes, 5));

      await upload.finalize(
        capture: AudioCapture(
          filePath: 'full.wav',
          mimeType: 'audio/wav',
          duration: const Duration(seconds: 1),
          inputLabel: 'Mic điện thoại',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamedAudioBytes: chunkBytes * 5,
          recordingSampleRate: pcm16SampleRate,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      expect(delegate.chunks.map((chunk) => chunk.first), <int>[1, 2, 3, 4, 5]);
      expect(delegate.finalizedCapture!.duration, const Duration(seconds: 1));
    },
  );
}

Uint8List _filledBytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));

class _FakeBatchUploadSession implements BatchChunkUploadSession {
  final List<Uint8List> chunks = <Uint8List>[];
  AudioCapture? finalizedCapture;

  @override
  void addAudioChunk(Uint8List bytes) {
    chunks.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {}

  @override
  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    finalizedCapture = capture;
    return ConversationResult(
      conversationId: 'conversation',
      sessionId: 'session',
      context: context,
      vietnameseText: 'Con muốn uống nước.',
      englishText: 'I want to drink water.',
      audioUri: null,
      processingMode: 'rule',
      textSource: 'phrase_rule',
      audioSource: 'cache',
      asrMode: 'batch_chunks',
      latency: ConversationLatency.fromJson(const <String, dynamic>{}),
    );
  }
}
