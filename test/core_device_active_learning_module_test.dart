import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry keeps the newest route active', () async {
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

  test(
    'registry restores the route below after the top route closes',
    () async {
      final registry = ActiveLearningModuleRegistry();
      final practice = _FakeActiveModule();
      final review = _FakeActiveModule();

      final practiceToken = registry.register(practice);
      final reviewToken = registry.register(review);

      expect(registry.controller, same(review));
      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(review.pauses, 1);
      expect(practice.pauses, 0);

      registry.unregister(reviewToken);
      expect(registry.controller, same(practice));
      expect(await registry.pauseForMainAssistant(), isTrue);
      expect(practice.pauses, 1);

      registry.unregister(practiceToken);
      expect(registry.hasActiveModule, isFalse);
      registry.dispose();
    },
  );
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
