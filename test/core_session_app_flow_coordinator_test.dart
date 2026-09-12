import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/session/app_flow_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pause exposes the stable active learning kind to MAIN', () async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final module = _FakeActiveModule(kind: ActiveLearningModuleKind.vocabulary);
    registry.register(module);
    final coordinator = AppFlowCoordinator(registry: registry);

    final pause = await coordinator.pauseForMainAssistant();

    expect(pause.paused, isTrue);
    expect(pause.hasActiveModule, isTrue);
    expect(pause.activeKind, ActiveLearningModuleKind.vocabulary);
    expect(coordinator.activeModulePausedForMain, isTrue);
    expect(module.pauseCount, 1);
  });

  test('handled command releases MAIN pause ownership', () async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final module = _FakeActiveModule();
    registry.register(module);
    final coordinator = AppFlowCoordinator(registry: registry);
    await coordinator.pauseForMainAssistant();

    final result = await coordinator.execute(ActiveLearningCommand.nextItem);

    expect(result.wasHandled, isTrue);
    expect(coordinator.activeModulePausedForMain, isFalse);
    expect(module.commands, <ActiveLearningCommand>[
      ActiveLearningCommand.nextItem,
    ]);
  });

  test('unhandled command speaks its reply without releasing pause', () async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final module = _FakeActiveModule(
      commandResult: const ActiveLearningCommandResult.unavailable(
        spokenReply: 'Lệnh này chưa dùng được.',
      ),
    );
    registry.register(module);
    final coordinator = AppFlowCoordinator(registry: registry);
    await coordinator.pauseForMainAssistant();
    final replies = <String>[];

    final result = await coordinator.execute(
      ActiveLearningCommand.nextLesson,
      onUnhandledReply: (reply) async => replies.add(reply),
    );

    expect(result.status, ActiveLearningCommandStatus.unavailable);
    expect(replies, <String>['Lệnh này chưa dùng được.']);
    expect(coordinator.activeModulePausedForMain, isTrue);
  });

  test('resume restores the paused module once', () async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final module = _FakeActiveModule();
    registry.register(module);
    final coordinator = AppFlowCoordinator(registry: registry);
    await coordinator.pauseForMainAssistant();

    await coordinator.resumeAfterMainAssistant();
    await coordinator.resumeAfterMainAssistant();

    expect(module.commands, <ActiveLearningCommand>[
      ActiveLearningCommand.resume,
    ]);
    expect(module.isPausedForMain, isFalse);
    expect(coordinator.activeModulePausedForMain, isFalse);
  });

  test('navigation handoff does not resume the lesson being left', () async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final module = _FakeActiveModule();
    registry.register(module);
    final coordinator = AppFlowCoordinator(registry: registry);
    await coordinator.pauseForMainAssistant();

    coordinator.forgetPausedModule();
    await coordinator.resumeAfterMainAssistant();

    expect(module.commands, isEmpty);
    expect(module.isPausedForMain, isTrue);
    expect(coordinator.activeModulePausedForMain, isFalse);
  });
}

class _FakeActiveModule implements ActiveLearningModuleController {
  _FakeActiveModule({
    this.kind = ActiveLearningModuleKind.listeningLesson,
    this.commandResult = const ActiveLearningCommandResult.handled(),
  });

  final ActiveLearningModuleKind kind;
  final ActiveLearningCommandResult commandResult;
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
    if (command == ActiveLearningCommand.resume && commandResult.wasHandled) {
      paused = false;
    }
    return commandResult;
  }
}
