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
  vocabularyPracticeAgain,
  vocabularyStars,
  stop,
  exitToHome,
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

  /// Whether the visible learning activity is currently paused by MAIN.
  bool get isPausedForMain;

  /// Stops audio/recording immediately but preserves the exact learning
  /// position so MAIN can ask for a command without destroying the route.
  Future<void> pauseForMainAssistant();

  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  );
}

/// One microphone owner and one visible learning owner at a time.
///
/// Learning routes can temporarily stack (for example, the review route sits
/// above the practice route). The last registered route receives MAIN commands;
/// removing it restores the route immediately below it.
class ActiveLearningModuleRegistry extends ChangeNotifier {
  final List<_ActiveLearningModuleRegistration> _registrations =
      <_ActiveLearningModuleRegistration>[];
  bool _notificationScheduled = false;

  ActiveLearningModuleController? get controller =>
      _registrations.lastOrNull?.controller;
  bool get hasActiveModule => controller != null;
  bool get isActiveModulePaused => controller?.isPausedForMain ?? false;
  ActiveLearningModuleKind? get activeKind => controller?.moduleKind;

  Object register(ActiveLearningModuleController controller) {
    final token = Object();
    _registrations.add(
      _ActiveLearningModuleRegistration(controller: controller, token: token),
    );
    _notifySafely();
    return token;
  }

  void unregister(Object token) {
    final index = _registrations.indexWhere(
      (registration) => identical(registration.token, token),
    );
    if (index < 0) {
      return;
    }
    final wasActive = index == _registrations.length - 1;
    _registrations.removeAt(index);
    if (wasActive) {
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (_notificationScheduled) {
      return;
    }
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  Future<bool> pauseForMainAssistant() async {
    final active = controller;
    if (active == null) {
      return false;
    }
    await active.pauseForMainAssistant();
    return identical(active, controller);
  }

  Future<ActiveLearningCommandResult> execute(
    ActiveLearningCommand command,
  ) async {
    final active = controller;
    if (active == null) {
      return const ActiveLearningCommandResult.unavailable();
    }
    return active.handleMainCommand(command);
  }
}

class _ActiveLearningModuleRegistration {
  const _ActiveLearningModuleRegistration({
    required this.controller,
    required this.token,
  });

  final ActiveLearningModuleController controller;
  final Object token;
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
