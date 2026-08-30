import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/offline_intent_recognizer.dart';
import 'package:ai_speaking_flutter_app/core/audio/preferred_audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/realtime_fallback_buffer.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
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

  test('vocabulary translation uses the backend text pipeline', () async {
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
    );

    final translation = await controller.translateVocabulary('con mèo');

    expect(repository.streamingCapture?.sourceText, 'con mèo');
    expect(repository.streamingCapture?.asrMode, 'text');
    expect(translation.vietnameseText, 'Con muốn uống nước');
    expect(translation.englishText, 'Can I have some water?');
    controller.dispose();
  });

  test('conversation waits for the navigation recognizer handoff', () async {
    var navigationReleased = false;
    final streamingInput = _FakeStreamingSpeechInput(
      onStart: () => expect(navigationReleased, isTrue),
    );
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      streamingSpeechInput: streamingInput,
      playbackService: const _FakePlaybackService(),
      repository: _FallbackRepository(),
      childAge: 6,
      beforeRecordingStart: () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        navigationReleased = true;
      },
    );

    await controller.startRecording();

    expect(streamingInput.startCount, 1);
    expect(controller.phase, ConversationPhase.recording);
    controller.dispose();
  });

  test('parental privacy guard blocks every recording start path', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
    );
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      voiceDataProcessingAllowed: () => false,
    );

    await controller.startRecording();

    expect(input.startCount, 0);
    expect(controller.errorMessage, contains('Phụ huynh cần đồng ý'));
    expect(controller.isRecording, isFalse);
    controller.dispose();
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
        playback.playbackRate,
        ConversationController.translatedSpeechPlaybackRate,
      );
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
      await _emitDetectedSpeech(input);
      await controller.stopRecording(manual: true);

      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 1);
      expect(repository.batchSession.finalized, isTrue);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

  test(
    'Android streaming start failure does not upload audio to Cloudflare',
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
      expect(controller.asrMode, AsrMode.androidStreaming);
      expect(controller.phase, ConversationPhase.error);

      expect(streaming.startCount, 1);
      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 0);
      expect(controller.errorMessage, contains('Chế độ tiêu chuẩn'));
      controller.dispose();
    },
  );

  test(
    'late Android streaming failure keeps the standard recognition mode',
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
      await _emitDetectedSpeech(input);
      await controller.stopRecording(manual: true);

      expect(controller.phase, ConversationPhase.error);
      expect(controller.asrMode, AsrMode.androidStreaming);
      expect(repository.realtimeStarted, 0);

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(streaming.startCount, 2);
      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 0);
      expect(controller.phase, ConversationPhase.error);
      controller.dispose();
    },
  );

  test(
    'spoken learning command bypasses translation and result audio',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[5, 6, 7, 8],
      );
      final streaming = _FakeStreamingSpeechInput(
        sourceText: 'Còn cái gì khác để học không?',
      );
      final repository = _FallbackRepository();
      String? handledCommand;
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: streaming,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        recognizedSpeechCommandMatcher: (text) => text.contains('khác để học'),
        onRecognizedSpeechCommand: (text) async => handledCommand = text,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.streamingCapture, isNull);
      expect(controller.result, isNull);
      expect(controller.phase, ConversationPhase.idle);
      expect(
        controller.lastTurnEndReason,
        ConversationTurnEndReason.commandHandled,
      );
      expect(handledCommand, 'Còn cái gì khác để học không?');
      controller.dispose();
    },
  );

  test(
    'Batch command result is hidden and opens the command handler',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
        emitOnStart: <int>[5, 6, 7, 8],
      );
      final repository = _FallbackRepository();
      repository.batchSession.resultOverride = _result(
        'batch-command',
        vietnameseText: 'Còn cái gì khác để học không?',
        audioUri: Uri.parse('https://api.example.com/should-not-play.mp3'),
      );
      String? handledCommand;
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        recognizedSpeechCommandMatcher: (text) => text.contains('khác để học'),
        onRecognizedSpeechCommand: (text) async => handledCommand = text,
      );

      await controller.startRecording();
      await _emitDetectedSpeech(input);
      await controller.stopRecording(manual: false);

      expect(repository.batchSession.finalized, isTrue);
      expect(controller.result, isNull);
      expect(controller.phase, ConversationPhase.idle);
      expect(
        controller.lastTurnEndReason,
        ConversationTurnEndReason.commandHandled,
      );
      expect(handledCommand, 'Còn cái gì khác để học không?');
      controller.dispose();
    },
  );

  test(
    'HFP source failure does not fall back to Cloudflare audio ASR',
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
      expect(controller.asrMode, AsrMode.androidStreaming);
      expect(hfp.startRouteCount, 1);
      expect(hfp.stopRouteCount, 1);
      expect(controller.phase, ConversationPhase.error);

      expect(repository.realtimeStarted, 0);
      expect(repository.batchStarted, 0);
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
      await _emitDetectedSpeech(input);
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
    await _emitDetectedSpeech(input);
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
      await _emitDetectedSpeech(input);
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

      await _emitDetectedSpeech(input);
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
      await _emitDetectedSpeech(input);

      expect(repository.batchSession.chunks, <List<int>>[
        <int>[1, 2, 3],
      ]);
      expect(controller.phase, ConversationPhase.recording);
      controller.dispose();
    },
  );

  test(
    'short Web utterance promotes buffered audio to Batch at stop',
    () async {
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

      expect(repository.batchStarted, 1);
      expect(repository.fullFileUploads, 0);
      expect(controller.result?.conversationId, 'batch-result');
      controller.dispose();
    },
  );

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
    'Web PCM silence requests terminal preview before recorder stop',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final session = _SpeculativeRecordingBatchSession();
      final batchCompleter = Completer<BatchChunkUploadSession>()
        ..complete(session);
      final repository = _FallbackRepository(batchCompleter: batchCompleter);
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
      );

      await controller.startRecording();
      // Calibrate the PCM detector from actual Raw PCM even if Safari's
      // amplitude callback later stops reporting the silence transition.
      input.emit(_pcm16Chunk(amplitude: 0));
      input.emit(_pcm16Chunk(amplitude: 0));
      await _emitDetectedSpeech(input);
      input.emit(_pcm16Chunk(amplitude: 0.3));
      input.emit(_pcm16Chunk(amplitude: 0));

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(session.terminalPreviewRequests, 1);
      expect(session.voiceInactiveCalls, greaterThan(0));
      expect(session.finalized, isFalse);
      expect(controller.phase, ConversationPhase.recording);

      await controller.stopRecording(manual: true);
      controller.dispose();
    },
  );

  test(
    'short PCM noise after silence does not cancel early terminal preview',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final session = _SpeculativeRecordingBatchSession();
      final repository = _FallbackRepository(
        batchCompleter: Completer<BatchChunkUploadSession>()..complete(session),
      );
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
      );

      await controller.startRecording();
      input.emit(_pcm16Chunk(amplitude: 0));
      input.emit(_pcm16Chunk(amplitude: 0));
      await _emitDetectedSpeech(input);
      input.emit(_pcm16Chunk(amplitude: 0.3));
      input.emit(_pcm16Chunk(amplitude: 0));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // A brief fan click/reverberation used to cancel the 200 ms terminal
      // timer and postpone Worker ASR until recorder.stop().
      input.emitAmplitude(-20);
      input.emit(_pcm16Chunk(amplitude: 0.12, durationMs: 40));
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(session.terminalPreviewRequests, 1);
      expect(controller.phase, ConversationPhase.recording);

      await controller.stopRecording(manual: true);
      expect(session.clientTerminalTelemetry['clientStopReason'], 'manual');
      expect(
        session.clientTerminalTelemetry['clientTerminalRequestedBeforeStopMs'],
        isA<int>(),
      );
      controller.dispose();
    },
  );

  test(
    'confirmed PCM speech resume cancels the stale terminal timer',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final session = _SpeculativeRecordingBatchSession();
      final repository = _FallbackRepository(
        batchCompleter: Completer<BatchChunkUploadSession>()..complete(session),
      );
      final controller = ConversationController(
        audioInput: input,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: true,
      );

      await controller.startRecording();
      input.emit(_pcm16Chunk(amplitude: 0));
      input.emit(_pcm16Chunk(amplitude: 0));
      await _emitDetectedSpeech(input);
      input.emit(_pcm16Chunk(amplitude: 0.3));
      input.emit(_pcm16Chunk(amplitude: 0));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      input.emit(
        Uint8List.fromList(<int>[
          ..._pcm16Chunk(amplitude: 0.08, durationMs: 40),
          ..._pcm16Chunk(amplitude: 0.25, durationMs: 40),
          ..._pcm16Chunk(amplitude: 0.12, durationMs: 40),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));

      // A real resumed phrase must invalidate the stale snapshot so a child is
      // never cut merely to gain terminal lead.
      expect(session.terminalPreviewRequests, 0);

      await controller.stopRecording(manual: true);
      expect(
        session.clientTerminalTelemetry['clientTerminalTimerLastCancelReason'],
        'pcm_confirmed_resume',
      );
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
        'Cô chưa nghe thấy con nói. Con nói lại nhé.',
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

  test('Batch PCM metadata mismatch falls back to the complete WAV', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
      emitOnStart: <int>[1, 2],
    );
    final repository = _FallbackRepository();
    repository.batchSession.finalizeError = const _PcmMetadataFailure();
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

    expect(repository.batchSession.finalized, isTrue);
    expect(repository.batchSession.discarded, isTrue);
    expect(repository.fullFileUploads, 1);
    expect(repository.batchFallbackReason, 'batch_pcm_metadata_mismatch');
    expect(controller.result?.conversationId, 'file-result');
    expect(controller.phase, ConversationPhase.ready);
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
      repository.batchSession.finalizeCompleter = resultCompleter;
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
      await Future<void>.delayed(const Duration(milliseconds: 20));

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
      expect(controller.transientMessage, contains('chưa nghe thấy'));
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

  test(
    'exact Android rule remains usable while backend is unavailable',
    () async {
      final repository = _FallbackRepository(
        streamingError: const _RetryableBackendFailure(),
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
      await Future<void>.delayed(Duration.zero);

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(controller.phase, ConversationPhase.ready);
      expect(controller.result?.vietnameseText, 'Con muốn uống nước');
      expect(controller.result?.englishText, 'Can I have some water?');
      expect(controller.result?.textSource, 'device_exact_rule_fallback');
      expect(controller.result?.conversationId, isEmpty);
      expect(controller.transientMessage, contains('tạm gián đoạn'));
      expect(playback.playedUris, <Uri>[
        Uri.parse('https://api.example.com/water.mp3'),
      ]);
      controller.dispose();
    },
  );

  test(
    'unknown Android sentence shows a friendly backend outage message',
    () async {
      final controller = ConversationController(
        audioInput: _FakeChunkedInput(
          available: true,
          bluetooth: false,
          label: 'Phone',
        ),
        streamingSpeechInput: _FakeStreamingSpeechInput(
          sourceText: 'Hôm nay trời đẹp quá',
        ),
        playbackService: const _FakePlaybackService(),
        repository: _FallbackRepository(
          streamingError: const _RetryableBackendFailure(),
        ),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(controller.phase, ConversationPhase.error);
      expect(
        controller.errorMessage,
        'Dịch vụ đang tạm gián đoạn. Vui lòng thử lại sau.',
      );
      expect(controller.errorMessage, isNot(contains('Mã hỗ trợ')));
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
    await _emitDetectedSpeech(input);
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
      await _emitDetectedSpeech(input);
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
    await _emitDetectedSpeech(input);
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

  test('HFP source uses standard Android ASR and reports Bluetooth', () async {
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
    expect(controller.asrMode, AsrMode.androidStreaming);
    expect(repository.streamingCapture?.asrMode, 'android_streaming');
    expect(repository.streamingCapture?.isBluetoothInput, isTrue);
    expect(repository.streamingCapture?.inputLabel, contains('Tai nghe HFP'));
    controller.dispose();
  });

  test('native iOS HFP prefers Apple Speech and reports Bluetooth', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Mic iPhone',
    );
    final hfp = _FakeHfpAudioControl();
    final repository = _FallbackRepository();
    final recognizer = _FakeIOSStreamingSpeechInput();
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: recognizer,
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
    );

    await controller.connectHfpDevice(
      const HfpAudioDevice(
        id: 'ios-hfp-input',
        name: 'H20 HFP',
        isConnected: true,
      ),
    );
    expect(controller.asrMode, AsrMode.androidStreaming);

    await controller.startRecording();
    expect(hfp.startRouteCount, 1);
    expect(recognizer.startCount, 1);
    expect(input.startCount, 0);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(hfp.stopRouteCount, 1);
    expect(repository.batchStarted, 0);
    expect(repository.streamingCapture?.isBluetoothInput, isTrue);
    expect(controller.result?.conversationId, 'stream-result');
    controller.dispose();
  });

  test('iOS streaming speech exclusively owns the capture HFP lease', () async {
    final hfp = _FakeHfpAudioControl();
    final recognizer = _FakeRouteOwningIOSStreamingSpeechInput(hfp);
    final resultCompleter = Completer<ConversationResult>()
      ..complete(
        _result(
          'stream-result',
          audioUri: Uri.parse('https://api.example.com/result.mp3'),
        ),
      );
    final repository = _FallbackRepository(
      streamingResultCompleter: resultCompleter,
    );
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Mic iPhone',
      ),
      streamingSpeechInput: recognizer,
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
    );

    await controller.connectHfpDevice(
      const HfpAudioDevice(
        id: 'ios-hfp-input',
        name: 'H20 HFP',
        isConnected: true,
      ),
    );
    await controller.startRecording();

    expect(hfp.startRouteCount, 1, reason: 'Only the iOS recognizer opens SCO');

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(
      hfp.startRouteCount,
      2,
      reason: 'Playback obtains a fresh route after recognition releases SCO',
    );
    expect(hfp.stopRouteCount, 2);
    expect(repository.streamingCapture?.isBluetoothInput, isTrue);
    controller.dispose();
  });

  test('audio preparation has a finite failure boundary', () async {
    final playback = _NeverPreparingPlaybackService();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      streamingSpeechInput: _FakeStreamingSpeechInput(
        sourceText: 'Một câu hoàn toàn mới',
      ),
      playbackService: playback,
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      audioPreparationTimeout: const Duration(milliseconds: 25),
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller
        .stopRecording(manual: true)
        .timeout(const Duration(milliseconds: 300));

    expect(controller.phase, ConversationPhase.error);
    expect(controller.errorMessage, contains('chuẩn bị âm thanh'));
    controller.dispose();
  });

  test('MAIN cancellation during HFP start prevents late recording', () async {
    final hfp = _BlockingStartHfpAudioControl();
    final recognizer = _FakeIOSStreamingSpeechInput();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Mic iPhone',
      ),
      streamingSpeechInput: recognizer,
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
    );

    await controller.connectHfpDevice(
      const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
    );
    final starting = controller.startRecording();
    await hfp.startRequested.future;

    final cancellation = await controller.cancelCurrentMainAction();
    hfp.completeStart();
    await starting.timeout(const Duration(milliseconds: 300));

    expect(cancellation, MainButtonActionResult.accepted);
    expect(recognizer.startCount, 0);
    expect(controller.phase, ConversationPhase.idle);
    controller.dispose();
  });

  test('pending HFP cancellation remains busy until native start settles', () async {
    final hfp = _StubbornStartHfpAudioControl();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Mic iPhone',
      ),
      hfpAudioControl: hfp,
      streamingSpeechInput: _FakeIOSStreamingSpeechInput(),
      playbackService: const _FakePlaybackService(),
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      cancellationBarrierTimeout: const Duration(milliseconds: 20),
    );

    await controller.connectHfpDevice(
      const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
    );
    final starting = controller.startRecording();
    await hfp.startRequested.future;

    final cancellation = await controller.cancelCurrentMainAction();

    expect(cancellation, MainButtonActionResult.busy);
    expect(controller.isBusy, isTrue);

    hfp.completeStart();
    await starting.timeout(const Duration(milliseconds: 300));
    expect(controller.isBusy, isFalse);
    controller.dispose();
  });

  test(
    'MAIN cancellation during native start prevents late recording',
    () async {
      final recognizer = _BlockingStartIOSStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: _FakeChunkedInput(
          available: true,
          bluetooth: false,
          label: 'Mic iPhone',
        ),
        streamingSpeechInput: recognizer,
        playbackService: const _FakePlaybackService(),
        repository: _FallbackRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
      );

      final starting = controller.startRecording();
      await recognizer.startRequested.future;
      final cancellation = await controller.cancelCurrentMainAction();
      recognizer.completeStart();
      await starting.timeout(const Duration(milliseconds: 300));

      expect(cancellation, MainButtonActionResult.accepted);
      expect(controller.phase, ConversationPhase.idle);
      controller.dispose();
    },
  );

  test('playback start has a finite failure boundary', () async {
    final playback = _NeverStartingPlaybackService();
    final resultCompleter = Completer<ConversationResult>()
      ..complete(
        _result(
          'stream-result',
          audioUri: Uri.parse('https://api.example.com/result.mp3'),
        ),
      );
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      streamingSpeechInput: _FakeStreamingSpeechInput(
        sourceText: 'Một câu hoàn toàn mới',
      ),
      playbackService: playback,
      repository: _FallbackRepository(
        streamingResultCompleter: resultCompleter,
      ),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      audioPreparationTimeout: const Duration(milliseconds: 25),
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller
        .stopRecording(manual: true)
        .timeout(const Duration(milliseconds: 300));

    expect(controller.phase, ConversationPhase.error);
    expect(controller.errorMessage, contains('chuẩn bị âm thanh'));
    expect(playback.stopCount, greaterThan(0));
    controller.dispose();
  });

  test('early exact-rule playback cannot prepare forever', () async {
    final playback = _NeverStartingPlaybackService();
    final resultCompleter = Completer<ConversationResult>()
      ..complete(
        _result(
          'stream-result',
          audioUri: Uri.parse('https://api.example.com/result.mp3'),
        ),
      );
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      ),
      streamingSpeechInput: _FakeStreamingSpeechInput(
        sourceText: 'Con muốn uống nước',
      ),
      playbackService: playback,
      repository: _FallbackRepository(
        streamingResultCompleter: resultCompleter,
      ),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      audioPreparationTimeout: const Duration(milliseconds: 25),
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller
        .stopRecording(manual: true)
        .timeout(const Duration(milliseconds: 300));

    expect(controller.phase, ConversationPhase.error);
    expect(playback.stopCount, greaterThan(0));
    controller.dispose();
  });

  test('HFP playback route start has a finite failure boundary', () async {
    final hfp = _NeverStartingHfpAudioControl();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Mic iPhone',
      ),
      hfpAudioControl: hfp,
      playbackService: const _FakePlaybackService(),
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      audioPreparationTimeout: const Duration(milliseconds: 25),
    );
    controller.result = _result(
      'result',
      audioUri: Uri.parse('https://api.example.com/result.mp3'),
    );
    await controller.connectHfpDevice(
      const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
    );

    await expectLater(
      controller
          .playResult(reportLatency: true, propagateFailure: true)
          .timeout(const Duration(milliseconds: 300)),
      throwsA(isA<PlaybackException>()),
    );

    expect(controller.transientMessage, contains('H20'));
    expect(hfp.stopRouteCount, 1);
    controller.dispose();
  });

  test('MAIN cancellation blocks a late HFP playback start', () async {
    final hfp = _BlockingStartHfpAudioControl();
    final playback = _RecordingPlaybackService();
    final controller = ConversationController(
      audioInput: _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Mic iPhone',
      ),
      hfpAudioControl: hfp,
      playbackService: playback,
      repository: _FallbackRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      cancellationBarrierTimeout: const Duration(milliseconds: 100),
    );
    controller.result = _result(
      'result',
      audioUri: Uri.parse('https://api.example.com/result.mp3'),
    );
    await controller.connectHfpDevice(
      const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
    );

    final pendingPlayback = controller.playResult();
    await hfp.startRequested.future;
    final cancellation = await controller.cancelCurrentMainAction();
    await pendingPlayback.timeout(const Duration(milliseconds: 300));

    expect(cancellation, MainButtonActionResult.accepted);
    expect(playback.playCount, 0);
    expect(hfp.stopRouteCount, greaterThan(0));
    expect(controller.phase, ConversationPhase.idle);
    controller.dispose();
  });

  test('iOS start failure records with Cloudflare Batch fallback', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Mic iPhone',
    );
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: _FakeIOSStreamingSpeechInput(failOnStart: true),
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
    );

    await controller.startRecording();
    expect(input.startCount, 1);
    expect(controller.asrMode, AsrMode.batchChunks);
    await _emitDetectedSpeech(input);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(repository.batchStarted, greaterThanOrEqualTo(1));
    expect(
      controller.result?.conversationId,
      anyOf('file-result', 'batch-result'),
    );
    controller.dispose();
  });

  test('iOS runtime failure uploads only the private fallback WAV', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Mic iPhone',
    );
    final repository = _FallbackRepository();
    final fallbackCapture = AudioCapture(
      filePath: 'ios-native-fallback.wav',
      mimeType: 'audio/wav',
      duration: const Duration(seconds: 1),
      inputLabel: 'Apple Native Speech',
      isBluetoothInput: false,
      initialNoiseRms: null,
    );
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: _FakeIOSStreamingSpeechInput(
        failOnStop: true,
        fallbackCapture: fallbackCapture,
      ),
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(repository.audioCapture, same(fallbackCapture));
    expect(repository.streamingCapture, isNull);
    expect(controller.asrMode, AsrMode.batchChunks);
    expect(controller.result?.conversationId, 'file-result');
    controller.dispose();
  });

  test(
    'standard Android ASR prefers direct streaming over recorded-audio injection',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final repository = _FallbackRepository();
      final recognizer = _FakeRecordedAudioStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: recognizer,
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(recognizer.startCount, 1);
      expect(recognizer.recordedCapture, isNull);
      expect(input.startCount, 0);
      expect(repository.streamingCapture?.asrMode, 'android_streaming');
      controller.dispose();
    },
  );

  test('recorded Android audio archive remains an explicit opt-in', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
    );
    final repository = _ArchivingFallbackRepository();
    final recognizer = _FakeRecordedAudioStreamingSpeechInput();
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: recognizer,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      recordAndroidAudioForArchive: true,
    );

    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);
    final archived = await repository.archived.future.timeout(
      const Duration(seconds: 1),
    );

    expect(archived.$1.conversationId, 'stream-result');
    expect(archived.$2.filePath, 'fake.wav');
    expect(recognizer.recordedCapture, same(archived.$2));
    expect(input.startCount, 1);
    controller.dispose();
  });

  test(
    'Android injected-audio failure keeps WAV via Cloudflare fallback',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: _FakeRecordedAudioStreamingSpeechInput(
          failRecognition: true,
        ),
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        recordAndroidAudioForArchive: true,
      );

      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.fullFileUploads, 1);
      expect(repository.audioCapture?.filePath, 'fake.wav');
      expect(controller.result?.conversationId, 'file-result');
      controller.dispose();
    },
  );

  test(
    'automatic Android no-match after VAD noise exits as no speech',
    () async {
      final input = _FakeChunkedInput(
        available: true,
        bluetooth: false,
        label: 'Phone',
      );
      final repository = _FallbackRepository();
      final controller = ConversationController(
        audioInput: input,
        streamingSpeechInput: _FakeRecordedAudioStreamingSpeechInput(
          recognitionError: const StreamingSpeechInputException(
            'Mình chưa nghe rõ câu nói.',
            code: 'RECORDED_AUDIO_UNCLEAR',
          ),
        ),
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        recordAndroidAudioForArchive: true,
      );

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
        speakNoSpeechPrompt: false,
      );
      // Simulate background noise crossing the local VAD threshold even though
      // Android ultimately reports that it did not recognize any speech.
      await _emitDetectedSpeech(input);
      await controller.stopRecording(manual: false);

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(controller.errorMessage, isNull);
      expect(controller.result, isNull);
      expect(repository.fullFileUploads, 0);
      expect(repository.batchStarted, 0);
      controller.dispose();
    },
  );

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
      webRuntimeOverride: true,
      adaptiveWebUploadDelay: const Duration(seconds: 8),
    );

    await controller.startRecording();
    expect(hfp.startRouteCount, 1);
    expect(input.startCount, 1);
    expect(controller.phase, ConversationPhase.recording);

    await _emitDetectedSpeech(input);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.stopRecording(manual: true);

    expect(hfp.stopRouteCount, 1);
    expect(controller.asrMode, AsrMode.batchChunks);
    expect(controller.inputLabel, contains('HFP'));
    expect(
      controller.result?.conversationId,
      anyOf('file-result', 'batch-result'),
    );
    controller.dispose();
  });

  test('older Android keeps audio through Cloudflare Batch Chunks', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Phone',
    );
    final repository = _FallbackRepository();
    final controller = ConversationController(
      audioInput: input,
      streamingSpeechInput: _FakeRecordedAudioStreamingSpeechInput(
        supportsRecordedAudio: false,
      ),
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      recordAndroidAudioForArchive: true,
    );

    await controller.startRecording();
    await _emitDetectedSpeech(input);
    await controller.stopRecording(manual: true);

    expect(controller.asrMode, AsrMode.batchChunks);
    expect(repository.batchSession.finalized, isTrue);
    expect(controller.result?.conversationId, 'batch-result');
    controller.dispose();
  });

  test('Safari Worker result archives the complete Web WAV', () async {
    final input = _FakeChunkedInput(
      available: true,
      bluetooth: false,
      label: 'Safari microphone',
    );
    final repository = _ArchivingFallbackRepository();
    repository.batchSession.resultOverride = _result(
      'worker-result',
      asrMode: 'browser_streaming',
    );
    final controller = ConversationController(
      audioInput: input,
      playbackService: const _FakePlaybackService(),
      repository: repository,
      childAge: 6,
      webRuntimeOverride: true,
      adaptiveWebUploadDelay: Duration.zero,
      initialAsrMode: AsrMode.batchChunks,
    );

    await controller.startRecording();
    await _emitDetectedSpeech(input);
    await controller.stopRecording(manual: true);
    final archived = await repository.archived.future.timeout(
      const Duration(seconds: 1),
    );

    expect(archived.$1.asrMode, 'browser_streaming');
    expect(archived.$2.filePath, 'fake.wav');
    controller.dispose();
  });
}

class _FakeStreamingSpeechInput implements StreamingSpeechInput {
  _FakeStreamingSpeechInput({
    this.failOnStart = false,
    this.failOnStop = false,
    this.onStart,
    this.sourceText = 'Con muốn uống nước',
  });

  final bool failOnStart;
  final bool failOnStop;
  final void Function()? onStart;
  final String sourceText;
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
    onStart?.call();
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
    return StreamingSpeechCapture(
      sourceText: sourceText,
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

class _FakeIOSStreamingSpeechInput extends _FakeStreamingSpeechInput
    implements
        BatchFallbackCapableNativeSpeechInput,
        NativeSpeechFallbackAudioProvider {
  _FakeIOSStreamingSpeechInput({
    super.failOnStart,
    super.failOnStop,
    this.fallbackCapture,
  });

  AudioCapture? fallbackCapture;

  @override
  String get label => 'Apple Native Speech';

  @override
  AudioCapture? takeFallbackAudioCapture() {
    final capture = fallbackCapture;
    fallbackCapture = null;
    return capture;
  }
}

class _BlockingStartIOSStreamingSpeechInput
    extends _FakeIOSStreamingSpeechInput {
  final Completer<void> startRequested = Completer<void>();
  final Completer<void> _startCompleter = Completer<void>();

  void completeStart() {
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }

  @override
  Future<void> start() async {
    if (!startRequested.isCompleted) startRequested.complete();
    await _startCompleter.future;
    await super.start();
  }

  @override
  Future<void> cancel() async {
    completeStart();
    await super.cancel();
  }
}

class _FakeRouteOwningIOSStreamingSpeechInput
    extends _FakeIOSStreamingSpeechInput
    implements HfpRouteOwningStreamingSpeechInput {
  _FakeRouteOwningIOSStreamingSpeechInput(this.routeControl);

  final HfpAudioControl routeControl;

  @override
  Future<void> start() async {
    await routeControl.startAudioRoute();
    await super.start();
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    try {
      return await super.stop();
    } finally {
      await routeControl.stopAudioRoute();
    }
  }

  @override
  Future<void> cancel() async {
    await super.cancel();
    await routeControl.stopAudioRoute();
  }
}

class _ArchivingFallbackRepository extends _FallbackRepository
    implements UserAudioArchiveRepository {
  final Completer<(ConversationResult, AudioCapture)> archived =
      Completer<(ConversationResult, AudioCapture)>();

  @override
  Future<void> archiveUserAudio({
    required ConversationResult result,
    required AudioCapture capture,
  }) async {
    if (!archived.isCompleted) {
      archived.complete((result, capture));
    }
  }
}

class _FakeRecordedAudioStreamingSpeechInput extends _FakeStreamingSpeechInput
    implements RecordedAudioStreamingSpeechInput {
  _FakeRecordedAudioStreamingSpeechInput({
    this.failRecognition = false,
    this.supportsRecordedAudio = true,
    this.recognitionError,
  });

  final bool failRecognition;
  final bool supportsRecordedAudio;
  final Object? recognitionError;
  AudioCapture? recordedCapture;

  @override
  Future<bool> supportsRecordedAudioRecognition() async =>
      supportsRecordedAudio;

  @override
  Future<StreamingSpeechCapture> recognizeRecordedAudio(
    AudioCapture capture,
  ) async {
    recordedCapture = capture;
    final error = recognitionError;
    if (error != null) {
      throw error;
    }
    if (failRecognition) {
      throw const StreamingSpeechInputException(
        'Injected audio is unsupported.',
      );
    }
    return StreamingSpeechCapture(
      sourceText: 'Con muốn uống nước',
      duration: capture.duration,
      inputLabel: 'ASR Android trực tiếp',
      confidence: 0.9,
      firstResultMs: 120,
      finalAfterStopMs: 30,
      recordedAudio: capture,
    );
  }
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

class _BlockingStartHfpAudioControl extends _FakeHfpAudioControl {
  final Completer<void> startRequested = Completer<void>();
  final Completer<void> _startCompleter = Completer<void>();

  void completeStart() {
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }

  @override
  Future<void> startAudioRoute() async {
    startRouteCount += 1;
    if (!startRequested.isCompleted) startRequested.complete();
    await _startCompleter.future;
  }

  @override
  Future<void> stopAudioRoute() async {
    await super.stopAudioRoute();
    completeStart();
  }
}

class _StubbornStartHfpAudioControl extends _FakeHfpAudioControl {
  final Completer<void> startRequested = Completer<void>();
  final Completer<void> _startCompleter = Completer<void>();

  void completeStart() {
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }

  @override
  Future<void> startAudioRoute() async {
    startRouteCount += 1;
    if (!startRequested.isCompleted) startRequested.complete();
    await _startCompleter.future;
  }
}

class _NeverStartingHfpAudioControl extends _FakeHfpAudioControl {
  final Completer<void> _startCompleter = Completer<void>();

  @override
  Future<void> startAudioRoute() {
    startRouteCount += 1;
    return _startCompleter.future;
  }

  @override
  Future<void> stopAudioRoute() async {
    await super.stopAudioRoute();
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }
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

Uint8List _pcm16Chunk({required double amplitude, int durationMs = 200}) {
  const sampleRate = 16000;
  final sampleCount = sampleRate * durationMs ~/ 1000;
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  final encoded = (amplitude.clamp(0.0, 1.0) * 32767).round();
  for (var index = 0; index < sampleCount; index += 1) {
    data.setInt16(index * 2, index.isEven ? encoded : -encoded, Endian.little);
  }
  return bytes;
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
  ConversationResult? resultOverride;
  Completer<ConversationResult>? finalizeCompleter;
  AudioCapture? capture;
  int terminalPreviewRequests = 0;
  int speechDetectedCalls = 0;
  int voiceActiveCalls = 0;
  int voiceInactiveCalls = 0;

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
    final completer = finalizeCompleter;
    if (completer != null) {
      return completer.future;
    }
    return resultOverride ?? _result('batch-result');
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {
    discarded = true;
  }
}

class _SpeculativeRecordingBatchSession extends _RecordingBatchSession
    implements SpeculativeBatchChunkUploadSession {
  final StreamController<ConversationPreview> _previews =
      StreamController<ConversationPreview>.broadcast(sync: true);
  final Map<String, dynamic> clientTerminalTelemetry = <String, dynamic>{};

  @override
  Stream<ConversationPreview> get speculativePreviews => _previews.stream;

  @override
  void configureSpeculativePreview({
    required PracticeContext context,
    required int childAge,
  }) {}

  @override
  void markSpeculativeSpeechDetected() {
    speechDetectedCalls += 1;
  }

  @override
  void markSpeculativeVoiceActive() {
    voiceActiveCalls += 1;
  }

  @override
  void markSpeculativeVoiceInactive() {
    voiceInactiveCalls += 1;
  }

  @override
  void updateClientTerminalTelemetry(Map<String, dynamic> telemetry) {
    clientTerminalTelemetry.addAll(telemetry);
  }

  @override
  void requestTerminalSpeculativePreview({bool atRecorderStop = false}) {
    terminalPreviewRequests += 1;
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

class _PcmMetadataFailure implements Exception, CodedConversationException {
  const _PcmMetadataFailure();

  @override
  String get message => 'Thiếu metadata PCM khi finalize Batch Chunks.';

  @override
  String get errorCode => 'AUDIO_SESSION_INVALID';
}

class _RetryableBackendFailure
    implements Exception, RetryableConversationException {
  const _RetryableBackendFailure();

  @override
  bool get isRetryable => true;
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
    this.streamingError,
    this.failRealtimeConnection = false,
  });

  final Completer<RealtimeTranscriptionSession>? realtimeCompleter;
  final Completer<BatchChunkUploadSession>? batchCompleter;
  final Completer<ConversationResult>? audioResultCompleter;
  final Completer<ConversationResult>? streamingResultCompleter;
  final Object? streamingError;
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
    final error = streamingError;
    if (error != null) {
      throw error;
    }
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
    int? responseToPlaybackMs,
    bool? audioPreloadLoadedData,
    bool? audioPreloadCanPlay,
    int? audioPreloadLoadedDataMs,
    int? audioPreloadCanPlayMs,
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

class _NeverPreparingPlaybackService implements AudioPlaybackService {
  final Completer<void> _preparation = Completer<void>();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() => _preparation.future;

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

class _NeverStartingPlaybackService implements AudioPlaybackService {
  final Completer<PlaybackStartMetrics> _playback =
      Completer<PlaybackStartMetrics>();
  int stopCount = 0;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) => _playback.future;

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _RecordingPlaybackService implements AudioPlaybackService {
  int playCount = 0;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCount += 1;
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
    implements
        AudioPlaybackService,
        DirectUserGestureAudioPlaybackService,
        PlaybackRateAwareAudioPlaybackService {
  _DirectGesturePlaybackService({this.rejectRegularPlay = false});

  final bool rejectRegularPlay;
  int directPlayCount = 0;
  int regularPlayCount = 0;
  double playbackRate = 1.0;
  final List<Uri> playedUris = <Uri>[];

  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate;
  }

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

ConversationResult _result(
  String conversationId, {
  Uri? audioUri,
  String asrMode = 'batch_chunks',
  String vietnameseText = 'Con muốn uống nước',
}) => ConversationResult(
  conversationId: conversationId,
  sessionId: 'session',
  context: PracticeContext.home,
  vietnameseText: vietnameseText,
  englishText: 'Can I have some water?',
  audioUri: audioUri,
  processingMode: 'rule',
  textSource: 'phrase_rule',
  audioSource: 'cache',
  asrMode: asrMode,
  latency: const ConversationLatency(
    asrMs: 1,
    llmMs: 1,
    ttsMs: 1,
    timeToFirstAudioMs: 3,
  ),
);
