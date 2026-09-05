import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
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
    this.levelTitle,
    super.key,
  }) : assert(
         missions.length == LessonMissionResult.requiredQuestionCount,
         'A Level Mission requires exactly four authored prompts.',
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
  final String? levelTitle;

  @override
  State<LessonMissionScreen> createState() => _LessonMissionScreenState();
}

class _LessonMissionScreenState extends State<LessonMissionScreen> {
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
  var _busy = false;
  var _promptRequest = 0;
  String? _message;
  final Map<String, LessonMissionAnswer> _answers =
      <String, LessonMissionAnswer>{};
  Timer? _recordingAutoStopTimer;
  Timer? _promptCompletionTimer;
  Completer<void>? _promptCompletionWaiter;

  bool get _usesIosOnDeviceRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      widget.iosSpeechInput != null;

  VoicePromptService get _prompt {
    final prompt = _voicePromptService;
    if (prompt != null) return prompt;
    _ownsVoicePromptService = true;
    return _voicePromptService = createVoicePromptService();
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
    _voicePromptService = widget.voicePromptService;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_playCurrentPrompt()),
    );
  }

  @override
  void dispose() {
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

  Future<void> _playCurrentPrompt({bool allowBusy = false}) async {
    if (!mounted || _recording || (_busy && !allowBusy)) return;
    final request = ++_promptRequest;
    setState(() {
      _playingPrompt = true;
      _message = null;
    });
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!mounted || request != _promptRequest) return;
      await _speakPromptAndWait(_mission.prompt);
      if (!mounted || request != _promptRequest) return;
      await _speakPromptAndWait('Bạn nói đầy đủ câu tiếng Anh nhé.');
    } catch (_) {
      // The visible prompt and record action remain available when TTS is
      // temporarily unavailable.
    } finally {
      if (mounted && request == _promptRequest) {
        setState(() => _playingPrompt = false);
      }
    }
    if (!mounted || request != _promptRequest || _recording || _busy) {
      return;
    }
    await _startRecording();
  }

  Future<void> _speakPromptAndWait(
    String text, {
    String locale = 'vi-VN',
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
        await _prompt.speakAndWait(text, locale: locale);
        if (!waiter.isCompleted) waiter.complete();
      } catch (error, stackTrace) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      }
    }());
    _promptCompletionTimer = Timer(_promptCompletionTimeout, () {
      unawaited(() async {
        try {
          await _prompt.stop();
        } finally {
          if (!waiter.isCompleted) waiter.complete();
        }
      }());
    });

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
    if (_recording || _busy || _playingPrompt || !mounted) return;
    final expected = _mission.correctAnswer.trim();
    if (expected.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _prompt.stop();
      var usesIosSpeech = false;
      final iosSpeechInput = _usesIosOnDeviceRecognition
          ? widget.iosSpeechInput
          : null;
      if (iosSpeechInput != null) {
        try {
          await iosSpeechInput.startLessonEnglishRecognition();
          usesIosSpeech = true;
          widget.mediaService.handoffSelectedLessonOutputToNativeCapture();
        } catch (error) {
          debugPrint(
            'HOMI iOS mission on-device recognition unavailable; '
            'using recorded/backend fallback: $error',
          );
          await iosSpeechInput.cancel().catchError((Object _) {});
        }
      }
      if (!usesIosSpeech) {
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

  Future<void> _stopRecording() async {
    if (!_recording || _busy || !mounted) return;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    setState(() => _busy = true);
    var shouldOpenMicrophoneAgain = false;
    try {
      final usesIosSpeech = _recordingUsesIosSpeech;
      final LessonAttemptOutcome outcome;
      if (usesIosSpeech) {
        outcome = await _stopAndScoreIosOnDevice();
        _attemptNumber += 1;
      } else {
        final recording = await widget.mediaService.stopRecording();
        if (!mounted) return;
        outcome = await _attemptEvaluator.evaluate(
          lessonCode: _lessonCode,
          sentenceId: _missionSentenceId,
          expectedEnglish: _mission.correctAnswer,
          recordingPath: recording.filePath,
          recordingDuration: recording.duration,
          attemptNumber: ++_attemptNumber,
          childAge: widget.startAge,
          requireAllExpectedTokens: false,
        );
      }
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
      });
      shouldOpenMicrophoneAgain = await _applyOutcome(outcome);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingUsesIosSpeech = false;
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (shouldOpenMicrophoneAgain && mounted && !_recording) {
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
      if (candidates.isEmpty) return LessonAttemptOutcome.unclear;
      return candidates.any(
            (candidate) => matchesRecognizedLessonEnglish(
              _mission.correctAnswer,
              candidate,
              requireAllExpectedTokens: false,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
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
        return _resolveCurrent(correct: true, outcome: outcome);
      case LessonAttemptOutcome.needsPractice:
        return _resolveCurrent(correct: false, outcome: outcome);
      case LessonAttemptOutcome.unclear:
      case LessonAttemptOutcome.retry:
        // Match the lesson behaviour: permit one retry, then resolve the
        // authored mission as weak so the Level can always produce 4 results.
        if (_attemptNumber >= 2) {
          return _resolveCurrent(correct: false, outcome: outcome);
        }
        final feedback = outcome == LessonAttemptOutcome.unclear
            ? 'Cô chưa nghe rõ. Bạn nói lại nhé.'
            : 'Bạn nói đầy đủ cả câu tiếng Anh nhé.';
        if (mounted) {
          setState(() => _message = feedback);
        }
        try {
          await widget.mediaService.prepareSelectedLessonOutput();
          await _speakPromptAndWait(feedback);
        } catch (_) {
          // Keep the visible feedback and reopen the microphone even if TTS is
          // temporarily unavailable.
        }
        return mounted;
    }
  }

  Future<bool> _resolveCurrent({
    required bool correct,
    required LessonAttemptOutcome outcome,
  }) async {
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

    if (_missionIndex < widget.missions.length - 1) {
      setState(() {
        _missionIndex += 1;
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
                  Text('Level Mission', style: theme.textTheme.headlineMedium),
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
