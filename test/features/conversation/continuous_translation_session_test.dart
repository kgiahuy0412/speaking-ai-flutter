import 'dart:async';

import 'package:ai_speaking_flutter_app/features/conversation/application/continuous_translation_session.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deduplicates one pending start and resets before the next turn',
    () async {
      final runtime = _FakeContinuousTranslationRuntime();
      final session = ContinuousTranslationSession(runtime: runtime);
      addTearDown(session.dispose);

      final first = session.startRecording();
      final duplicate = session.startRecording();
      expect(runtime.startCalls, 1);
      expect(session.isRecordingStartPending, isTrue);

      runtime.completeStart();
      await Future.wait<void>(<Future<void>>[first, duplicate]);
      expect(session.isRecordingStartPending, isFalse);

      runtime.resetStart();
      final second = session.startRecording();
      expect(runtime.startCalls, 2);
      runtime.completeStart();
      await second;
    },
  );

  test('primary action unlocks playback before manually stopping', () async {
    final runtime = _FakeContinuousTranslationRuntime(
      phase: ConversationPhase.recording,
    );
    final session = ContinuousTranslationSession(runtime: runtime);
    addTearDown(session.dispose);

    await session.onPrimaryAction();

    expect(runtime.events, <String>['unlock', 'stop:true']);
  });

  test(
    'push-to-talk released while opening stops as soon as mic is ready',
    () async {
      final runtime = _FakeContinuousTranslationRuntime();
      final session = ContinuousTranslationSession(runtime: runtime);
      addTearDown(session.dispose);

      final press = session.startPushToTalk();
      await Future<void>.delayed(Duration.zero);
      await session.stopPushToTalk();
      expect(runtime.stopCalls, 0);

      runtime.phase = ConversationPhase.recording;
      runtime.completeStart();
      await press;

      expect(runtime.startNoSpeechTimeout, const Duration(seconds: 12));
      expect(runtime.startStopOnSilence, isFalse);
      expect(runtime.stopCalls, 1);
      expect(runtime.lastManualStop, isTrue);
    },
  );

  test('result playback flags cross the runtime boundary unchanged', () async {
    final runtime = _FakeContinuousTranslationRuntime();
    final session = ContinuousTranslationSession(runtime: runtime);
    addTearDown(session.dispose);

    await session.playResult(reportLatency: true, propagateFailure: true);

    expect(runtime.playCalls, 1);
    expect(runtime.reportLatency, isTrue);
    expect(runtime.propagateFailure, isTrue);
  });

  test(
    'cancel keeps a pending start visible for the cleanup barrier',
    () async {
      final runtime = _FakeContinuousTranslationRuntime();
      final session = ContinuousTranslationSession(runtime: runtime);
      addTearDown(session.dispose);

      final start = session.startRecording();
      session.cancelInteraction();
      expect(session.pendingRecordingStart, isNotNull);

      runtime.completeStart();
      await start;
      expect(session.pendingRecordingStart, isNull);
    },
  );
}

class _FakeContinuousTranslationRuntime
    implements ContinuousTranslationRuntime {
  _FakeContinuousTranslationRuntime({this.phase = ConversationPhase.idle});

  @override
  ConversationPhase phase;

  @override
  bool isBusy = false;

  final List<String> events = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
  int playCalls = 0;
  Duration? startNoSpeechTimeout;
  bool? startStopOnSilence;
  bool? lastManualStop;
  bool? reportLatency;
  bool? propagateFailure;
  Completer<void> _startCompleter = Completer<void>();

  void completeStart() {
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }

  void resetStart() {
    _startCompleter = Completer<void>();
  }

  @override
  Future<void> unlockPlaybackForUserGesture() async {
    events.add('unlock');
  }

  @override
  Future<void> startTurn({
    required Duration noSpeechTimeout,
    required bool speakNoSpeechPrompt,
    required bool stopOnSilence,
  }) {
    startCalls += 1;
    startNoSpeechTimeout = noSpeechTimeout;
    startStopOnSilence = stopOnSilence;
    return _startCompleter.future;
  }

  @override
  Future<void> stopTurn({required bool manual}) async {
    stopCalls += 1;
    lastManualStop = manual;
    events.add('stop:$manual');
  }

  @override
  Future<void> playResult({
    required bool reportLatency,
    required bool propagateFailure,
  }) async {
    playCalls += 1;
    this.reportLatency = reportLatency;
    this.propagateFailure = propagateFailure;
  }
}
