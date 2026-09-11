import '../device/active_learning_module.dart';

typedef AppFlowSpokenReply = Future<void> Function(String text);

class MainLearningPause {
  const MainLearningPause({
    required this.paused,
    required this.hasActiveModule,
    required this.activeKind,
  });

  final bool paused;
  final bool hasActiveModule;
  final ActiveLearningModuleKind? activeKind;
}

/// Typed boundary between MAIN navigation and the currently visible learning
/// module.
///
/// It does not contain lesson or vocabulary business rules. Those remain in
/// the registered module and are reached only through [ActiveLearningCommand].
class AppFlowCoordinator {
  AppFlowCoordinator({required ActiveLearningModuleRegistry registry})
    : _registry = registry;

  final ActiveLearningModuleRegistry _registry;
  bool _activeModulePausedForMain = false;
  bool _resumingActiveModule = false;

  bool get hasActiveModule => _registry.hasActiveModule;
  bool get activeModulePausedForMain => _activeModulePausedForMain;
  ActiveLearningModuleKind? get activeKind => _registry.activeKind;

  Future<MainLearningPause> pauseForMainAssistant() async {
    final hadActiveModule = _registry.hasActiveModule;
    var kind = _registry.activeKind;
    if (!hadActiveModule) {
      return MainLearningPause(
        paused: false,
        hasActiveModule: false,
        activeKind: kind,
      );
    }

    _activeModulePausedForMain = await _registry.pauseForMainAssistant();
    final stableActiveModule =
        _activeModulePausedForMain && _registry.hasActiveModule;
    kind = stableActiveModule ? _registry.activeKind : null;
    return MainLearningPause(
      paused: _activeModulePausedForMain,
      hasActiveModule: stableActiveModule,
      activeKind: kind,
    );
  }

  Future<ActiveLearningCommandResult> execute(
    ActiveLearningCommand command, {
    AppFlowSpokenReply? onUnhandledReply,
  }) async {
    ActiveLearningCommandResult result;
    try {
      result = await _registry.execute(command);
    } catch (_) {
      result = const ActiveLearningCommandResult.busy(
        spokenReply: 'Bi cô chưa thực hiện được. Con thử lại nhé.',
      );
    }
    if (result.wasHandled) {
      _activeModulePausedForMain = false;
    } else {
      final reply = result.spokenReply?.trim();
      if (reply != null && reply.isNotEmpty) {
        await onUnhandledReply?.call(reply);
      }
    }
    return result;
  }

  Future<void> resumeAfterMainAssistant() async {
    if (!_activeModulePausedForMain || _resumingActiveModule) return;
    _resumingActiveModule = true;
    try {
      final result = await _registry.execute(ActiveLearningCommand.resume);
      if (result.wasHandled ||
          !_registry.hasActiveModule ||
          !_registry.isActiveModulePaused) {
        _activeModulePausedForMain = false;
      }
    } catch (_) {
      // Keep the paused marker so a later assistant state change can retry.
    } finally {
      _resumingActiveModule = false;
    }
  }

  void forgetPausedModule() {
    _activeModulePausedForMain = false;
  }
}
