import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/adaptive_voice_activity_detector.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/data/web_batch_streaming_speech_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploads Web MAIN audio while speaking and finalizes Batch', () async {
    final input = _FakeChunkedAudioInput();
    final session = _FakeBatchSession(transcript: 'học theo chủ đề');
    final repository = _FakeRepository(session);
    final speechInput = _createSpeechInput(input, repository);

    await speechInput.startCommandRecognition();
    _confirmSpeech(input);
    input.emitChunk(<int>[1, 2, 3]);
    input.emitChunk(<int>[4, 5]);

    final capture = await speechInput.stop();

    expect(capture.sourceText, 'học theo chủ đề');
    expect(capture.asrMode, 'batch_chunks');
    expect(capture.extraBenchmark?['webVirtualMain'], isTrue);
    expect(session.finalizeCount, 1);
    expect(session.chunks.expand((chunk) => chunk), <int>[1, 2, 3, 4, 5]);
    expect(repository.directProcessCount, 0);
    await speechInput.dispose();
    await input.dispose();
  });

  test('emits completed after speech followed by VAD silence', () async {
    final input = _FakeChunkedAudioInput();
    final speechInput = _createSpeechInput(
      input,
      _FakeRepository(_FakeBatchSession(transcript: 'học từ mới')),
    );
    final completed = Completer<void>();
    final subscription = speechInput.completed.listen((_) {
      if (!completed.isCompleted) {
        completed.complete();
      }
    });

    await speechInput.start();
    _confirmSpeech(input);
    input.emitAmplitude(-80);

    await completed.future.timeout(const Duration(milliseconds: 150));
    final capture = await speechInput.stop();

    expect(capture.sourceText, 'học từ mới');
    await subscription.cancel();
    await speechInput.dispose();
    await input.dispose();
  });

  test('discard Web MAIN Batch session when command is cancelled', () async {
    final input = _FakeChunkedAudioInput();
    final session = _FakeBatchSession(transcript: 'không dùng');
    final speechInput = _createSpeechInput(input, _FakeRepository(session));

    await speechInput.start();
    await speechInput.cancel();

    expect(input.cancelCount, 1);
    expect(session.discardCount, 1);
    expect(session.finalizeCount, 0);
    await speechInput.dispose();
    await input.dispose();
  });
}

WebBatchStreamingSpeechInput _createSpeechInput(
  _FakeChunkedAudioInput input,
  _FakeRepository repository,
) => WebBatchStreamingSpeechInput(
  audioInput: input,
  repository: repository,
  childAge: 7,
  vadSilenceDuration: const Duration(milliseconds: 15),
  voiceActivityDetector: AdaptiveVoiceActivityDetector(
    calibrationDuration: Duration.zero,
    minimumSpeechDuration: Duration.zero,
    minimumSpeechVariationDb: 0,
  ),
);

void _confirmSpeech(_FakeChunkedAudioInput input) {
  input.emitAmplitude(-60);
  input.emitAmplitude(-60);
  input.emitAmplitude(-15);
}

class _FakeChunkedAudioInput implements ChunkedAudioInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast(sync: true);
  final StreamController<Uint8List> _chunkController =
      StreamController<Uint8List>.broadcast(sync: true);

  bool started = false;
  int cancelCount = 0;

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<Uint8List> get audioChunks => _chunkController.stream;

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Web microphone';

  void emitAmplitude(double dbfs) => _amplitudeController.add(dbfs);

  void emitChunk(List<int> bytes) =>
      _chunkController.add(Uint8List.fromList(bytes));

  @override
  Future<void> start() => startChunked();

  @override
  Future<void> startChunked() async {
    started = true;
  }

  @override
  Future<AudioCapture> stop() async {
    started = false;
    return AudioCapture(
      filePath: '',
      mimeType: 'audio/wav',
      duration: const Duration(milliseconds: 800),
      inputLabel: label,
      isBluetoothInput: false,
      initialNoiseRms: 0.01,
      recordingSampleRate: 16000,
      dataBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );
  }

  @override
  Future<void> cancel() async {
    started = false;
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _chunkController.close();
  }
}

class _FakeRepository
    implements ConversationRepository, ChunkedConversationRepository {
  _FakeRepository(this.session);

  final _FakeBatchSession session;
  int directProcessCount = 0;

  @override
  Future<BatchChunkUploadSession> startBatchChunkUpload() async => session;

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    directProcessCount += 1;
    return _result('dự phòng');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatchSession implements BatchChunkUploadSession {
  _FakeBatchSession({required this.transcript});

  final String transcript;
  final List<List<int>> chunks = <List<int>>[];
  int finalizeCount = 0;
  int discardCount = 0;

  @override
  void addAudioChunk(Uint8List bytes) {
    chunks.add(bytes.toList(growable: false));
  }

  @override
  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    finalizeCount += 1;
    return _result(transcript);
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {
    discardCount += 1;
  }
}

ConversationResult _result(String transcript) => ConversationResult(
  conversationId: 'conversation-id',
  sessionId: 'session-id',
  context: PracticeContext.home,
  vietnameseText: transcript,
  englishText: '',
  audioUri: null,
  processingMode: 'cloudflare',
  textSource: 'cloudflare_asr',
  audioSource: 'none',
  asrMode: 'batch_chunks',
  latency: const ConversationLatency(
    asrMs: 10,
    llmMs: 0,
    ttsMs: 0,
    timeToFirstAudioMs: 10,
  ),
);
