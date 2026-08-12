import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'navigation transcript is handled without entering conversation',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        ownsSpeechInput: true,
      );
      VoiceNavigationIntent? receivedIntent;
      controller.setIntentHandler((intent) {
        receivedIntent = intent;
      });

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isFalse,
      );
      expect(receivedIntent, isNull);

      expect(await controller.dispatchRecognizedText('Hey Pico'), isTrue);
      expect(voicePrompt.spokenTexts, <String>['Pipo nghe đây']);
      expect(controller.isAwaitingCommand, isTrue);

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isTrue,
      );
      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );

      receivedIntent = null;
      expect(
        await controller.dispatchRecognizedText('Con muốn uống nước'),
        isFalse,
      );
      expect(receivedIntent, isNull);
      controller.dispose();
    },
  );

  test(
    'pauses navigation recognizer before conversation can reuse it',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        ownsSpeechInput: true,
      );

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.isListening, isTrue);

      await controller.pause();
      await speechInput.start();

      expect(speechInput.events, <String>['start', 'cancel', 'start']);
      expect(controller.isActive, isFalse);
      controller.dispose();
    },
  );

  test('handles an explicit command from a stable partial result', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitPartial('Hey Pico');
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(voicePrompt.spokenTexts, <String>['Pipo nghe đây']);
    expect(controller.isAwaitingCommand, isTrue);
    expect(controller.isListening, isTrue);

    speechInput.emitPartial('Tu vung');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(receivedIntents, isEmpty);

    speechInput.emitPartial('Con muon hoc tu vung');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(receivedIntents, hasLength(1));
    expect(
      speechInput.events.where((event) => event == 'cancel'),
      hasLength(2),
    );
    speechInput.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(receivedIntents, hasLength(1));
    expect(
      receivedIntents.single.destination,
      VoiceNavigationDestination.vocabulary,
    );
    controller.dispose();
    await speechInput.dispose();
  });

  test('returns to wake-word mode when the command window expires', () async {
    final controller = VoiceNavigationController(
      speechInput: _FakeNavigationSpeechInput(),
      voicePromptService: _FakeVoicePromptService(),
      commandWindowDuration: const Duration(milliseconds: 5),
    );

    expect(await controller.dispatchRecognizedText('Hey Pico'), isTrue);
    expect(controller.isAwaitingCommand, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(controller.isAwaitingCommand, isFalse);
    expect(
      await controller.dispatchRecognizedText('Con muon hoc tu vung'),
      isFalse,
    );
    controller.dispose();
  });

  test(
    'does not reopen the microphone until the wake reply finishes',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _BlockingVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        partialIntentDebounce: const Duration(milliseconds: 1),
      );

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      speechInput.emitPartial('Hey Pico');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isAcknowledgingWakeWord, isTrue);
      expect(controller.isListening, isFalse);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(1),
      );

      voicePrompt.complete();
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(controller.isAcknowledgingWakeWord, isFalse);
      expect(controller.isAwaitingCommand, isTrue);
      expect(controller.isListening, isTrue);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(2),
      );
      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'pause waits for a pending navigation start to release the mic',
    () async {
      final speechInput = _DelayedNavigationSpeechInput();
      final controller = VoiceNavigationController(speechInput: speechInput);

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.isStarting, isTrue);

      var pauseCompleted = false;
      final pauseFuture = controller.pause().then((_) => pauseCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(pauseCompleted, isFalse);

      speechInput.releaseStart();
      await pauseFuture;
      await speechInput.start();
      await Future<void>.delayed(const Duration(milliseconds: 2));

      expect(speechInput.events, <String>[
        'start.begin',
        'cancel',
        'start.end',
        'cancel',
        'start.begin',
        'start.end',
      ]);
      expect(controller.isActive, isFalse);
      controller.dispose();
      await speechInput.dispose();
    },
  );
}

class _FakeNavigationSpeechInput implements StreamingSpeechInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final List<String> events = <String>[];

  void emitPartial(String text) => _partialTextController.add(text);

  void emitCompleted() => _completedController.add(null);

  @override
  String get label => 'Navigation ASR';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    events.add('start');
  }

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn học từ vựng',
    duration: Duration(seconds: 1),
    inputLabel: 'Navigation ASR',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
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

class _BlockingVoicePromptService extends _FakeVoicePromptService {
  final Completer<void> _completion = Completer<void>();

  void complete() => _completion.complete();

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await super.speak(text, locale: locale);
    await _completion.future;
  }
}

class _DelayedNavigationSpeechInput implements StreamingSpeechInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final Completer<void> _firstStartGate = Completer<void>();
  final List<String> events = <String>[];
  var _startCount = 0;

  void releaseStart() => _firstStartGate.complete();

  @override
  String get label => 'Delayed navigation ASR';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    _startCount += 1;
    events.add('start.begin');
    if (_startCount == 1) {
      await _firstStartGate.future;
    }
    events.add('start.end');
  }

  @override
  Future<StreamingSpeechCapture> stop() {
    throw UnimplementedError();
  }

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
}
