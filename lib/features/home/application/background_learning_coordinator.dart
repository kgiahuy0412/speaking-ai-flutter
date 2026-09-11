import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/platform/background_learning_session.dart';
import '../../listening/data/active_listening_session_store.dart';

enum BackgroundLearningDirective { keepVoiceNavigation, pauseVoiceNavigation }

typedef BackgroundLearningDirectiveHandler =
    void Function(BackgroundLearningDirective directive);

/// Coordinates platform background eligibility and durable lesson recovery.
///
/// Feature sessions still own their prompt, capture, and progress state. This
/// coordinator only translates OS lifecycle/session events into typed keep or
/// pause decisions and restores the smallest safe listening checkpoint once.
class BackgroundLearningCoordinator {
  BackgroundLearningCoordinator({
    required BackgroundLearningSessionControl session,
    required AppLifecycleState initialLifecycleState,
    required BackgroundLearningDirectiveHandler onDirective,
    ActiveListeningSessionStore checkpointStore =
        const ActiveListeningSessionStore(),
    bool? isWeb,
    TargetPlatform? targetPlatform,
  }) : _session = session,
       _checkpointStore = checkpointStore,
       _lifecycleState = initialLifecycleState,
       _onDirective = onDirective,
       _isWeb = isWeb ?? kIsWeb,
       _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  final BackgroundLearningSessionControl _session;
  final ActiveListeningSessionStore _checkpointStore;
  final BackgroundLearningDirectiveHandler _onDirective;
  final bool _isWeb;
  final TargetPlatform _targetPlatform;

  StreamSubscription<BackgroundLearningEvent>? _subscription;
  AppLifecycleState _lifecycleState;
  bool _active = false;
  bool _starting = false;
  bool _microphoneRequiresVisibleResume = false;
  bool _checkpointHandled = false;
  bool _disposed = false;

  bool get isActive => _active;
  bool get isForeground => _lifecycleState == AppLifecycleState.resumed;

  Future<void> initialize({required bool voiceAccessEnabled}) async {
    await ensureStarted(voiceAccessEnabled: voiceAccessEnabled);
  }

  Future<void> updateVoiceAccess(bool enabled) async {
    if (_disposed) return;
    if (enabled) {
      await ensureStarted(voiceAccessEnabled: true);
      return;
    }
    _active = false;
    _microphoneRequiresVisibleResume = false;
    await _session.stop();
  }

  BackgroundLearningDirective handleLifecycle(
    AppLifecycleState state, {
    required bool voiceAccessEnabled,
    required bool explicitMainSessionActive,
  }) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      if (_microphoneRequiresVisibleResume) {
        _microphoneRequiresVisibleResume = false;
        _active = false;
      }
      unawaited(ensureStarted(voiceAccessEnabled: voiceAccessEnabled));
      return BackgroundLearningDirective.keepVoiceNavigation;
    }

    // Android keeps only an explicitly-started MAIN command microphone alive;
    // it never revives the old always-on wake-word loop in background.
    if (!_isWeb && _targetPlatform == TargetPlatform.android) {
      if (_active && voiceAccessEnabled && explicitMainSessionActive) {
        return BackgroundLearningDirective.keepVoiceNavigation;
      }
      return BackgroundLearningDirective.pauseVoiceNavigation;
    }

    if (state == AppLifecycleState.detached) {
      _active = false;
      unawaited(_session.stop());
    } else if (_active && voiceAccessEnabled) {
      return BackgroundLearningDirective.keepVoiceNavigation;
    }
    return BackgroundLearningDirective.pauseVoiceNavigation;
  }

  Future<void> ensureStarted({required bool voiceAccessEnabled}) async {
    if (_disposed || !voiceAccessEnabled || _active || _starting || _isWeb) {
      return;
    }
    _starting = true;
    _subscription ??= _session.events.listen(_handleEvent);
    final active = await _session.start();
    _starting = false;
    if (_disposed) {
      if (active && (_isWeb || _targetPlatform != TargetPlatform.android)) {
        await _session.stop();
      }
      return;
    }
    _active = active;
    if (active) {
      _onDirective(BackgroundLearningDirective.keepVoiceNavigation);
    }
  }

  bool canKeepMainListeningInBackground({
    required bool voiceAccessEnabled,
    required bool explicitMainSessionActive,
  }) {
    return _active && voiceAccessEnabled && explicitMainSessionActive;
  }

  Future<ActiveListeningSessionCheckpoint?> takeListeningCheckpoint({
    required bool voiceAccessEnabled,
  }) async {
    if (_checkpointHandled ||
        !voiceAccessEnabled ||
        _isWeb ||
        (_targetPlatform != TargetPlatform.android &&
            _targetPlatform != TargetPlatform.iOS) ||
        !isForeground) {
      return null;
    }
    _checkpointHandled = true;
    return _checkpointStore.read();
  }

  Future<void> clearListeningCheckpoint() => _checkpointStore.clear();

  Future<void> setActiveLearning(bool active) async {
    final session = _session;
    if (session is ActiveLearningBackgroundSessionControl) {
      await (session as ActiveLearningBackgroundSessionControl)
          .setActiveLearning(active);
    }
  }

  void _handleEvent(BackgroundLearningEvent event) {
    if (_disposed) return;
    if (event.type == BackgroundLearningEventType.resumable) {
      _active = true;
      _microphoneRequiresVisibleResume =
          event.reason == 'microphone_requires_visible_resume';
      _onDirective(BackgroundLearningDirective.keepVoiceNavigation);
      return;
    }
    _active = false;
    _microphoneRequiresVisibleResume = false;
    _onDirective(BackgroundLearningDirective.pauseVoiceNavigation);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    if (_isWeb || _targetPlatform != TargetPlatform.android) {
      unawaited(_session.stop());
    }
  }
}
