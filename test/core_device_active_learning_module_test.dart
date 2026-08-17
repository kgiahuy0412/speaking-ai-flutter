import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry keeps the newest route as the only active module', () async {
    final registry = ActiveLearningModuleRegistry();
    final first = _FakeActiveModule();
    final second = _FakeActiveModule();

    final firstToken = registry.register(first);
    final secondToken = registry.register(second);
    registry.unregister(firstToken);

    expect(registry.controller, same(second));
    expect(await registry.pauseForMainAssistant(), isTrue);
    expect(second.pauses, 1);
    expect(first.pauses, 0);
    expect(registry.isActiveModulePaused, isTrue);

    final result = await registry.execute(ActiveLearningCommand.resume);
    expect(result.wasHandled, isTrue);
    expect(registry.isActiveModulePaused, isFalse);
    expect(second.commands, <ActiveLearningCommand>[
      ActiveLearningCommand.resume,
    ]);

    registry.unregister(secondToken);
    expect(registry.hasActiveModule, isFalse);
    registry.dispose();
  });
}

class _FakeActiveModule implements ActiveLearningModuleController {
  int pauses = 0;
  bool paused = false;
  final List<ActiveLearningCommand> commands = <ActiveLearningCommand>[];

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => paused;

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    commands.add(command);
    if (command == ActiveLearningCommand.stop) {
      paused = true;
    } else if (command == ActiveLearningCommand.resume) {
      paused = false;
    }
    return const ActiveLearningCommandResult.handled();
  }

  @override
  Future<void> pauseForMainAssistant() async {
    pauses += 1;
    paused = true;
  }
}
