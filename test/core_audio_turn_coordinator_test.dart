import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudioTurnCoordinator coordinator;

  setUp(() {
    coordinator = AudioTurnCoordinator();
  });

  tearDown(() async {
    await coordinator.dispose();
  });

  test('grants only one owner at a time in request order', () async {
    final lesson = await coordinator.acquire(
      owner: AudioTurnOwner.listeningLesson,
      mode: AudioTurnMode.speechCapture,
    );
    var translationGranted = false;
    final translationFuture = coordinator
        .acquire(
          owner: AudioTurnOwner.continuousTranslation,
          mode: AudioTurnMode.speechCapture,
        )
        .then((lease) {
          translationGranted = true;
          return lease;
        });

    await Future<void>.delayed(Duration.zero);
    expect(translationGranted, isFalse);
    expect(coordinator.currentToken, lesson.token);

    await lesson.release();
    final translation = await translationFuture;
    expect(translationGranted, isTrue);
    expect(coordinator.currentToken, translation.token);
    await translation.release();
  });

  test('an old token cannot release a transferred turn', () async {
    final translation = await coordinator.acquire(
      owner: AudioTurnOwner.continuousTranslation,
      mode: AudioTurnMode.speechCapture,
    );
    final assistant = await translation.transfer(
      owner: AudioTurnOwner.mainAssistant,
      mode: AudioTurnMode.promptPlayback,
    );

    expect(assistant, isNotNull);
    await translation.release();
    expect(coordinator.currentToken, assistant!.token);
    expect(assistant.isCurrent, isTrue);
    await assistant.release();
  });

  test(
    'cancels a queued acquisition without touching the active owner',
    () async {
      final lesson = await coordinator.acquire(
        owner: AudioTurnOwner.listeningLesson,
        mode: AudioTurnMode.mediaPlayback,
      );
      final cancellation = AudioTurnCancellation();
      final queued = coordinator.acquire(
        owner: AudioTurnOwner.vocabulary,
        mode: AudioTurnMode.promptPlayback,
        cancellation: cancellation,
      );

      cancellation.cancel();
      await expectLater(queued, throwsA(isA<AudioTurnAcquireCancelled>()));
      expect(coordinator.currentToken, lesson.token);
      expect(coordinator.pendingCount, 0);
      await lesson.release();
    },
  );

  test('a timed-out request does not poison the queue', () async {
    final lesson = await coordinator.acquire(
      owner: AudioTurnOwner.listeningLesson,
      mode: AudioTurnMode.mediaPlayback,
    );
    final timedOut = coordinator.acquire(
      owner: AudioTurnOwner.vocabulary,
      mode: AudioTurnMode.speechCapture,
      timeout: const Duration(milliseconds: 5),
    );

    await expectLater(timedOut, throwsA(isA<AudioTurnAcquireTimeout>()));
    await lesson.release();
    final assistant = await coordinator.acquire(
      owner: AudioTurnOwner.mainAssistant,
      mode: AudioTurnMode.speechCapture,
    );

    expect(assistant.isCurrent, isTrue);
    await assistant.release();
  });

  test(
    'disposing one owner adapter releases only its own current turn',
    () async {
      final actionStarted = Completer<void>();
      final actionMayFinish = Completer<void>();
      final lessonAdapter = CompatibilityAudioTurnAdapter(
        coordinator: coordinator,
        owner: AudioTurnOwner.listeningLesson,
      );
      final lessonRun = lessonAdapter.run<void>(
        mode: AudioTurnMode.speechCapture,
        action: (_) async {
          actionStarted.complete();
          await actionMayFinish.future;
        },
      );
      await actionStarted.future;

      final assistantFuture = coordinator.acquire(
        owner: AudioTurnOwner.mainAssistant,
        mode: AudioTurnMode.promptPlayback,
      );
      await lessonAdapter.dispose();
      final assistant = await assistantFuture;
      expect(assistant.isCurrent, isTrue);

      actionMayFinish.complete();
      await lessonRun;
      expect(assistant.isCurrent, isTrue);
      await assistant.release();
    },
  );

  test(
    'emits acquire, transfer, stale release, and release diagnostics',
    () async {
      final events = <AudioTurnDiagnostic>[];
      final subscription = coordinator.diagnostics.listen(events.add);
      addTearDown(subscription.cancel);

      final translation = await coordinator.acquire(
        owner: AudioTurnOwner.continuousTranslation,
        mode: AudioTurnMode.speechCapture,
      );
      final assistant = await translation.transfer(
        owner: AudioTurnOwner.mainAssistant,
        mode: AudioTurnMode.promptPlayback,
      );
      await translation.release();
      await assistant!.release();

      expect(
        events.map((event) => event.type),
        containsAllInOrder(<AudioTurnDiagnosticType>[
          AudioTurnDiagnosticType.acquireRequested,
          AudioTurnDiagnosticType.acquired,
          AudioTurnDiagnosticType.transferred,
          AudioTurnDiagnosticType.staleRelease,
          AudioTurnDiagnosticType.released,
        ]),
      );
    },
  );
}
