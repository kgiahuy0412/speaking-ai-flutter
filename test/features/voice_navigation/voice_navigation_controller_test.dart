import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
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
      expect(voicePrompt.readyCueCount, 1);
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

  test('Main button speaks the menu then starts the speaking flow', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
    );
    VoiceNavigationIntent? receivedIntent;
    controller.setIntentHandler((intent) => receivedIntent = intent);

    expect(
      await controller.activateFromMainButton(
        inputLabelOverride: 'Mic iPhone (giữ BLE H20)',
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 520));

    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
    ]);
    expect(voicePrompt.readyCueCount, 1);
    expect(controller.isAwaitingCommand, isTrue);
    expect(controller.isListening, isTrue);
    expect(controller.activeInputLabel, 'Mic iPhone (giữ BLE H20)');
    expect(
      await controller.dispatchRecognizedText('Con ghi muốn luyện nói'),
      isTrue,
    );
    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
      'Con nói từng câu nhé. Muốn dừng thì nói dừng lại.',
    ]);
    expect(
      receivedIntent?.destination,
      VoiceNavigationDestination.conversation,
    );
    expect(receivedIntent?.enterMainSpeakingMode, isTrue);
    expect(controller.continuousRequested, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'Main opens the microphone when the native ready cue never completes',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _HangingReadyCueVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        speechReadyCueTimeout: const Duration(milliseconds: 5),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 520));

      expect(voicePrompt.readyCueCount, 1);
      expect(controller.isAwaitingCommand, isTrue);
      expect(controller.isListening, isTrue);
      expect(
        speechInput.events.where((event) => event == 'start'),
        hasLength(1),
      );

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main command window starts only after the microphone is ready',
    () async {
      final speechInput = _DelayedNavigationSpeechInput();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        commandWindowDuration: const Duration(milliseconds: 15),
        microphoneStartTimeout: const Duration(seconds: 2),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 530));

      expect(controller.isStarting, isTrue);
      expect(controller.isAwaitingCommand, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.isAwaitingCommand, isTrue);

      speechInput.releaseStart();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      expect(controller.isListening, isTrue);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'HFP speech activity extends MAIN command window before transcript',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 250),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      speechInput.emitSpeechStarted();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(controller.isListening, isTrue);
      expect(controller.isAwaitingCommand, isTrue);
      expect(
        voicePrompt.spokenTexts,
        isNot(contains(MainVoiceAssistantFlow.noSpeechRetryPrompt)),
      );

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main retries a failed microphone start after the start future clears',
    () async {
      final speechInput = _FailingNavigationSpeechInput(failuresRemaining: 1);
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        microphoneStartRetryDelay: const Duration(milliseconds: 2),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 550));

      expect(speechInput.startCount, 2);
      expect(controller.isListening, isTrue);
      expect(controller.lastError, isNull);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main pauses its command deadline while a premature completion recovers',
    () async {
      final speechInput = _FakeNavigationSpeechInput(stopText: '');
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 200),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => controller.isListening);
      expect(controller.isListening, isTrue);

      speechInput.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.isMainButtonSessionActive, isTrue);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
      ]);

      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main stops automatic retries and exposes the microphone error',
    () async {
      final speechInput = _FailingNavigationSpeechInput(failuresRemaining: 10);
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: _FakeVoicePromptService(),
        microphoneStartRetryDelay: const Duration(milliseconds: 2),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 570));

      expect(speechInput.startCount, 3);
      expect(controller.isMainButtonSessionActive, isFalse);
      expect(controller.continuousRequested, isFalse);
      expect(controller.lastErrorMessage, contains('Không mở được micro'));

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('Main activation never exposes a transient inactive session', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: _FakeVoicePromptService(),
    );
    var exposedInactiveSession = false;
    controller.addListener(() {
      if (!controller.isMainButtonSessionActive && !controller.isActive) {
        exposedInactiveSession = true;
      }
    });

    expect(
      await controller.activateFromMainButton(activeLearning: true),
      isTrue,
    );

    expect(exposedInactiveSession, isFalse);
    expect(controller.isMainButtonSessionActive, isTrue);
    controller.dispose();
    await speechInput.dispose();
  });

  test('Main button keeps listening through age, topic and lesson', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    expect(await controller.activateFromMainButton(), isTrue);
    expect(
      await controller.dispatchRecognizedText('Con muốn học theo chủ đề'),
      isTrue,
    );
    expect(await controller.dispatchRecognizedText('Con 6 tuổi'), isTrue);
    expect(
      await controller.dispatchRecognizedText('Con muốn học chủ đề số 3'),
      isTrue,
    );

    expect(receivedIntents, hasLength(1));
    expect(receivedIntents.single.childAge, 6);
    expect(receivedIntents.single.topicNumber, 3);
    expect(controller.isMainButtonSessionActive, isTrue);
    expect(await controller.dispatchRecognizedText('Con học bài số 1'), isTrue);

    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.openingPrompt,
      'Con mấy tuổi',
      'Có 10 chủ đề. Con muốn học chủ đề số mấy',
      'Có 2 bài học. Con muốn học bài số mấy',
      'Bắt đầu học thôi con',
    ]);
    expect(receivedIntents, hasLength(2));
    expect(receivedIntents.last.childAge, 6);
    expect(receivedIntents.last.topicNumber, 3);
    expect(receivedIntents.last.lessonNumber, 1);
    expect(receivedIntents.last.openLesson, isTrue);
    expect(controller.isMainButtonSessionActive, isFalse);
    expect(controller.continuousRequested, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'saved age lets MAIN go directly from feature to topic number',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        mainAssistantFlow: MainVoiceAssistantFlow(
          contentLoader: _loadMainAssistantContent,
        ),
        restartDelay: const Duration(milliseconds: 1),
      );
      final receivedIntents = <VoiceNavigationIntent>[];
      controller.setIntentHandler(receivedIntents.add);
      controller.setChildAge(6);

      expect(await controller.activateFromMainButton(), isTrue);
      expect(
        await controller.dispatchRecognizedText('Con muốn học theo chủ đề'),
        isTrue,
      );

      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
        'Có 10 chủ đề. Con muốn học chủ đề số mấy',
      ]);
      expect(voicePrompt.spokenTexts, isNot(contains('Con mấy tuổi')));

      expect(
        await controller.dispatchRecognizedText('Con muốn học chủ đề số 3'),
        isTrue,
      );
      expect(receivedIntents.single.childAge, 6);
      expect(receivedIntents.single.topicNumber, 3);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('completed topic prompt continues through topic and lesson', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: _loadMainAssistantContent,
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    final receivedIntents = <VoiceNavigationIntent>[];
    controller.setIntentHandler(receivedIntents.add);

    expect(
      await controller.activateTopicSelectionAfterCompletion(
        childAge: 6,
        completedTopicNumbers: const <int>[3, 5],
      ),
      isTrue,
    );
    expect(voicePrompt.spokenTexts, <String>[
      'Có 10 chủ đề. Con muốn học chủ đề số mấy',
    ]);
    expect(controller.isMainButtonSessionActive, isTrue);

    expect(
      await controller.dispatchRecognizedText('Con chọn chủ đề số 3'),
      isTrue,
    );
    expect(receivedIntents, isEmpty);
    expect(
      voicePrompt.spokenTexts.last,
      'Chủ đề số 3 con đã học rồi. Con có muốn học lại không?',
    );

    expect(await controller.dispatchRecognizedText('Có'), isTrue);
    expect(receivedIntents.single.topicNumber, 3);
    expect(
      voicePrompt.spokenTexts.last,
      'Có 2 bài học. Con muốn học bài số mấy',
    );

    expect(await controller.dispatchRecognizedText('Bài số 1'), isTrue);
    expect(receivedIntents.last.openLesson, isTrue);
    expect(receivedIntents.last.lessonNumber, 1);
    expect(voicePrompt.spokenTexts.last, 'Bắt đầu học thôi con');

    controller.dispose();
    await speechInput.dispose();
  });

  test('speaking command opens the other-learning voice menu', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      mainAssistantFlow: MainVoiceAssistantFlow(
        vocabularyLoader: () async => const <VocabularyEntry>[],
      ),
      restartDelay: const Duration(milliseconds: 1),
    );
    VoiceNavigationIntent? receivedIntent;
    controller.setIntentHandler((intent) => receivedIntent = intent);

    expect(await controller.activateOtherLearningFromSpeaking(), isTrue);
    expect(voicePrompt.spokenTexts, <String>[
      MainVoiceAssistantFlow.otherLearningPrompt,
    ]);
    expect(controller.isAwaitingCommand, isTrue);

    expect(
      await controller.dispatchRecognizedText('Con muốn học từ vựng'),
      isTrue,
    );
    expect(
      voicePrompt.spokenTexts.last,
      'Con muốn luyện lại hay nghe những ngôi sao của con?',
    );
    expect(receivedIntent?.destination, VoiceNavigationDestination.vocabulary);
    expect(controller.isMainButtonSessionActive, isTrue);

    expect(await controller.dispatchRecognizedText('Luyện lại'), isTrue);
    expect(voicePrompt.spokenTexts, contains('Phần luyện lại chưa có từ nào.'));
    expect(controller.isMainButtonSessionActive, isFalse);

    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'Main reads parent vocabulary in the correct language sequence',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final introducedIds = <String>[];
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        mainAssistantFlow: MainVoiceAssistantFlow(
          vocabularyLoader: () async => <VocabularyEntry>[
            VocabularyEntry(
              id: 'parent-cat',
              word: 'Cat',
              meaning: 'Con mèo',
              addedAt: DateTime(2026, 8, 18),
            ),
          ],
          vocabularyIntroducedMarker: (ids) async => introducedIds.addAll(ids),
        ),
      );
      VoiceNavigationIntent? receivedIntent;
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(await controller.activateFromMainButton(), isTrue);
      expect(await controller.dispatchRecognizedText('Học từ mới'), isTrue);

      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      final englishIndex = voicePrompt.spokenTexts.indexOf('Cat');
      expect(englishIndex, greaterThanOrEqualTo(0));
      expect(voicePrompt.spokenLocales[englishIndex], 'en-US');
      expect(voicePrompt.spokenTexts, contains('Con mèo'));
      expect(introducedIds, <String>['parent-cat']);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'active lesson Main next answer advances through the module bridge',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.activeLearningPrompt,
      ]);
      expect(await controller.dispatchRecognizedText('Câu tiếp theo'), isTrue);
      expect(voicePrompt.spokenTexts.last, 'Mình học câu tiếp theo nhé');
      expect(receivedCommand, ActiveLearningCommand.nextItem);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'active lesson Main previous answer moves back through the module bridge',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(await controller.dispatchRecognizedText('Nghe câu trước'), isTrue);
      expect(voicePrompt.spokenTexts.last, 'Mình nghe lại câu trước nhé');
      expect(receivedCommand, ActiveLearningCommand.previousItem);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'active lesson Main dispatches the remaining D07 and D08 commands',
    () async {
      const cases = <String, ActiveLearningCommand>{
        'Nghe lại': ActiveLearningCommand.replayCurrent,
        'Học lại từ đầu': ActiveLearningCommand.restart,
        'Bài tiếp theo': ActiveLearningCommand.nextLesson,
        'Bài trước': ActiveLearningCommand.previousLesson,
      };

      for (final entry in cases.entries) {
        final speechInput = _FakeNavigationSpeechInput();
        final voicePrompt = _FakeVoicePromptService();
        ActiveLearningCommand? receivedCommand;
        final controller = VoiceNavigationController(
          speechInput: speechInput,
          voicePromptService: voicePrompt,
          activeLearningCommandHandler: (command) async {
            receivedCommand = command;
            return const ActiveLearningCommandResult.handled();
          },
        );

        expect(
          await controller.activateFromMainButton(activeLearning: true),
          isTrue,
          reason: entry.key,
        );
        expect(
          await controller.dispatchRecognizedText(entry.key),
          isTrue,
          reason: entry.key,
        );
        expect(receivedCommand, entry.value, reason: entry.key);
        expect(
          controller.isMainButtonSessionActive,
          isFalse,
          reason: entry.key,
        );

        controller.dispose();
        await speechInput.dispose();
      }
    },
  );

  test(
    'active lesson exit choice keeps listening then opens vocabulary',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      ActiveLearningCommand? receivedCommand;
      VoiceNavigationIntent? receivedIntent;
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        activeLearningCommandHandler: (command) async {
          receivedCommand = command;
          return const ActiveLearningCommandResult.handled();
        },
      );
      controller.setIntentHandler((intent) => receivedIntent = intent);

      expect(
        await controller.activateFromMainButton(activeLearning: true),
        isTrue,
      );
      expect(
        await controller.dispatchRecognizedText('Con không muốn học nữa'),
        isTrue,
      );
      expect(
        voicePrompt.spokenTexts.last,
        MainVoiceAssistantFlow.alternativeAfterLearningPrompt,
      );
      expect(controller.isMainButtonSessionActive, isTrue);
      expect(receivedCommand, isNull);

      expect(
        await controller.dispatchRecognizedText('Con muốn học từ vựng'),
        isTrue,
      );
      expect(
        receivedIntent?.destination,
        VoiceNavigationDestination.vocabulary,
      );
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
    },
  );

  test(
    'Main asks once after silence then exits on the second timeout',
    () async {
      final speechInput = _FakeNavigationSpeechInput();
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        commandWindowDuration: const Duration(milliseconds: 8),
        restartDelay: const Duration(milliseconds: 1),
      );

      expect(await controller.activateFromMainButton(), isTrue);
      await _waitUntil(() => voicePrompt.spokenTexts.length >= 2);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
        MainVoiceAssistantFlow.noSpeechRetryPrompt,
      ]);
      expect(controller.isMainButtonSessionActive, isTrue);

      await _waitUntil(() => voicePrompt.spokenTexts.length >= 3);
      expect(voicePrompt.spokenTexts, <String>[
        MainVoiceAssistantFlow.openingPrompt,
        MainVoiceAssistantFlow.noSpeechRetryPrompt,
        MainVoiceAssistantFlow.noSpeechExitPrompt,
      ]);
      expect(voicePrompt.readyCueCount, 2);
      expect(controller.isMainButtonSessionActive, isFalse);

      controller.dispose();
      await speechInput.dispose();
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

  test('hears the wake phrase from a secondary Android transcript', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final voicePrompt = _FakeVoicePromptService();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: voicePrompt,
      restartDelay: const Duration(milliseconds: 1),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitAlternatives(<String>['Thời tiết hôm nay', 'Hay Bi Cô']);
    await Future<void>.delayed(const Duration(milliseconds: 140));

    expect(voicePrompt.spokenTexts, <String>['Pipo nghe đây']);
    expect(controller.isAwaitingCommand, isTrue);
    await controller.pause();
    controller.dispose();
    await speechInput.dispose();
  });

  test(
    'uses final Android alternatives when the primary text misses',
    () async {
      final speechInput = _FakeNavigationSpeechInput(
        stopText: 'Thời tiết hôm nay',
        stopAlternatives: const <String>['Thời tiết hôm nay', 'Hey Pico'],
      );
      final voicePrompt = _FakeVoicePromptService();
      final controller = VoiceNavigationController(
        speechInput: speechInput,
        voicePromptService: voicePrompt,
        restartDelay: const Duration(milliseconds: 1),
      );

      controller.startContinuous();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      speechInput.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(voicePrompt.spokenTexts, <String>['Pipo nghe đây']);
      expect(controller.isAwaitingCommand, isTrue);
      await controller.pause();
      controller.dispose();
      await speechInput.dispose();
    },
  );

  test('returns to wake-word mode when the command window expires', () async {
    final speechInput = _FakeNavigationSpeechInput();
    final controller = VoiceNavigationController(
      speechInput: speechInput,
      voicePromptService: _FakeVoicePromptService(),
      commandWindowDuration: const Duration(milliseconds: 30),
      partialIntentDebounce: const Duration(milliseconds: 1),
    );

    controller.startContinuous();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    speechInput.emitPartial('Hey Pico');
    await Future<void>.delayed(const Duration(milliseconds: 115));
    expect(controller.isAwaitingCommand, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(controller.isAwaitingCommand, isFalse);
    expect(
      await controller.dispatchRecognizedText('Con muon hoc tu vung'),
      isFalse,
    );
    controller.dispose();
    await speechInput.dispose();
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
        speechInput.diagnosticStages,
        containsAllInOrder(<String>[
          'prompt_done',
          'microphone_start_requested',
          'microphone_listening',
        ]),
      );
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

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the expected navigation state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<ListeningContentCatalog> _loadMainAssistantContent() async {
  return const ListeningContentCatalog(
    groups: <ListeningContentAgeGroup>[
      ListeningContentAgeGroup(
        startAge: 6,
        endAge: 7,
        topics: <ListeningTopicContent>[
          ListeningTopicContent(
            id: 'a067_t03',
            number: 3,
            titleVi: 'Cặp sách và lớp học',
            titleEn: 'School Bag and Classroom',
            lessons: <ListeningLessonContent>[
              ListeningLessonContent(
                id: 'lesson-1',
                number: 1,
                titleVi: 'Đồ dùng học tập',
                titleEn: 'School Supplies',
                intro: '',
                outro: '',
                estimatedMinutes: 3,
                sentences: <ListeningSentenceContent>[],
              ),
              ListeningLessonContent(
                id: 'lesson-2',
                number: 2,
                titleVi: 'Trong lớp học',
                titleEn: 'In the Classroom',
                intro: '',
                outro: '',
                estimatedMinutes: 3,
                sentences: <ListeningSentenceContent>[],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _FakeNavigationSpeechInput
    implements
        StreamingSpeechInput,
        SpeechActivityStreamingSpeechInput,
        AlternativeTranscriptStreamingSpeechInput,
        NativeSpeechDiagnostics {
  _FakeNavigationSpeechInput({
    this.stopText = 'Con muốn học từ vựng',
    this.stopAlternatives = const <String>[],
  });

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _speechStartedController =
      StreamController<void>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _alternativeTextController =
      StreamController<List<String>>.broadcast();
  final StreamController<NativeSpeechDiagnostic> _diagnosticsController =
      StreamController<NativeSpeechDiagnostic>.broadcast();
  final List<String> events = <String>[];
  final List<String> diagnosticStages = <String>[];
  final String stopText;
  final List<String> stopAlternatives;
  NativeSpeechDiagnostic? _nativeDiagnostic;

  void emitPartial(String text) => _partialTextController.add(text);

  void emitAlternatives(List<String> alternatives) =>
      _alternativeTextController.add(alternatives);

  void emitCompleted() => _completedController.add(null);

  void emitSpeechStarted() => _speechStartedController.add(null);

  @override
  String get label => 'Navigation ASR';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get speechStarted => _speechStartedController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Stream<List<String>> get transcriptAlternatives =>
      _alternativeTextController.stream;

  @override
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic => _nativeDiagnostic;

  @override
  Stream<NativeSpeechDiagnostic> get nativeSpeechDiagnostics =>
      _diagnosticsController.stream;

  @override
  void reportNativeSpeechStage(
    String stage, {
    String? audioSource,
    String? audioRoute,
    String? code,
    String? message,
  }) {
    diagnosticStages.add(stage);
    _nativeDiagnostic = NativeSpeechDiagnostic(
      stage: stage,
      occurredAt: DateTime.now(),
      audioSource: audioSource,
      audioRoute: audioRoute,
      code: code,
      message: message,
    );
    _diagnosticsController.add(_nativeDiagnostic!);
  }

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    events.add('start');
  }

  @override
  Future<StreamingSpeechCapture> stop() async => StreamingSpeechCapture(
    sourceText: stopText,
    duration: const Duration(seconds: 1),
    inputLabel: 'Navigation ASR',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
    alternatives: stopAlternatives,
  );

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _speechStartedController.close();
    await _completedController.close();
    await _partialTextController.close();
    await _alternativeTextController.close();
    await _diagnosticsController.close();
  }
}

class _FakeVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  final List<String> spokenTexts = <String>[];
  final List<String> spokenLocales = <String>[];
  int readyCueCount = 0;

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCount += 1;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
    spokenLocales.add(locale);
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

class _HangingReadyCueVoicePromptService extends _FakeVoicePromptService {
  final Completer<void> _neverCompletes = Completer<void>();

  @override
  Future<void> playSpeechReadyCue() {
    readyCueCount += 1;
    return _neverCompletes.future;
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

class _FailingNavigationSpeechInput extends _FakeNavigationSpeechInput {
  _FailingNavigationSpeechInput({required this.failuresRemaining});

  int failuresRemaining;
  int startCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
    events.add('start');
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const StreamingSpeechInputException(
        'Không mở được micro thử nghiệm.',
        code: 'TEST_MICROPHONE_START_FAILED',
      );
    }
  }
}
