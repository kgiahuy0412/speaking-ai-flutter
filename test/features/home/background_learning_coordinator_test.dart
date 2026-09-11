import 'dart:async';

import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:ai_speaking_flutter_app/features/home/application/background_learning_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/active_listening_session_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Android keeps only an explicit MAIN microphone in background',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final directives = <BackgroundLearningDirective>[];
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: directives.add,
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(voiceAccessEnabled: true);

      expect(
        coordinator.handleLifecycle(
          AppLifecycleState.paused,
          voiceAccessEnabled: true,
          explicitMainSessionActive: false,
        ),
        BackgroundLearningDirective.pauseVoiceNavigation,
      );
      expect(
        coordinator.handleLifecycle(
          AppLifecycleState.paused,
          voiceAccessEnabled: true,
          explicitMainSessionActive: true,
        ),
        BackgroundLearningDirective.keepVoiceNavigation,
      );
      expect(session.stopCount, 0);
    },
  );

  test('native interruption and resume become typed directives', () async {
    final session = _FakeBackgroundSession();
    addTearDown(session.dispose);
    final directives = <BackgroundLearningDirective>[];
    final coordinator = BackgroundLearningCoordinator(
      session: session,
      initialLifecycleState: AppLifecycleState.resumed,
      onDirective: directives.add,
      isWeb: false,
      targetPlatform: TargetPlatform.android,
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize(voiceAccessEnabled: true);

    session.emit(
      const BackgroundLearningEvent(
        type: BackgroundLearningEventType.interrupted,
        reason: 'audio_focus_loss',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.emit(
      const BackgroundLearningEvent(
        type: BackgroundLearningEventType.resumable,
        reason: 'audio_session_interruption_ended',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(directives, <BackgroundLearningDirective>[
      BackgroundLearningDirective.keepVoiceNavigation,
      BackgroundLearningDirective.pauseVoiceNavigation,
      BackgroundLearningDirective.keepVoiceNavigation,
    ]);
  });

  test(
    'visible resume restarts a session that cannot open mic in background',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.paused,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(voiceAccessEnabled: true);
      session.emit(
        const BackgroundLearningEvent(
          type: BackgroundLearningEventType.resumable,
          reason: 'microphone_requires_visible_resume',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      coordinator.handleLifecycle(
        AppLifecycleState.resumed,
        voiceAccessEnabled: true,
        explicitMainSessionActive: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(session.startCount, 2);
    },
  );

  test(
    'restores one listening checkpoint only after iOS is foreground',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await const ActiveListeningSessionStore().save(
        childAge: 8,
        topicNumber: 2,
        lessonNumber: 3,
      );
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.paused,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(coordinator.dispose);

      expect(
        await coordinator.takeListeningCheckpoint(voiceAccessEnabled: true),
        isNull,
      );
      coordinator.handleLifecycle(
        AppLifecycleState.resumed,
        voiceAccessEnabled: true,
        explicitMainSessionActive: false,
      );
      final checkpoint = await coordinator.takeListeningCheckpoint(
        voiceAccessEnabled: true,
      );

      expect(checkpoint?.childAge, 8);
      expect(checkpoint?.topicNumber, 2);
      expect(checkpoint?.lessonNumber, 3);
      expect(
        await coordinator.takeListeningCheckpoint(voiceAccessEnabled: true),
        isNull,
      );
    },
  );

  test(
    'forwards active-learning wake ownership without owning audio',
    () async {
      final session = _FakeBackgroundSession();
      addTearDown(session.dispose);
      final coordinator = BackgroundLearningCoordinator(
        session: session,
        initialLifecycleState: AppLifecycleState.resumed,
        onDirective: (_) {},
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(coordinator.dispose);

      await coordinator.setActiveLearning(true);
      await coordinator.setActiveLearning(false);

      expect(session.activeLearningValues, <bool>[true, false]);
    },
  );
}

class _FakeBackgroundSession
    implements
        BackgroundLearningSessionControl,
        ActiveLearningBackgroundSessionControl {
  final StreamController<BackgroundLearningEvent> _events =
      StreamController<BackgroundLearningEvent>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  final List<bool> activeLearningValues = <bool>[];

  @override
  Stream<BackgroundLearningEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    startCount += 1;
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> setActiveLearning(bool active) async {
    activeLearningValues.add(active);
  }

  void emit(BackgroundLearningEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}
