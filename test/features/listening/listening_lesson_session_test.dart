import 'package:ai_speaking_flutter_app/features/listening/application/listening_lesson_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a newer recorder start invalidates a late start callback', () {
    final session = ListeningLessonSession();
    final first = session.beginRecordingStart();
    final second = session.beginRecordingStart();

    expect(session.isCurrentRecordingStart(first), isFalse);
    expect(session.isCurrentRecordingStart(second), isTrue);
  });

  test('MAIN invalidates capture and evaluation without changing choices', () {
    final session = ListeningLessonSession();
    final recording = session.recordingLifecycleTicket;
    final evaluation = session.beginAttemptEvaluation();
    final choice = session.beginCompletionChoice();

    session.invalidateActiveTurn();

    expect(session.isCurrentRecordingLifecycle(recording), isFalse);
    expect(session.isCurrentAttemptEvaluation(evaluation), isFalse);
    expect(session.isCurrentCompletionChoice(choice), isTrue);
  });

  test('completion choice and MAIN prompt have independent generations', () {
    final session = ListeningLessonSession();
    final pause = session.mainPauseTicket;
    final choice = session.beginCompletionChoice();

    session.invalidateCompletionChoice();
    expect(session.isCurrentCompletionChoice(choice), isFalse);
    expect(session.isCurrentMainPause(pause), isTrue);

    session.invalidateMainPause();
    expect(session.isCurrentMainPause(pause), isFalse);
  });

  test('dispose makes every outstanding ticket stale', () {
    final session = ListeningLessonSession();
    final recordingStart = session.beginRecordingStart();
    final recording = session.recordingLifecycleTicket;
    final evaluation = session.beginAttemptEvaluation();
    final choice = session.beginCompletionChoice();
    final pause = session.mainPauseTicket;

    session.dispose();

    expect(session.isCurrentRecordingStart(recordingStart), isFalse);
    expect(session.isCurrentRecordingLifecycle(recording), isFalse);
    expect(session.isCurrentAttemptEvaluation(evaluation), isFalse);
    expect(session.isCurrentCompletionChoice(choice), isFalse);
    expect(session.isCurrentMainPause(pause), isFalse);
  });
}
