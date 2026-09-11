import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../application/recorded_lesson_voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_attempt_evaluator.dart';
import '../application/lesson_media_service.dart';
import '../domain/lesson_guide_flow.dart';
import '../domain/listening_content.dart';

/// The scored outcome of one authored Level Mission question.
///
/// A question may have several recognition attempts, but only its terminal
/// outcome is retained. This keeps the Level Mission score at one answer per
/// authored prompt rather than rewarding repeated recordings.
@immutable
class LessonMissionAnswer {
  const LessonMissionAnswer({
    required this.missionId,
    required this.targetId,
    required this.correct,
    required this.attempts,
    required this.outcome,
  });

  final String missionId;
  final String targetId;
  final bool correct;
  final int attempts;
  final LessonAttemptOutcome outcome;
}

/// Returned by [LessonMissionScreen] when all four mission prompts resolve.
@immutable
class LessonMissionResult {
  const LessonMissionResult({
    required this.answers,
    required this.score,
    required this.total,
    required this.weakTargetIds,
  });

  static const requiredQuestionCount = 4;
  static const passingScore = 3;

  /// One terminal answer, in authored mission order, for each prompt.
  final List<LessonMissionAnswer> answers;
  final int score;
  final int total;

  /// Stable, de-duplicated target identifiers to use when constructing a
  /// retest or a targeted relearn path.
  final List<String> weakTargetIds;

  bool get passed => total == requiredQuestionCount && score >= passingScore;
}

/// Voice-scored V4 Level Mission.
///
/// The supplied questions must be the authored four-question mission selected
/// for a Level. Choices are shown as listening aids only; the child must say
/// the full English answer. A prompt is resolved exactly once, then contributes
/// either one point or one weak target to [LessonMissionResult].
class LessonMissionScreen extends StatefulWidget {
  const LessonMissionScreen({
    required this.language,
    required this.startAge,
    required this.lesson,
    required this.missions,
    required this.mediaService,
    this.attemptEvaluator,
    this.voicePromptService,
    this.iosSpeechInput,
    this.onStarEarned,
    this.onStarEarnedWithResult,
    this.onStarEarnedWithAudioResult,
    this.onNeedsPractice,
    this.onMastered,
    this.initialAnswers = const <String, bool>{},
    this.onAnswerResolved,
    this.isReinforcement = false,
    this.levelTitle,
    super.key,
  }) : assert(
         isReinforcement
             ? missions.length > 0
             : missions.length == LessonMissionResult.requiredQuestionCount,
         'A Level Mission requires four prompts; reinforcement requires at least one.',
       );

  final DisplayLanguage language;
  final int startAge;

  /// A lesson provides the learner context and a stable assessment namespace.
  final ListeningLessonContent lesson;
  final List<ListeningMissionContent> missions;
  final LessonMediaService mediaService;
  final LessonAttemptEvaluator? attemptEvaluator;
  final VoicePromptService? voicePromptService;
  final LessonEnglishSpeechInput? iosSpeechInput;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onStarEarned;
  final Future<bool> Function(String starId, String english, String vietnamese)?
  onStarEarnedWithResult;
  final Future<bool> Function(
    String starId,
    String english,
    String vietnamese,
    String? correctAudioPath,
  )?
  onStarEarnedWithAudioResult;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onNeedsPractice;
  final Future<void> Function(String english)? onMastered;
  final Map<String, bool> initialAnswers;
  final Future<void> Function(LessonMissionAnswer answer)? onAnswerResolved;
  final bool isReinforcement;
  final String? levelTitle;

  @override
  State<LessonMissionScreen> createState() => _LessonMissionScreenState();
}

class _LessonMissionScreenState extends State<LessonMissionScreen>
    implements ActiveLearningModuleController {
  static const Duration _automaticAnswerWindow = Duration(seconds: 6);
  static const Duration _promptCompletionTimeout = Duration(seconds: 10);

  late final LessonAttemptEvaluator _attemptEvaluator;
  late final bool _ownsAttemptEvaluator;

  VoicePromptService? _voicePromptService;
  var _ownsVoicePromptService = false;
  var _missionIndex = 0;
  var _attemptNumber = 0;
  var _playingPrompt = false;
  var _recording = false;
  var _recordingUsesIosSpeech = false;
  var _correctionRepeatPendingResolve = false;
  LessonAttemptOutcome _correctionRepeatOutcome =
      LessonAttemptOutcome.needsPractice;
  var _busy = false;
  var _promptRequest = 0;
  String? _message;
  final Map<String, LessonMissionAnswer> _answers =
      <String, LessonMissionAnswer>{};
  Timer? _recordingAutoStopTimer;
  Timer? _promptCompletionTimer;
  Completer<void>? _promptCompletionWaiter;
  bool _pausedForMainAssistant = false;
  String? _activeAttemptAudioPath;
  String? _latestCorrectAudioPath;
  ActiveLearningModuleRegistry? _activeModuleRegistry;
  Object? _activeModuleRegistration;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  bool get _usesIosOnDeviceRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      widget.iosSpeechInput != null;

  VoicePromptService get _prompt {
    final prompt = _voicePromptService;
    if (prompt != null) return prompt;
    _ownsVoicePromptService = true;
    return _voicePromptService = createLessonVoicePromptService(
      mediaService: widget.mediaService,
      age: widget.startAge,
    );
  }

  ListeningMissionContent get _mission => widget.missions[_missionIndex];

  String get _lessonCode => widget.lesson.code.trim().isEmpty
      ? '${widget.lesson.id}-MISSION'
      : '${widget.lesson.code}-MISSION';

  String get _missionSentenceId => 'MISSION-${_mission.id}';

  @override
  void initState() {
    super.initState();
    _ownsAttemptEvaluator = widget.attemptEvaluator == null;
    _attemptEvaluator =
        widget.attemptEvaluator ?? createDefaultLessonAttemptEvaluator();
    _voicePromptService = widget.voicePromptService == null
        ? null
        : createLessonVoicePromptService(
            mediaService: widget.mediaService,
            override: widget.voicePromptService,
            age: widget.startAge,
          );
    for (final mission in widget.missions) {
      final correct = widget.initialAnswers[mission.id];
      if (correct == null) continue;
      _answers[mission.id] = LessonMissionAnswer(
        missionId: mission.id,
        targetId: mission.coverageTargetId,
        correct: correct,
        attempts: 0,
        outcome: correct
            ? LessonAttemptOutcome.good
            : LessonAttemptOutcome.retry,
      );
    }
    final firstUnanswered = widget.missions.indexWhere(
      (mission) => !_answers.containsKey(mission.id),
    );
    _missionIndex = firstUnanswered < 0
        ? widget.missions.length - 1
        : firstUnanswered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (firstUnanswered < 0) {
        Navigator.of(context).pop(_buildResult());
      } else {
        unawaited(_playCurrentPrompt());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (identical(registry, _activeModuleRegistry)) return;
    final oldRegistration = _activeModuleRegistration;
    if (oldRegistration != null) {
      _activeModuleRegistry?.unregister(oldRegistration);
    }
    _activeModuleRegistry = registry;
    _activeModuleRegistration = registry?.register(this);
  }

  @override
  void dispose() {
    final registration = _activeModuleRegistration;
    if (registration != null) {
      _activeModuleRegistry?.unregister(registration);
    }
    _promptRequest += 1;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    _promptCompletionTimer?.cancel();
    _promptCompletionTimer = null;
    final promptWaiter = _promptCompletionWaiter;
    _promptCompletionWaiter = null;
    if (promptWaiter != null && !promptWaiter.isCompleted) {
      promptWaiter.complete();
    }
    unawaited(widget.mediaService.stopPlayback());
    if (_recording || _recordingUsesIosSpeech) {
      if (_recordingUsesIosSpeech && widget.iosSpeechInput != null) {
        unawaited(widget.iosSpeechInput!.cancel());
      } else {
        unawaited(widget.mediaService.cancelRecording());
      }
    }
    final prompt = _voicePromptService;
    if (prompt != null) {
      if (_ownsVoicePromptService) {
        unawaited(prompt.dispose());
      } else {
        unawaited(prompt.stop());
      }
    }
    if (_ownsAttemptEvaluator &&
        _attemptEvaluator is DisposableLessonAttemptEvaluator) {
      (_attemptEvaluator as DisposableLessonAttemptEvaluator).dispose();
    }
    super.dispose();
  }

  @override
  Future<void> pauseForMainAssistant() async {
    _pausedForMainAssistant = true;
    _correctionRepeatPendingResolve = false;
    _promptRequest += 1;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    _promptCompletionTimer?.cancel();
    _promptCompletionTimer = null;
    final waiter = _promptCompletionWaiter;
    _promptCompletionWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final wasRecording = _recording;
    final usedIosSpeech = _recordingUsesIosSpeech;
    if (mounted) {
      setState(() {
        _playingPrompt = false;
        _recording = false;
        _recordingUsesIosSpeech = false;
        _busy = false;
        _message = 'Nhiệm vụ đang tạm dừng.';
      });
    }
    await Future.wait<void>(<Future<void>>[
      widget.mediaService.stopPlayback().catchError((Object _) {}),
      if (_voicePromptService != null)
        _voicePromptService!.stop().catchError((Object _) {}),
      if (wasRecording && usedIosSpeech && widget.iosSpeechInput != null)
        widget.iosSpeechInput!.cancel().catchError((Object _) {})
      else if (wasRecording)
        widget.mediaService.cancelRecording().catchError((Object _) {}),
    ]);
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) return const ActiveLearningCommandResult.unavailable();
    switch (command) {
      case ActiveLearningCommand.resume:
        _pausedForMainAssistant = false;
        await _playCurrentPrompt();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng Nhiệm vụ.',
        );
      case ActiveLearningCommand.exitToHome:
        await pauseForMainAssistant();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
      case ActiveLearningCommand.nextItem:
      case ActiveLearningCommand.previousItem:
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.restart:
      case ActiveLearningCommand.vocabularyParentAdded:
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable(
          spokenReply:
              'Các nút câu trước, câu sau và nghe lại chỉ dùng trong phần luyện câu.',
        );
    }
  }

  Future<void> _playCurrentPrompt({bool allowBusy = false}) async {
    if (_pausedForMainAssistant ||
        !mounted ||
        _recording ||
        (_busy && !allowBusy)) {
      return;
    }
    final request = ++_promptRequest;
    setState(() {
      _playingPrompt = true;
      _message = null;
    });
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!mounted || request != _promptRequest) return;
      if (widget.isReinforcement) {
        await _speakReinforcementTarget(request);
      } else {
        await _speakPromptAndWait(
          _mission.prompt,
          audioId: '${_mission.id}_PROMPT',
        );
        if (!mounted || request != _promptRequest) return;
        await _speakPromptAndWait('Bạn nói đầy đủ câu tiếng Anh nhé.');
      }
    } catch (_) {
      // The visible prompt and record action remain available when TTS is
      // temporarily unavailable.
    } finally {
      if (mounted && request == _promptRequest) {
        setState(() => _playingPrompt = false);
      }
    }
    if (_pausedForMainAssistant ||
        !mounted ||
        request != _promptRequest ||
        _recording ||
        _busy) {
      return;
    }
    await _startRecording();
  }

  Future<void> _speakReinforcementTarget(int request) async {
    await _speakPromptAndWait(_mission.correctAnswer, locale: 'en-US');
    if (!mounted || request != _promptRequest) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || request != _promptRequest) return;
    if (_mission.correctVietnamese.trim().isNotEmpty) {
      await _speakPromptAndWait(_mission.correctVietnamese);
      if (!mounted || request != _promptRequest) return;
    }
    await _speakPromptAndWait('Bạn nói lại tiếng Anh nhé.');
  }

  Future<void> _speakPromptAndWait(
    String text, {
    String locale = 'vi-VN',
    String? audioId,
    String? feedbackState,
  }) async {
    _promptCompletionTimer?.cancel();
    final previousWaiter = _promptCompletionWaiter;
    if (previousWaiter != null && !previousWaiter.isCompleted) {
      previousWaiter.complete();
    }

    final waiter = Completer<void>();
    _promptCompletionWaiter = waiter;
    unawaited(() async {
      try {
        await speakRecordedLessonPrompt(
          _prompt,
          text,
          locale: locale,
          audioId: audioId,
          feedbackState: feedbackState,
        );
        if (!waiter.isCompleted) waiter.complete();
      } catch (error, stackTrace) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      }
    }());
    _promptCompletionTimer = Timer(
      _prompt is RecordedLessonVoicePromptService
          ? RecordedLessonVoicePromptService.playbackTimeout
          : _promptCompletionTimeout,
      () {
        unawaited(() async {
          try {
            await _prompt.stop();
          } finally {
            if (!waiter.isCompleted) waiter.complete();
          }
        }());
      },
    );

    try {
      await waiter.future;
    } finally {
      if (identical(_promptCompletionWaiter, waiter)) {
        _promptCompletionTimer?.cancel();
        _promptCompletionTimer = null;
        _promptCompletionWaiter = null;
      }
    }
  }

  Future<void> _startRecording() async {
    if (_pausedForMainAssistant ||
        _recording ||
        _busy ||
        _playingPrompt ||
        !mounted) {
      return;
    }
    final expected = _mission.correctAnswer.trim();
    if (expected.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    _latestCorrectAudioPath = null;
    try {
      await _prompt.stop();
      var usesIosSpeech = false;
      final iosSpeechInput = _usesIosOnDeviceRecognition
          ? widget.iosSpeechInput
          : null;
      if (iosSpeechInput != null) {
        try {
          if (iosSpeechInput is IOSStreamingSpeechInput) {
            _activeAttemptAudioPath = await widget.mediaService.recordingPath(
              lessonId: '${widget.lesson.id}-mission',
              sentenceNumber: _missionIndex + 1,
              extension: 'wav',
            );
            await iosSpeechInput.startLessonEnglishRecognitionWithRecording(
              _activeAttemptAudioPath!,
            );
          } else {
            _activeAttemptAudioPath = null;
            await iosSpeechInput.startLessonEnglishRecognition();
          }
          usesIosSpeech = true;
          widget.mediaService.handoffSelectedLessonOutputToNativeCapture();
        } on StreamingSpeechInputException catch (error) {
          if (_isPermissionFailure(error)) {
            rethrow;
          }
          debugPrint(
            'HOMI iOS mission on-device recognition unavailable; '
            'using recorded/backend fallback: $error',
          );
          await iosSpeechInput.cancel().catchError((Object _) {});
        }
      }
      if (!usesIosSpeech) {
        _activeAttemptAudioPath = null;
        await widget.mediaService.startRecording(
          lessonId: '${widget.lesson.id}-mission',
          sentenceNumber: _missionIndex + 1,
          lessonTitle: '${widget.lesson.titleVi} · Level Mission',
          sentenceId: _missionSentenceId,
          english: expected,
          vietnamese: _mission.correctVietnamese,
          saveToHistory: false,
        );
      }
      if (!mounted) {
        if (usesIosSpeech) {
          await iosSpeechInput?.cancel().catchError((Object _) {});
        } else {
          await widget.mediaService.cancelRecording().catchError((Object _) {});
        }
        return;
      }
      setState(() {
        _recording = true;
        _recordingUsesIosSpeech = usesIosSpeech;
        _busy = false;
      });
      _recordingAutoStopTimer?.cancel();
      _recordingAutoStopTimer = Timer(
        _automaticAnswerWindow,
        () => unawaited(_stopRecording()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingUsesIosSpeech = false;
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  bool _isPermissionFailure(StreamingSpeechInputException error) =>
      error.code == 'SPEECH_PERMISSION_DENIED' ||
      error.code == 'MICROPHONE_PERMISSION_DENIED' ||
      error.code == 'MICROPHONE_PERMISSION_PENDING';

  Future<void> _stopRecording() async {
    if (!_recording || _busy || !mounted) return;
    final request = _promptRequest;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    setState(() => _busy = true);
    var shouldOpenMicrophoneAgain = false;
    if (_correctionRepeatPendingResolve) {
      try {
        if (_recordingUsesIosSpeech && widget.iosSpeechInput != null) {
          await widget.iosSpeechInput!.cancel().catchError((Object _) {});
        } else {
          await widget.mediaService.cancelRecording().catchError((Object _) {});
        }
        if (!mounted || _pausedForMainAssistant || request != _promptRequest) {
          return;
        }
        final outcome = _correctionRepeatOutcome;
        _correctionRepeatPendingResolve = false;
        setState(() {
          _recording = false;
          _recordingUsesIosSpeech = false;
        });
        shouldOpenMicrophoneAgain = await _resolveCurrent(
          correct: false,
          outcome: outcome,
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (shouldOpenMicrophoneAgain &&
          mounted &&
          !_pausedForMainAssistant &&
          !_recording) {
        await _startRecording();
      }
      return;
    }
    try {
      final usesIosSpeech = _recordingUsesIosSpeech;
      final LessonAttemptOutcome outcome;
      final evaluatedAttemptNumber = _attemptNumber + 1;
      if (usesIosSpeech) {
        outcome = await _stopAndScoreIosOnDevice();
      } else {
        final recording = await widget.mediaService.stopRecording();
        if (!mounted || _pausedForMainAssistant || request != _promptRequest) {
          return;
        }
        outcome = await _attemptEvaluator.evaluate(
          lessonCode: _lessonCode,
          sentenceId: _missionSentenceId,
          expectedEnglish: _mission.correctAnswer,
          recordingPath: recording.filePath,
          recordingDuration: recording.duration,
          attemptNumber: evaluatedAttemptNumber,
          childAge: widget.startAge,
          requireAllExpectedTokens: false,
        );
        if (outcome == LessonAttemptOutcome.good) {
          _latestCorrectAudioPath = recording.filePath;
        }
      }
      if (!mounted || _pausedForMainAssistant || request != _promptRequest) {
        return;
      }
      if (outcome != LessonAttemptOutcome.unclear &&
          outcome != LessonAttemptOutcome.noResponse) {
        _attemptNumber = evaluatedAttemptNumber;
      }
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
      });
      shouldOpenMicrophoneAgain = await _applyOutcome(outcome);
    } catch (error) {
      if (!mounted || _pausedForMainAssistant || request != _promptRequest) {
        return;
      }
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (shouldOpenMicrophoneAgain &&
        mounted &&
        !_pausedForMainAssistant &&
        !_recording) {
      await _startRecording();
    }
  }

  Future<LessonAttemptOutcome> _stopAndScoreIosOnDevice() async {
    final speechInput = widget.iosSpeechInput;
    if (speechInput == null) return LessonAttemptOutcome.unclear;
    try {
      final capture = await speechInput.stop();
      final candidates = <String>{
        capture.sourceText,
        ...capture.alternatives,
      }.where((candidate) => candidate.trim().isNotEmpty);
      if (candidates.isEmpty) return LessonAttemptOutcome.noResponse;
      final outcome =
          candidates.any(
            (candidate) => matchesRecognizedLessonEnglish(
              _mission.correctAnswer,
              candidate,
              requireAllExpectedTokens: false,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
      if (outcome == LessonAttemptOutcome.good) {
        _latestCorrectAudioPath =
            capture.recordedAudio?.filePath ?? _activeAttemptAudioPath;
      }
      return outcome;
    } on StreamingSpeechInputException catch (error) {
      debugPrint(
        'HOMI iOS mission recognition returned no usable speech: '
        'code=${error.code ?? 'unknown'}',
      );
      return LessonAttemptOutcome.unclear;
    } catch (error) {
      debugPrint('HOMI iOS mission recognition failed locally: $error');
      return LessonAttemptOutcome.unclear;
    }
  }

  Future<bool> _applyOutcome(LessonAttemptOutcome outcome) async {
    switch (outcome) {
      case LessonAttemptOutcome.good:
        await _speakFeedback(LessonFeedbackKind.correct);
        if (_pausedForMainAssistant) return false;
        if (widget.isReinforcement) {
          await _saveMastered();
        } else {
          await _awardStar();
        }
        return _resolveCurrent(correct: true, outcome: outcome);
      case LessonAttemptOutcome.needsPractice:
      case LessonAttemptOutcome.retry:
        if (_attemptNumber >= 2) {
          return _prepareCorrectionRepeat(outcome);
        }
        await _speakFeedback(LessonFeedbackKind.retry);
        if (widget.isReinforcement && mounted && !_pausedForMainAssistant) {
          await _speakReinforcementTarget(_promptRequest);
        }
        return mounted;
      case LessonAttemptOutcome.unclear:
        await _speakFeedback(LessonFeedbackKind.asr);
        return mounted;
      case LessonAttemptOutcome.noResponse:
        await _speakFeedback(LessonFeedbackKind.noResponse);
        return mounted;
    }
  }

  Future<void> _speakFeedback(LessonFeedbackKind kind) async {
    final feedback = LessonAgeFeedbackLibrary.message(
      age: widget.startAge,
      kind: kind,
    );
    if (mounted) setState(() => _message = feedback);
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      await _speakPromptAndWait(
        feedback,
        feedbackState: kind == LessonFeedbackKind.noResponse
            ? 'NO_RESPONSE'
            : kind.name.toUpperCase(),
      );
    } catch (_) {
      // Keep visible feedback and continue with the authored state machine.
    }
  }

  Future<void> _awardStar() async {
    final callbackWithAudioResult = widget.onStarEarnedWithAudioResult;
    if (callbackWithAudioResult != null) {
      try {
        await callbackWithAudioResult(
          'mission:${_missionIndex + 1}',
          _mission.correctAnswer,
          _mission.correctVietnamese,
          _latestCorrectAudioPath,
        );
      } catch (_) {
        // Local Star persistence must never interrupt Level Mission scoring.
      }
      return;
    }
    final callbackWithResult = widget.onStarEarnedWithResult;
    if (callbackWithResult != null) {
      try {
        await callbackWithResult(
          'mission:${_missionIndex + 1}',
          _mission.correctAnswer,
          _mission.correctVietnamese,
        );
      } catch (_) {
        // Local Star persistence must never interrupt Level Mission scoring.
      }
      return;
    }
    final callback = widget.onStarEarned;
    if (callback == null) return;
    try {
      await callback(
        _missionSentenceId,
        _mission.correctAnswer,
        _mission.correctVietnamese,
      );
    } catch (_) {
      // Local Star persistence must never interrupt Level Mission scoring.
    }
  }

  Future<bool> _giveAnswerAndResolve({
    required LessonAttemptOutcome outcome,
    required bool skip,
  }) async {
    await _speakFeedback(
      skip ? LessonFeedbackKind.skip : LessonFeedbackKind.give,
    );
    if (!mounted || _pausedForMainAssistant) return false;
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      await _speakPromptAndWait(_mission.correctAnswer, locale: 'en-US');
    } catch (_) {
      // The correct authored answer remains visible on screen.
    }
    if (!mounted || _pausedForMainAssistant) return false;
    if (!skip) {
      await _saveNeedsPractice();
      if (!mounted || _pausedForMainAssistant) return false;
    }
    return _resolveCurrent(correct: false, outcome: outcome);
  }

  Future<bool> _prepareCorrectionRepeat(LessonAttemptOutcome outcome) async {
    await _speakFeedback(LessonFeedbackKind.give);
    if (!mounted || _pausedForMainAssistant) return false;
    await _saveNeedsPractice();
    if (!mounted || _pausedForMainAssistant) return false;
    await widget.mediaService.prepareSelectedLessonOutput().catchError((
      Object error,
    ) {
      debugPrint('HOMI mission correction route failed: $error');
    });
    for (final line in <({String text, String locale})>[
      (text: _mission.correctAnswer, locale: 'en-US'),
      if (_mission.correctVietnamese.trim().isNotEmpty)
        (text: _mission.correctVietnamese, locale: 'vi-VN'),
      (text: 'Bạn nói lại tiếng Anh nhé.', locale: 'vi-VN'),
    ]) {
      try {
        await _speakPromptAndWait(line.text, locale: line.locale);
      } catch (error) {
        // One failed line must not suppress the remaining model/invitation.
        debugPrint('HOMI mission correction line failed: $error');
      }
    }
    if (!mounted || _pausedForMainAssistant) return false;
    _correctionRepeatOutcome = outcome;
    _correctionRepeatPendingResolve = true;
    return true;
  }

  Future<void> _saveNeedsPractice() async {
    final callback = widget.onNeedsPractice;
    if (callback == null) return;
    try {
      await callback(
        'mission:${_missionIndex + 1}',
        _mission.correctAnswer,
        _mission.correctVietnamese,
      );
    } catch (_) {
      // Vocabulary persistence must never interrupt the authored lesson.
    }
  }

  Future<void> _saveMastered() async {
    final callback = widget.onMastered;
    if (callback == null) return;
    try {
      await callback(_mission.correctAnswer);
    } catch (_) {
      // Vocabulary persistence must never interrupt the authored lesson.
    }
  }

  Future<void> _skipCurrent() async {
    if (_busy || _playingPrompt) return;
    setState(() => _busy = true);
    var shouldOpenMicrophoneAgain = false;
    try {
      if (_recording) {
        _recordingAutoStopTimer?.cancel();
        _recordingAutoStopTimer = null;
        if (_recordingUsesIosSpeech && widget.iosSpeechInput != null) {
          await widget.iosSpeechInput!.cancel().catchError((Object _) {});
        } else {
          await widget.mediaService.cancelRecording().catchError((Object _) {});
        }
        if (!mounted) return;
        setState(() {
          _recording = false;
          _recordingUsesIosSpeech = false;
        });
      }
      shouldOpenMicrophoneAgain = await _giveAnswerAndResolve(
        outcome: LessonAttemptOutcome.needsPractice,
        skip: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (shouldOpenMicrophoneAgain && mounted && !_recording) {
      await _startRecording();
    }
  }

  Future<bool> _resolveCurrent({
    required bool correct,
    required LessonAttemptOutcome outcome,
  }) async {
    if (_pausedForMainAssistant) return false;
    _correctionRepeatPendingResolve = false;
    final mission = _mission;
    // An evaluator can resolve late as the route is transitioning. Never let a
    // duplicate callback turn one authored prompt into multiple score entries.
    if (_answers.containsKey(mission.id)) return false;
    final answer = LessonMissionAnswer(
      missionId: mission.id,
      targetId: mission.coverageTargetId,
      correct: correct,
      attempts: _attemptNumber,
      outcome: outcome,
    );
    setState(() => _answers[mission.id] = answer);
    final answerCallback = widget.onAnswerResolved;
    if (answerCallback != null) {
      try {
        await answerCallback(answer);
      } catch (_) {
        // Resume persistence cannot interrupt the live assessment.
      }
    }

    final nextIndex = widget.missions.indexWhere(
      (candidate) => !_answers.containsKey(candidate.id),
      _missionIndex + 1,
    );
    if (nextIndex >= 0) {
      setState(() {
        _missionIndex = nextIndex;
        _attemptNumber = 0;
        _message = null;
      });
      await _playCurrentPrompt(allowBusy: true);
      return mounted;
    }

    if (!mounted) return false;
    Navigator.of(context).pop(_buildResult());
    return false;
  }

  LessonMissionResult _buildResult() {
    final answers = widget.missions
        .map((mission) => _answers[mission.id])
        .whereType<LessonMissionAnswer>()
        .toList(growable: false);
    final weakIds = <String>{
      for (final answer in answers)
        if (!answer.correct && answer.targetId.trim().isNotEmpty)
          answer.targetId.trim(),
    };
    return LessonMissionResult(
      answers: answers,
      score: answers.where((answer) => answer.correct).length,
      total: widget.missions.length,
      weakTargetIds: weakIds.toList(growable: false),
    );
  }

  String _friendlyError(Object error) {
    if (error is StreamingSpeechInputException &&
        error.code == 'SPEECH_PERMISSION_DENIED') {
      return error.message;
    }
    final text = error.toString();
    if (text.contains('micro') || text.contains('Micro')) {
      return 'Ứng dụng cần quyền micro để nghe câu trả lời.';
    }
    return 'Chưa chấm được câu trả lời. Bạn thử nói lại nhé.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_missionIndex / widget.missions.length).clamp(0.0, 1.0);
    final levelLabel = widget.levelTitle?.trim();

    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-mission-screen'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: _busy || _recording
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Quay lại',
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: LinearProgressIndicator(value: progress)),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _playingPrompt || _busy
                            ? null
                            : _playCurrentPrompt,
                        icon: const Icon(Icons.volume_up_rounded),
                        tooltip: 'Nghe lại',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 132,
                    child: Image.asset(
                      MascotAssets.listen,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.isReinforcement ? 'Luyện nhanh' : 'Level Mission',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    levelLabel == null || levelLabel.isEmpty
                        ? 'Câu ${_missionIndex + 1}/4 · Cần đúng ít nhất 3 câu'
                        : '$levelLabel · Câu ${_missionIndex + 1}/4 · Cần đúng ít nhất 3 câu',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _MissionCard(mission: _mission),
                    ),
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FilledButton.icon(
                        key: const Key('lesson-mission-record-button'),
                        onPressed: _busy || _playingPrompt
                            ? null
                            : (_recording ? _stopRecording : _startRecording),
                        icon: Icon(
                          _recording ? Icons.stop_rounded : Icons.mic_rounded,
                        ),
                        label: Text(
                          _recording ? 'Dừng và chấm' : 'Nói câu trả lời',
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('lesson-mission-skip-button'),
                        onPressed: _busy || _playingPrompt
                            ? null
                            : _skipCurrent,
                        child: const Text('Bỏ qua'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});

  final ListeningMissionContent mission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = mission.choices.take(2).toList(growable: false);
    return Container(
      key: const Key('lesson-mission-prompt'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.lavenderBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Nghe câu hỏi rồi nói đáp án tiếng Anh',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          Text(mission.prompt, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 18),
          for (var index = 0; index < choices.length; index++) ...<Widget>[
            _MissionChoice(label: choices[index]),
            if (index < choices.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Text(
            'Không cần chạm chọn đáp án — bạn hãy nói đầy đủ câu tiếng Anh.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MissionChoice extends StatelessWidget {
  const _MissionChoice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lavenderBorder),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.indigoDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
