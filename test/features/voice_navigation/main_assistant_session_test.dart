import 'dart:async';

import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/session/app_flow_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_assistant_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects MAIN while conversation owns audio outside learning', () async {
    final harness = _SessionHarness();
    addTearDown(harness.dispose);
    var activationCalls = 0;

    final activated = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: true,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        activationCalls += 1;
        return true;
      },
    );

    expect(activated, isFalse);
    expect(activationCalls, 0);
    expect(harness.activationStates, isEmpty);
  });

  test('pauses learning before activating MAIN with typed context', () async {
    final module = _FakeActiveModule(kind: ActiveLearningModuleKind.vocabulary);
    final harness = _SessionHarness(module: module);
    addTearDown(harness.dispose);
    final events = <String>[];

    final activated = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: true,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        events.add('activate');
        expect(module.isPausedForMain, isTrue);
        expect(activeLearning, isTrue);
        expect(activeLearningKind, ActiveLearningModuleKind.vocabulary);
        return true;
      },
    );

    expect(activated, isTrue);
    expect(module.pauseCount, 1);
    expect(events, <String>['activate']);
    expect(harness.activationStates, <bool>[true, false]);
  });

  test(
    'failed MAIN activation resumes the interrupted learning module',
    () async {
      final module = _FakeActiveModule();
      final harness = _SessionHarness(module: module);
      addTearDown(harness.dispose);

      final activated = await harness.session.activate(
        startupReady: true,
        voiceAccessEnabled: true,
        conversationBusy: false,
        assistantFlowBusy: false,
        canContinue: () => true,
        activateVoice: ({required activeLearning, activeLearningKind}) async {
          return false;
        },
      );

      expect(activated, isFalse);
      expect(module.commands, <ActiveLearningCommand>[
        ActiveLearningCommand.resume,
      ]);
      expect(module.isPausedForMain, isFalse);
    },
  );

  test('serializes repeated MAIN activation attempts', () async {
    final harness = _SessionHarness();
    addTearDown(harness.dispose);
    final gate = Completer<bool>();
    var activationCalls = 0;

    final first = harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: false,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) {
        activationCalls += 1;
        return gate.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    final second = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: false,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        activationCalls += 1;
        return true;
      },
    );

    expect(second, isFalse);
    expect(activationCalls, 1);
    gate.complete(true);
    expect(await first, isTrue);
    expect(harness.activationStates, <bool>[true, false]);
  });
}

class _SessionHarness {
  _SessionHarness({_FakeActiveModule? module})
    : registry = ActiveLearningModuleRegistry() {
    if (module != null) registry.register(module);
    coordinator = AppFlowCoordinator(registry: registry);
    session = MainAssistantSession(
      appFlowCoordinator: coordinator,
      onActivationChanged: activationStates.add,
    );
  }

  final ActiveLearningModuleRegistry registry;
  late final AppFlowCoordinator coordinator;
  late final MainAssistantSession session;
  final List<bool> activationStates = <bool>[];

  void dispose() => registry.dispose();
}

class _FakeActiveModule implements ActiveLearningModuleController {
  _FakeActiveModule({this.kind = ActiveLearningModuleKind.listeningLesson});

  final ActiveLearningModuleKind kind;
  int pauseCount = 0;
  bool paused = false;
  final List<ActiveLearningCommand> commands = <ActiveLearningCommand>[];

  @override
  ActiveLearningModuleKind get moduleKind => kind;

  @override
  bool get isPausedForMain => paused;

  @override
  Future<void> pauseForMainAssistant() async {
    pauseCount += 1;
    paused = true;
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    commands.add(command);
    if (command == ActiveLearningCommand.resume) paused = false;
    return const ActiveLearningCommandResult.handled();
  }
}
