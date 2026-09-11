import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/coordinated_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes prompts from different feature owners', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final lessonDelegate = _BlockingPromptService();
    final mainDelegate = _BlockingPromptService();
    final lesson = CoordinatedVoicePromptService(
      delegate: lessonDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );
    final main = CoordinatedVoicePromptService(
      delegate: mainDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
    );

    final lessonPrompt = lesson.speakAndWait('Lesson prompt');
    await lessonDelegate.started.future;
    final mainPrompt = main.speakAndWait('MAIN prompt');
    await Future<void>.delayed(Duration.zero);
    expect(mainDelegate.startCalls, 0);

    lessonDelegate.finish();
    await lessonPrompt;
    await mainDelegate.started.future;
    expect(mainDelegate.startCalls, 1);
    mainDelegate.finish();
    await mainPrompt;
  });

  test('stopping an old prompt cannot stop the next owner', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final oldDelegate = _BlockingPromptService();
    final nextDelegate = _BlockingPromptService();
    final oldPrompt = CoordinatedVoicePromptService(
      delegate: oldDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );
    final nextPrompt = CoordinatedVoicePromptService(
      delegate: nextDelegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.mainAssistant,
    );

    final oldOperation = oldPrompt.speakAndWait('Old');
    await oldDelegate.started.future;
    await oldPrompt.stop();
    await oldOperation;

    final nextOperation = nextPrompt.speakAndWait('Next');
    await nextDelegate.started.future;
    await oldPrompt.dispose();
    expect(nextDelegate.stopCalls, 0);
    nextDelegate.finish();
    await nextOperation;
  });

  test('forwards selected-output and ready-cue capabilities', () async {
    final coordinator = AudioTurnCoordinator();
    addTearDown(coordinator.dispose);
    final delegate = _CapabilityPromptService();
    final service = CoordinatedVoicePromptService(
      delegate: delegate,
      coordinator: coordinator,
      owner: AudioTurnOwner.listeningLesson,
    );

    await service.speakAndWaitOnSelectedMediaOutput('English', locale: 'en-US');
    await service.playSpeechReadyCue();

    expect(delegate.selectedPrompts, <String>['en-US|English']);
    expect(delegate.readyCueCalls, 1);
  });
}

class _BlockingPromptService implements VoicePromptService {
  Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();
  int startCalls = 0;
  int stopCalls = 0;

  void finish() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    startCalls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    await _completion.future;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}

class _CapabilityPromptService
    implements
        VoicePromptService,
        SelectedMediaOutputVoicePromptService,
        SpeechReadyCuePlayer {
  final List<String> selectedPrompts = <String>[];
  int readyCueCalls = 0;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    selectedPrompts.add('$locale|$text');
  }

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCalls += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
