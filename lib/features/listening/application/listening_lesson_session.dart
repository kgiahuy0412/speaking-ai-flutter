/// Owns asynchronous turn generations for one listening lesson.
///
/// Presentation code uses opaque integer tickets only to correlate an async
/// completion with the turn that created it. Invalidating a boundary makes a
/// late recorder, evaluator, completion-choice, or prompt callback harmless.
class ListeningLessonSession {
  int _recordingStartGeneration = 0;
  int _recordingLifecycleGeneration = 0;
  int _attemptEvaluationGeneration = 0;
  int _completionChoiceGeneration = 0;
  int _mainPauseGeneration = 0;
  bool _disposed = false;

  int beginRecordingStart() => ++_recordingStartGeneration;
  void invalidateRecordingStart() => _recordingStartGeneration += 1;
  bool isCurrentRecordingStart(int ticket) =>
      !_disposed && ticket == _recordingStartGeneration;

  int get recordingLifecycleTicket => _recordingLifecycleGeneration;
  void invalidateRecordingLifecycle() => _recordingLifecycleGeneration += 1;
  bool isCurrentRecordingLifecycle(int ticket) =>
      !_disposed && ticket == _recordingLifecycleGeneration;

  int beginAttemptEvaluation() => ++_attemptEvaluationGeneration;
  void invalidateAttemptEvaluation() => _attemptEvaluationGeneration += 1;
  bool isCurrentAttemptEvaluation(int ticket) =>
      !_disposed && ticket == _attemptEvaluationGeneration;

  int beginCompletionChoice() => ++_completionChoiceGeneration;
  int get completionChoiceTicket => _completionChoiceGeneration;
  void invalidateCompletionChoice() => _completionChoiceGeneration += 1;
  bool isCurrentCompletionChoice(int ticket) =>
      !_disposed && ticket == _completionChoiceGeneration;

  int get mainPauseTicket => _mainPauseGeneration;
  void invalidateMainPause() => _mainPauseGeneration += 1;
  bool isCurrentMainPause(int ticket) =>
      !_disposed && ticket == _mainPauseGeneration;

  void invalidateActiveTurn() {
    invalidateRecordingStart();
    invalidateRecordingLifecycle();
    invalidateAttemptEvaluation();
  }

  void dispose() {
    if (_disposed) return;
    invalidateActiveTurn();
    invalidateCompletionChoice();
    invalidateMainPause();
    _disposed = true;
  }
}
