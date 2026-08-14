import 'dart:async';

import 'package:flutter/widgets.dart';

/// The small, shared command surface exposed by whichever learning module is
/// currently visible.
///
/// Detailed lesson/vocabulary scripts remain inside their owning feature. The
/// global MAIN assistant only asks the active module to pause, resume, or move
/// at well-defined boundaries.
enum ActiveLearningCommand {
  resume,
  replayCurrent,
  nextItem,
  previousItem,
  nextLesson,
  previousLesson,
  restart,
  stop,
}

enum ActiveLearningModuleKind { listeningLesson, vocabulary }

enum ActiveLearningCommandStatus { handled, unavailable, busy }

class ActiveLearningCommandResult {
  const ActiveLearningCommandResult._(this.status, this.spokenReply);

  const ActiveLearningCommandResult.handled({String? spokenReply})
    : this._(ActiveLearningCommandStatus.handled, spokenReply);

  const ActiveLearningCommandResult.unavailable({String? spokenReply})
    : this._(ActiveLearningCommandStatus.unavailable, spokenReply);

  const ActiveLearningCommandResult.busy({String? spokenReply})
    : this._(ActiveLearningCommandStatus.busy, spokenReply);

  final ActiveLearningCommandStatus status;
  final String? spokenReply;

  bool get wasHandled => status == ActiveLearningCommandStatus.handled;
}

abstract interface class ActiveLearningModuleController {
  ActiveLearningModuleKind get moduleKind;

  /// Stops audio/recording immediately but preserves the exact learning
  /// position so MAIN can ask for a command without destroying the route.
  Future<void> pauseForMainAssistant();

  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  );
}

/// One microphone owner and one active learning owner at a time.
///
/// Screens register on mount and unregister on dispose. A token prevents an
/// older route from accidentally removing the newer route during replacement.
class ActiveLearningModuleRegistry extends ChangeNotifier {
  ActiveLearningModuleController? _controller;
  Object? _ownerToken;

  ActiveLearningModuleController? get controller => _controller;
  bool get hasActiveModule => _controller != null;
  ActiveLearningModuleKind? get activeKind => _controller?.moduleKind;

  Object register(ActiveLearningModuleController controller) {
    final token = Object();
    _controller = controller;
    _ownerToken = token;
    notifyListeners();
    return token;
  }

  void unregister(Object token) {
    if (!identical(token, _ownerToken)) {
      return;
    }
    _controller = null;
    _ownerToken = null;
    notifyListeners();
  }

  Future<bool> pauseForMainAssistant() async {
    final active = _controller;
    if (active == null) {
      return false;
    }
    await active.pauseForMainAssistant();
    return identical(active, _controller);
  }

  Future<ActiveLearningCommandResult> execute(
    ActiveLearningCommand command,
  ) async {
    final active = _controller;
    if (active == null) {
      return const ActiveLearningCommandResult.unavailable();
    }
    return active.handleMainCommand(command);
  }
}

class ActiveLearningModuleScope
    extends InheritedNotifier<ActiveLearningModuleRegistry> {
  const ActiveLearningModuleScope({
    required ActiveLearningModuleRegistry registry,
    required super.child,
    super.key,
  }) : super(notifier: registry);

  static ActiveLearningModuleRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ActiveLearningModuleScope>()
      ?.notifier;
}
