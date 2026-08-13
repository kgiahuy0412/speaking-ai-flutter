import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
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

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(promptService.spokenTexts, isEmpty);

      await controller.speakAssistantPrompt('tạm biệt con nhé');
      expect(promptService.spokenTexts, <String>['tạm biệt con nhé']);
    },
  );
}

class _SilentAudioInput implements ChunkedAudioInput {
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
  Future<void> cancel() async {}

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

class _FakeVoicePromptService implements VoicePromptService {
  final List<String> spokenTexts = <String>[];

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
