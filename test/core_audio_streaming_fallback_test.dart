import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/offline_intent_recognizer.dart';
import 'package:ai_speaking_flutter_app/core/audio/preferred_audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/realtime_fallback_buffer.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback buffer keeps immutable chunks in order', () {
    final buffer = RealtimeFallbackBuffer(maxBytes: 8);
    final source = Uint8List.fromList(<int>[1, 2, 3]);
    buffer.add(source);
    source[0] = 9;
    buffer.add(Uint8List.fromList(<int>[4, 5]));

    final replayed = <List<int>>[];
    buffer.replay((bytes) => replayed.add(bytes.toList()));

    expect(replayed, <List<int>>[
      <int>[1, 2, 3],
      <int>[4, 5],
    ]);
    expect(buffer.byteLength, 5);
    expect(buffer.canReplay, isTrue);
  });

  test('fallback buffer refuses a partial replay after its limit', () {
    final buffer = RealtimeFallbackBuffer(maxBytes: 4);
    buffer.add(Uint8List.fromList(<int>[1, 2, 3]));
    buffer.add(Uint8List.fromList(<int>[4, 5]));

    expect(buffer.overflowed, isTrue);
    expect(buffer.canReplay, isFalse);
    expect(buffer.byteLength, 0);
  });

  test('unlocks browser audio before stopping previous playback', () async {
    final events = <String>[];
    final playback = _GesturePlaybackService(events);
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
    );
    final controller = ConversationController(
      audioInput: input,
      playbackService: playback,
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
    );

    await controller.startRecording();

    expect(events.take(2), <String>['unlock', 'stop']);
    await controller.onPrimaryAction();
    expect(events.where((event) => event == 'unlock').length, 2);
    controller.dispose();
  });

  test(
    'manual Play can use the direct browser gesture path repeatedly',
    () async {
      final playback = _DirectGesturePlaybackService();
      final controller = ConversationController(
        audioInput: _FakeChunkedInput(
          available: true,
          bluetooth: false,
          label: 'Phone',
        ),
        playbackService: playback,
        repository: _FallbackRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
      );
      controller.result = ConversationResult(
        conversationId: 'conversation',
        sessionId: 'session',
        context: PracticeContext.home,
        vietnameseText: 'Đường đi xa lắm.',
        englishText: "It's a long way.",
        audioUri: Uri.parse('https://api.example.com/audio.mp3'),
        processingMode: 'rule',
        textSource: 'phrase_rule',
        audioSource: 'cache',
        asrMode: 'batch_chunks',
        latency: const ConversationLatency(
          asrMs: 1,
          llmMs: 0,
          ttsMs: 0,
          timeToFirstAudioMs: 1,
        ),
      );

      await controller.playResult();
      await controller.playResult();
      await controller.playResult();

      expect(playback.directPlayCount, 3);
      expect(playback.regularPlayCount, 0);
      expect(
        playback.playedUris,
        everyElement(Uri.parse('https://api.example.com/audio.mp3')),
      );
      controller.dispose();
    },
  );

  test('first manual Play recovers after Safari blocks autoplay', () async {
    final playback = _DirectGesturePlaybackService(rejectRegularPlay: true);
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      playbackService: playback,
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
    );
    final audioUri = Uri.parse('https://api.example.com/exact-translation.mp3');
    controller.result = ConversationResult(
      conversationId: 'conversation',
      sessionId: 'session',
      context: PracticeContext.home,
      vietnameseText: 'Đường đi xa lắm.',
      englishText: "It's a long way.",
      audioUri: audioUri,
      processingMode: 'ai',
      textSource: 'faithful_translation',
      audioSource: 'generated',
      asrMode: 'batch_chunks',
      latency: const ConversationLatency(
        asrMs: 1,
        llmMs: 1,
        ttsMs: 1,
        timeToFirstAudioMs: 3,
      ),
    );

    await controller.playResult(reportLatency: true);
    expect(playback.regularPlayCount, 1);
    expect(playback.directPlayCount, 0);

    await controller.playResult();
    expect(playback.directPlayCount, 1);
    expect(playback.playedUris, <Uri>[audioUri, audioUri]);
    controller.dispose();
  });

  test(
    'preferred audio input safely uses phone when BLE is unavailable',
    () async {
      final ble = _FakeChunkedInput(
        available: false,
        bluetooth: true,
        label: 'BLE',
      );
      final phone = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final input = PreferredAudioInput(preferred: ble, fallback: phone);
      final chunks = <List<int>>[];
      final subscription = input.audioChunks.listen(
        (bytes) => chunks.add(bytes.toList()),
      );

      await input.startChunked();
      phone.emit(<int>[1, 2]);
      await input.stop();

      expect(phone.startCount, 1);
      expect(ble.startCount, 0);
      expect(chunks, <List<int>>[
        <int>[1, 2],
      ]);
      await subscription.cancel();
      await input.dispose();
    },
  );

  test(
    'defaults to Cloudflare Batch Chunks without Android streaming',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2, 3, 4],
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
      );

      expect(controller.asrMode, AsrMode.batchChunks);
      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.finalized, isTrue);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'Android streaming start failure records with Cloudflare Batch Chunks',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[5, 6, 7, 8],
      );
      final streaming = _FakeStreamingSpeechInput(failOnStart: true);
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: streaming,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
      );

      await controller.startRecording();
      expect(controller.asrMode, AsrMode.batchChunks);
      expect(controller.phase, ConversationPhase.recording);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(streaming.startCount, 1);
      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[5, 6, 7, 8],
      ]);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'late Android streaming failure switches the next attempt to Batch Chunks',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[21, 22, 23, 24],
      );
      final streaming = _FakeStreamingSpeechInput(failOnStop: true);
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: streaming,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(controller.phase, ConversationPhase.error);
      expect(controller.asrMode, AsrMode.batchChunks);
      expect(repository.realtimeStarted, 0);

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(streaming.startCount, 1);
      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[21, 22, 23, 24],
      ]);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'HFP streaming start failure keeps the route for Batch Chunks',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[9, 10, 11, 12],
      );
      final hfp = _FakeHfpAudioControl();
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: _FakeStreamingSpeechInput(failOnStart: true),
        hfpAudioControl: hfp,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.hfpStreaming,
      );

      await controller.startRecording();
      expect(controller.asrMode, AsrMode.batchChunks);
      expect(hfp.startRouteCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.capture?.isBluetoothInput, isTrue);
      expect(
        repository.batchSession.capture?.inputLabel,
        contains('Tai nghe HFP'),
      );
      expect(hfp.stopRouteCount, 1);
      controller.dispose();
    },
  );

  test(
    'BLE without offline ASR falls back directly to Cloudflare Batch Chunks',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: true,
        label: 'INNOTRIK BLE',
        emitOnStart: <int>[13, 14, 15, 16],
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.deviceStreaming,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test('uncertain BLE intent uses buffered Cloudflare Batch Chunks', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: true,
      label: 'INNOTRIK BLE',
    );
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      offlineIntentRecognizer: _FakeOfflineIntentRecognizer(
        emitHighConfidenceIntent: false,
      ),
      childAge: 6,
      initialAsrMode: AsrMode.deviceStreaming,
    );

    await controller.startRecording();
    input.emit(<int>[17, 18, 19, 20]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(repository.realtimeStarted, 0);
    expect(repository.batchStarted, 1);
    expect(repository.batchSession.chunks, <List<int>>[
      <int>[17, 18, 19, 20],
    ]);
    expect(controller.result?.conversationId, 'batch-result');
    controller.dispose();
  });

  test(
    'Realtime failure replays buffered audio through Batch Chunks',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2, 3, 4],
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.openAiRealtime,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.realtimeStarted, 1);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
      expect(repository.batchSession.finalized, isTrue);
      expect(repository.fullFileUploads, 0);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'recording starts before a slow Realtime connection and preserves order',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2],
      );
      final realtimeCompleter = Completer<RealtimeTranscriptionSession>();
      final repository = _FallbackRepository(
        realtimeCompleter: realtimeCompleter,
      );
      final realtimeSession = _RecordingRealtimeSession();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.openAiRealtime,
      );
      final stopwatch = Stopwatch()..start();

      await controller.startRecording();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(controller.phase, ConversationPhase.recording);
      expect(realtimeSession.chunks, isEmpty);

      realtimeCompleter.complete(realtimeSession);
      await Future<void>.delayed(Duration.zero);
      input.emit(<int>[3, 4]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(realtimeSession.chunks, <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]);
      expect(repository.batchStarted, 0);
      expect(repository.fullFileUploads, 0);
      expect(controller.result?.conversationId, 'stream-result');
      controller.dispose();
    },
  );

  test(
    'Batch recording starts before a slow upload session is created',
    () async {
      final batchCompleter = Completer<BatchChunkUploadSession>();
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2, 3],
      );
      final repository = _FallbackRepository(batchCompleter: batchCompleter);
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
      );

      final starting = controller.startRecording();
      await Future<void>.delayed(Duration.zero);

      expect(input.startCount, 1);
      expect(controller.phase, ConversationPhase.idle);
      batchCompleter.complete(repository.batchSession);
      await starting;

      expect(repository.batchSession.chunks, <List<int>>[
        <int>[1, 2, 3],
      ]);
      expect(controller.phase, ConversationPhase.recording);
      controller.dispose();
    },
  );

  test('short Web utterance keeps the direct WAV upload path', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
      emitOnStart: <int>[1, 2, 3],
    );
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: true,
      adaptiveWebUploadDelay: const Duration(seconds: 2),
    );

    await controller.startRecording();
    await _emitDetectedSpeech(input);
    await controller.stopRecording(manual: true);

    expect(repository.batchStarted, 0);
    expect(repository.fullFileUploads, 1);
    expect(controller.result?.conversationId, 'file-result');
    controller.dispose();
  });

  test(
    'long Web utterance uploads buffered and live chunks in parallel',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2],
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
        adaptiveWebUploadDelay: const Duration(milliseconds: 20),
      );

      await controller.startRecording();
      await _emitDetectedSpeech(input);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      input.emit(<int>[3, 4]);
      await controller.stopRecording(manual: true);

      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]);
      expect(repository.batchSession.finalized, isTrue);
      expect(repository.fullFileUploads, 0);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'Web low-confidence Batch result does not upload the WAV a second time',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2],
      );
      final repository = _FallbackRepository();
      repository.batchSession.finalizeError = const _LowConfidenceFailure();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
        adaptiveWebUploadDelay: const Duration(milliseconds: 20),
      );

      await controller.startRecording();
      await _emitDetectedSpeech(input);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await controller.stopRecording(manual: true);

      expect(repository.batchStarted, 1);
      expect(repository.batchSession.finalized, isTrue);
      expect(repository.batchSession.discarded, isTrue);
      expect(repository.fullFileUploads, 0);
      expect(controller.phase, ConversationPhase.error);
      expect(
        controller.errorMessage,
        'Mình chưa nghe rõ. Con đưa micro lại gần và nói rõ hơn nhé.',
      );
      controller.dispose();
    },
  );

  test('Web technical Batch failure retains the WAV fallback', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
      emitOnStart: <int>[1, 2],
    );
    final repository = _FallbackRepository();
    repository.batchSession.finalizeError = StateError('network failed');
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: true,
      adaptiveWebUploadDelay: const Duration(milliseconds: 20),
    );

    await controller.startRecording();
    await _emitDetectedSpeech(input);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await controller.stopRecording(manual: true);

    expect(repository.batchStarted, 1);
    expect(repository.batchSession.finalized, isTrue);
    expect(repository.batchSession.discarded, isTrue);
    expect(repository.fullFileUploads, 1);
    expect(repository.batchFallbackReason, 'batch_transport_failure');
    expect(controller.result?.conversationId, 'file-result');
    expect(controller.transientMessage, contains('WAV dự phòng'));
    controller.dispose();
  });

  test(
    'processing status advances through ASR, translation, and audio',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[1, 2, 3],
      );
      final resultCompleter = Completer<ConversationResult>();
      final repository = _FallbackRepository(
        audioResultCompleter: resultCompleter,
      );
      final playback = _BlockingPlaybackService();
      final controller = ConversationController(
        audioInput: input,
        playbackService: playback,
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
        adaptiveWebUploadDelay: const Duration(seconds: 2),
      );

      await controller.startRecording();
      await _emitDetectedSpeech(input);
      final stopping = controller.stopRecording(manual: true);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, ConversationPhase.processing);
      expect(
        controller.processingStage,
        ConversationProcessingStage.recognizing,
      );

      await Future<void>.delayed(const Duration(milliseconds: 750));
      expect(
        controller.processingStage,
        ConversationProcessingStage.translating,
      );

      resultCompleter.complete(
        _result(
          'file-result',
          audioUri: Uri.parse('https://api.example.com/result.mp3'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.processingStage,
        ConversationProcessingStage.preparingAudio,
      );
      expect(controller.phase, ConversationPhase.processing);

      playback.completePlay();
      await stopping;
      expect(controller.phase, ConversationPhase.ready);
      controller.dispose();
    },
  );

  test(
    'Web starts Batch immediately then discards it without detected speech',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[0, 0, 0, 0],
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[0, 0, 0, 0],
      ]);

      await controller.stopRecording(manual: true);

      expect(repository.batchSession.discarded, isTrue);
      expect(repository.fullFileUploads, 0);
      expect(controller.result, isNull);
      expect(controller.phase, ConversationPhase.idle);
      expect(controller.transientMessage, contains('chưa nghe rõ'));
      controller.dispose();
    },
  );

  test(
    'exact Android rule starts cached audio before backend finishes',
    () async {
      final streamingResultCompleter = Completer<ConversationResult>();
      final repository = _FallbackRepository(
        streamingResultCompleter: streamingResultCompleter,
      );
      final playback = _DirectGesturePlaybackService();
      final controller = ConversationController(
        audioInput: _FakeChunkedInput(
          available: true,
          bluetooth: false,
          label: 'Phone',
        ),
        streamingSpeechInput: _FakeStreamingSpeechInput(),
        playbackService: playback,
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
      );
      final audioUri = Uri.parse('https://api.example.com/water.mp3');

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stopping = controller.stopRecording(manual: true);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playedUris, <Uri>[audioUri]);
      expect(controller.result, isNull);

      streamingResultCompleter.complete(
        _result('stream-result', audioUri: audioUri),
      );
      await stopping;

      expect(playback.playedUris, <Uri>[audioUri]);
      expect(controller.phase, ConversationPhase.ready);
      controller.dispose();
    },
  );

  test('stop briefly waits for an almost-ready Realtime connection', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
      emitOnStart: <int>[1, 2],
    );
    final realtimeCompleter = Completer<RealtimeTranscriptionSession>();
    final repository = _FallbackRepository(
      realtimeCompleter: realtimeCompleter,
    );
    final realtimeSession = _RecordingRealtimeSession();
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.openAiRealtime,
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        realtimeCompleter.complete(realtimeSession);
      }),
    );
    await controller.stopRecording(manual: true);

    expect(realtimeSession.chunks, <List<int>>[
      <int>[1, 2],
    ]);
    expect(repository.batchStarted, 0);
    expect(controller.result?.conversationId, 'stream-result');
    controller.dispose();
  });

  test(
    'Realtime connection failure uses buffered Batch Chunks at stop',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[7, 8, 9],
      );
      final repository = _FallbackRepository(failRealtimeConnection: true);
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.openAiRealtime,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.batchStarted, 1);
      expect(repository.batchSession.chunks, <List<int>>[
        <int>[7, 8, 9],
      ]);
      expect(repository.fullFileUploads, 0);
      controller.dispose();
    },
  );

  test('stop falls back after the bounded Realtime connection wait', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
      emitOnStart: <int>[4, 5, 6],
    );
    final repository = _FallbackRepository(
      realtimeCompleter: Completer<RealtimeTranscriptionSession>(),
    );
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.openAiRealtime,
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final stopwatch = Stopwatch()..start();
    await controller.stopRecording(manual: true);
    stopwatch.stop();

    expect(
      stopwatch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 450)),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 1200)));
    expect(repository.batchStarted, 1);
    expect(repository.batchSession.chunks, <List<int>>[
      <int>[4, 5, 6],
    ]);
    expect(controller.result?.conversationId, 'batch-result');
    controller.dispose();
  });

  test(
    'preferred audio input falls back when BLE fails during start',
    () async {
      final ble = _FakeChunkedInput(
        available: true,
        bluetooth: true,
        label: 'BLE',
        failOnStart: true,
      );
      final phone = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final input = PreferredAudioInput(preferred: ble, fallback: phone);

      await input.startChunked();

      expect(ble.startCount, 1);
      expect(phone.startCount, 1);
      expect(input.isBluetooth, isFalse);
      await input.cancel();
      await input.dispose();
    },
  );

  test(
    'explicit BLE capture never silently uses the phone microphone',
    () async {
      final ble = _FakeChunkedInput(
        available: true,
        bluetooth: true,
        label: 'BLE',
        failOnStart: true,
      );
      final phone = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final input = PreferredAudioInput(preferred: ble, fallback: phone);

      input.requireBluetoothCaptureOnce();
      await expectLater(input.startChunked(), throwsStateError);

      expect(ble.startCount, 1);
      expect(phone.startCount, 0);
      await input.dispose();
    },
  );

  test('high-confidence BLE intent skips paid Realtime ASR', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: true,
      label: 'INNOTRIK BLE',
    );
    final repository = _FallbackRepository();
    final recognizer = _FakeOfflineIntentRecognizer();
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      offlineIntentRecognizer: recognizer,
      childAge: 6,
    );
    controller.asrMode = AsrMode.androidStreaming;

    await controller.startRecording();
    input.emit(<int>[1, 2, 3, 4]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(repository.realtimeStarted, 0);
    expect(repository.streamingCapture?.asrMode, 'ble_offline_intent');
    expect(repository.streamingCapture?.confidence, 0.95);
    expect(controller.result?.conversationId, 'stream-result');
    controller.dispose();
  });

  test('HFP streaming opens SCO route and reports Bluetooth input', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
    );
    final hfp = _FakeHfpAudioControl();
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: _FakeStreamingSpeechInput(),
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.hfpStreaming,
    );

    await controller.startRecording();
    expect(hfp.startRouteCount, 1);
    expect(controller.phase, ConversationPhase.recording);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(hfp.stopRouteCount, 1);
    expect(repository.streamingCapture?.asrMode, 'hfp_streaming');
    expect(repository.streamingCapture?.isBluetoothInput, isTrue);
    expect(repository.streamingCapture?.inputLabel, contains('Tai nghe HFP'));
    controller.dispose();
  });

  test('browser HFP records with the selected Bluetooth web input', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: true,
      label: 'Mic HFP Web • AirPods',
    );
    final hfp = _FakeHfpAudioControl(usesBrowserAudioInput: true);
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.hfpStreaming,
    );

    await controller.startRecording();
    expect(hfp.startRouteCount, 1);
    expect(input.startCount, 1);
    expect(controller.phase, ConversationPhase.recording);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(hfp.stopRouteCount, 1);
    expect(repository.audioCapture?.isBluetoothInput, isTrue);
    expect(repository.audioCapture?.inputLabel, contains('AirPods'));
    expect(controller.result?.conversationId, 'file-result');
    controller.dispose();
  });
}

class _FakeStreamingSpeechInput implements StreamingSpeechInput {
  _FakeStreamingSpeechInput({
    this.failOnStart = false,
    this.failOnStop = false,
  });

  final bool failOnStart;
  final bool failOnStop;
  int startCount = 0;

  @override
  String get label => 'ASR Android trực tiếp';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    startCount += 1;
    if (failOnStart) {
      throw const StreamingSpeechInputException(
        'Android streaming start failed.',
      );
    }
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    if (failOnStop) {
      throw const StreamingSpeechInputException(
        'Android streaming stop failed.',
      );
    }
    return const StreamingSpeechCapture(
      sourceText: 'Con muốn uống nước',
      duration: Duration(seconds: 1),
      inputLabel: 'ASR Android trực tiếp',
      confidence: 0.9,
      firstResultMs: 120,
      finalAfterStopMs: 30,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl({this.usesBrowserAudioInput = false});

  int startRouteCount = 0;
  int stopRouteCount = 0;

  @override
  final bool usesBrowserAudioInput;

  @override
  BluetoothAudioStatus get status => const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    deviceId: '00:11:22:33:44:55',
    deviceName: 'Tai nghe HFP',
    sampleRate: 16000,
  );

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      const Stream<BluetoothAudioStatus>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> startAudioRoute() async {
    startRouteCount += 1;
  }

  @override
  Future<void> stopAudioRoute() async {
    stopRouteCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeChunkedInput implements ChunkedAudioInput {
  _FakeChunkedInput({
    required this.available,
    required this.bluetooth,
    required this.label,
    this.emitOnStart,
    this.failOnStart = false,
  });

  final bool available;
  final bool bluetooth;
  final List<int>? emitOnStart;
  final bool failOnStart;
  final StreamController<Uint8List> _chunks =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast(sync: true);
  int startCount = 0;

  void emit(List<int> bytes) => _chunks.add(Uint8List.fromList(bytes));

  void emitAmplitude(double dbfs) => _amplitudes.add(dbfs);

  @override
  final String label;

  @override
  bool get isAvailable => available;

  @override
  bool get isBluetooth => bluetooth;

  @override
  Stream<double> get amplitudeDbfs => _amplitudes.stream;

  @override
  Stream<Uint8List> get audioChunks => _chunks.stream;

  @override
  Future<void> start() async {
    startCount += 1;
    if (failOnStart) {
      throw StateError('input start failed');
    }
  }

  @override
  Future<void> startChunked() async {
    startCount += 1;
    if (failOnStart) {
      throw StateError('input start failed');
    }
    final bytes = emitOnStart;
    if (bytes != null) {
      emit(bytes);
    }
  }

  @override
  Future<AudioCapture> stop() async => AudioCapture(
    filePath: 'fake.wav',
    mimeType: 'audio/wav',
    duration: const Duration(seconds: 1),
    inputLabel: label,
    isBluetoothInput: bluetooth,
    initialNoiseRms: null,
    streamHeaderBytes: Uint8List.fromList(<int>[82, 73, 70, 70]),
    streamedAudioBytes: 4,
    recordingSampleRate: 24000,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _chunks.close();
    await _amplitudes.close();
  }
}

Future<void> _emitDetectedSpeech(_FakeChunkedInput input) async {
  input.emitAmplitude(-60);
  await Future<void>.delayed(const Duration(milliseconds: 150));
  input.emitAmplitude(-58);
  await Future<void>.delayed(const Duration(milliseconds: 170));
  input.emitAmplitude(-60);
  input.emitAmplitude(-20);
  await Future<void>.delayed(const Duration(milliseconds: 190));
  input.emitAmplitude(-28);
}

class _FailingRealtimeSession implements RealtimeTranscriptionSession {
  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  void markRecordingStarted(DateTime startedAt) {}

  @override
  void addAudioChunk(Uint8List bytes) {}

  @override
  Future<StreamingSpeechCapture> finalize() {
    throw const _ExpectedRealtimeFailure();
  }

  @override
  Future<void> discard() async {}
}

class _RecordingRealtimeSession implements RealtimeTranscriptionSession {
  final List<List<int>> chunks = <List<int>>[];

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  void markRecordingStarted(DateTime startedAt) {}

  @override
  void addAudioChunk(Uint8List bytes) {
    chunks.add(bytes.toList());
  }

  @override
  Future<StreamingSpeechCapture> finalize() async =>
      const StreamingSpeechCapture(
        sourceText: 'Con muốn uống nước',
        duration: Duration(seconds: 1),
        inputLabel: 'Phone',
        confidence: null,
        firstResultMs: 100,
        finalAfterStopMs: 10,
        asrMode: 'openai_realtime',
      );

  @override
  Future<void> discard() async {}
}

class _ExpectedRealtimeFailure implements Exception {
  const _ExpectedRealtimeFailure();
}

class _RecordingBatchSession implements BatchChunkUploadSession {
  final List<List<int>> chunks = <List<int>>[];
  bool finalized = false;
  bool discarded = false;
  Object? finalizeError;
  AudioCapture? capture;

  @override
  void addAudioChunk(Uint8List bytes) {
    chunks.add(bytes.toList());
  }

  @override
  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    finalized = true;
    this.capture = capture;
    final error = finalizeError;
    if (error != null) {
      throw error;
    }
    return _result('batch-result');
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {
    discarded = true;
  }
}

class _LowConfidenceFailure implements Exception, CodedConversationException {
  const _LowConfidenceFailure();

  @override
  String get message =>
      'Mình chưa nghe rõ. Con đưa micro lại gần và nói rõ hơn nhé.';

  @override
  String get errorCode => 'ASR_LOW_CONFIDENCE';
}

class _FallbackRepository
    implements
        ConversationRepository,
        RealtimeConversationRepository,
        ChunkedConversationRepository,
        OfflineIntentCatalogRepository {
  _FallbackRepository({
    this.realtimeCompleter,
    this.batchCompleter,
    this.audioResultCompleter,
    this.streamingResultCompleter,
    this.failRealtimeConnection = false,
  });

  final Completer<RealtimeTranscriptionSession>? realtimeCompleter;
  final Completer<BatchChunkUploadSession>? batchCompleter;
  final Completer<ConversationResult>? audioResultCompleter;
  final Completer<ConversationResult>? streamingResultCompleter;
  final bool failRealtimeConnection;
  final _RecordingBatchSession batchSession = _RecordingBatchSession();
  int realtimeStarted = 0;
  int batchStarted = 0;
  int fullFileUploads = 0;
  String? batchFallbackReason;
  StreamingSpeechCapture? streamingCapture;
  AudioCapture? audioCapture;

  @override
  Future<OfflineIntentManifest> fetchOfflineIntentManifest() async {
    return OfflineIntentManifest(
      version: 'test',
      sampleRate: 24000,
      policy: const OfflineIntentPolicy(
        confidenceThreshold: 0.88,
        marginThreshold: 0.15,
        stableUpdates: 3,
        earlyFallbackMs: 800,
      ),
      items: <OfflineIntentDefinition>[
        OfflineIntentDefinition(
          id: 'drink_water',
          contexts: const <String>['home'],
          samples: const <String>['Con muốn uống nước'],
          englishText: 'Can I have some water?',
          audioUri: Uri.parse('https://api.example.com/water.mp3'),
        ),
      ],
    );
  }

  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription({
    required String audioInputLabel,
    required bool bluetoothAudioInput,
  }) async {
    realtimeStarted += 1;
    if (failRealtimeConnection) {
      throw StateError('Realtime connection failed');
    }
    final completer = realtimeCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _FailingRealtimeSession();
  }

  @override
  Future<BatchChunkUploadSession> startBatchChunkUpload() async {
    batchStarted += 1;
    final completer = batchCompleter;
    if (completer != null) {
      return completer.future;
    }
    return batchSession;
  }

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    fullFileUploads += 1;
    batchFallbackReason = fallbackReason;
    audioCapture = capture;
    final completer = audioResultCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _result('file-result');
  }

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    streamingCapture = capture;
    final completer = streamingResultCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _result('stream-result');
  }

  @override
  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  }) async => null;

  @override
  Future<void> warmAudioCache() async {}

  @override
  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  }) async => const ConversationLearningOutcome(
    status: 'ok',
    promoted: false,
    useCount: 0,
    threshold: 3,
    message: '',
  );

  @override
  Future<void> patchPlaybackLatency({
    required String conversationId,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
  }) async {}

  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async =>
      <ConversationHistoryItem>[];

  @override
  Future<void> deleteHistoryItem(String conversationId) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeOfflineIntentRecognizer implements OfflineIntentRecognizer {
  _FakeOfflineIntentRecognizer({this.emitHighConfidenceIntent = true});

  final bool emitHighConfidenceIntent;
  final StreamController<OfflineIntentHypothesis> _controller =
      StreamController<OfflineIntentHypothesis>.broadcast(sync: true);

  @override
  Stream<OfflineIntentHypothesis> get hypotheses => _controller.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start({required OfflineIntentManifest manifest}) async {}

  @override
  void addAudioChunk(Uint8List bytes) {
    if (!emitHighConfidenceIntent) {
      return;
    }
    for (var index = 0; index < 3; index += 1) {
      _controller.add(
        const OfflineIntentHypothesis(
          intentId: 'drink_water',
          transcript: 'Con muốn uống nước',
          confidence: 0.95,
          alternatives: <OfflineIntentAlternative>[
            OfflineIntentAlternative(intentId: 'ask_teacher', confidence: 0.2),
          ],
        ),
      );
    }
  }

  @override
  Future<OfflineIntentHypothesis?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
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
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _BlockingPlaybackService implements AudioPlaybackService {
  final Completer<PlaybackStartMetrics> _playCompleter =
      Completer<PlaybackStartMetrics>();

  void completePlay() {
    if (!_playCompleter.isCompleted) {
      _playCompleter.complete(
        const PlaybackStartMetrics(
          audioLoadDuration: Duration.zero,
          startedAfterRequest: Duration.zero,
          fromDeviceCache: false,
        ),
      );
    }
  }

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) => _playCompleter.future;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _GesturePlaybackService
    implements AudioPlaybackService, UserGestureAudioPlaybackService {
  _GesturePlaybackService(this.events);

  final List<String> events;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> unlockForUserGesture() async {
    events.add('unlock');
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {}
}

class _DirectGesturePlaybackService
    implements AudioPlaybackService, DirectUserGestureAudioPlaybackService {
  _DirectGesturePlaybackService({this.rejectRegularPlay = false});

  final bool rejectRegularPlay;
  int directPlayCount = 0;
  int regularPlayCount = 0;
  final List<Uri> playedUris = <Uri>[];

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<PlaybackStartMetrics?> playLoadedForUserGesture(Uri uri) async {
    directPlayCount += 1;
    playedUris.add(uri);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    regularPlayCount += 1;
    playedUris.add(uri);
    if (rejectRegularPlay) {
      throw const PlaybackException('Safari blocked autoplay.');
    }
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

ConversationResult _result(String conversationId, {Uri? audioUri}) =>
    ConversationResult(
      conversationId: conversationId,
      sessionId: 'session',
      context: PracticeContext.home,
      vietnameseText: 'Con muốn uống nước',
      englishText: 'Can I have some water?',
      audioUri: audioUri,
      processingMode: 'rule',
      textSource: 'phrase_rule',
      audioSource: 'cache',
      asrMode: 'batch_chunks',
      latency: const ConversationLatency(
        asrMs: 1,
        llmMs: 1,
        ttsMs: 1,
        timeToFirstAudioMs: 3,
      ),
    );
