import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Main speaking turn waits for its configured no-speech timeout',
    () async {
      final promptService = _FakeVoicePromptService();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        playbackService: const _FakePlaybackService(),
        voicePromptService: promptService,
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);

      await controller.startRecording(
        noSpeechTimeout: const Duration(milliseconds: 550),
        speakNoSpeechPrompt: false,
      );
      expect(controller.isRecording, isTrue);
      expect(promptService.readyCueCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(promptService.spokenTexts, isEmpty);

      await controller.speakAssistantPrompt('tạm biệt con nhé');
      expect(promptService.spokenTexts, <String>['tạm biệt con nhé']);
    },
  );

  test('long MAIN cancels a single sentence without translating it', () async {
    final audioInput = _SilentAudioInput();
    final promptService = _FakeVoicePromptService();
    final controller = ConversationController(
      audioInput: audioInput,
      playbackService: const _FakePlaybackService(),
      voicePromptService: promptService,
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await controller.startRecording(
      noSpeechTimeout: const Duration(seconds: 10),
    );
    expect(controller.isRecording, isTrue);

    final result = await controller.cancelSingleSentenceMainAction();

    expect(result, MainButtonActionResult.accepted);
    expect(controller.phase, ConversationPhase.idle);
    expect(
      controller.lastTurnEndReason,
      ConversationTurnEndReason.commandHandled,
    );
    expect(audioInput.cancelCount, 1);
    expect(promptService.spokenTexts, isEmpty);
  });

  test(
    'manual MAIN stop asks the child to retry when Android reports no speech',
    () async {
      final promptService = _FakeVoicePromptService();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: const _NoSpeechStreamingSpeechInput(),
        playbackService: const _FakePlaybackService(),
        voicePromptService: promptService,
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(promptService.spokenTexts, <String>[
        'Chưa nghe rõ, con vui lòng nói rõ hơn nhé.',
      ]);
    },
  );

  test('D10 long MAIN stops active playback immediately', () async {
    final playback = _ControllablePlaybackService();
    final controller = ConversationController(
      audioInput: _SilentAudioInput(),
      playbackService: playback,
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await playback.play(Uri.parse('https://example.com/result.mp3'));
    final result = await controller.cancelCurrentMainAction();

    expect(result, MainButtonActionResult.accepted);
    expect(playback.stopCount, 1);
    expect(controller.phase, ConversationPhase.idle);
  });

  test('long MAIN suppresses a translation already processing', () async {
    final controller = ConversationController(
      audioInput: _SilentAudioInput(),
      streamingSpeechInput: const _ImmediateStreamingSpeechInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await controller.startRecording(
      noSpeechTimeout: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final stopFuture = controller.stopRecording(manual: true);
    for (var attempt = 0; attempt < 50; attempt += 1) {
      if (controller.phase == ConversationPhase.processing) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.phase, ConversationPhase.processing);

    final cancelResult = await controller.cancelSingleSentenceMainAction();
    expect(cancelResult, MainButtonActionResult.accepted);
    expect(controller.phase, ConversationPhase.idle);

    await stopFuture;
    expect(controller.phase, ConversationPhase.idle);
    expect(controller.result, isNull);
  });
}

class _SilentAudioInput implements ChunkedAudioInput {
  int cancelCount = 0;

  @override
  String get label => 'Mic kiểm thử';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> startChunked() async {}

  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic kiểm thử',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {}
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

class _ControllablePlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int stopCount = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    _playing.add(true);
    await Future<void>.delayed(Duration.zero);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _playing.add(false);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await _playing.close();
  }
}

class _FakeVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  final List<String> spokenTexts = <String>[];
  int readyCueCount = 0;

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCount += 1;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _ImmediateStreamingSpeechInput implements StreamingSpeechInput {
  const _ImmediateStreamingSpeechInput();

  @override
  String get label => 'ASR Android kiểm thử';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn đi công viên',
    duration: Duration(seconds: 1),
    inputLabel: 'ASR Android kiểm thử',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _NoSpeechStreamingSpeechInput implements StreamingSpeechInput {
  const _NoSpeechStreamingSpeechInput();

  @override
  String get label => 'ASR Android im lặng';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async {
    throw const StreamingSpeechInputException(
      'Không nghe thấy giọng nói.',
      code: 'ANDROID_SPEECH_7',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
