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

/// Runs the authored V4 end-of-lesson activity.
///
/// Each challenge keeps the two options written by the curriculum team, but
/// the microphone is the answer control: a child must say the English answer,
/// rather than selecting A/B.  When V4 supplies a role-play, it is
/// completed immediately before the two challenges and only the child's turns
/// are recorded and scored.
class LessonChallengeScreen extends StatefulWidget {
  const LessonChallengeScreen({
    required this.language,
    required this.startAge,
    required this.lesson,
    required this.challenges,
    required this.mediaService,
    this.attemptEvaluator,
    this.voicePromptService,
    this.iosSpeechInput,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final ListeningLessonContent lesson;
  final List<ListeningChallengeContent> challenges;
  final LessonMediaService mediaService;
  final LessonAttemptEvaluator? attemptEvaluator;
  final VoicePromptService? voicePromptService;
  final LessonEnglishSpeechInput? iosSpeechInput;

  @override
  State<LessonChallengeScreen> createState() => _LessonChallengeScreenState();
}

class _LessonChallengeScreenState extends State<LessonChallengeScreen> {
  static const Duration _automaticAnswerWindow = Duration(seconds: 6);
  static const Duration _promptCompletionTimeout = Duration(seconds: 10);

  late final LessonAttemptEvaluator _attemptEvaluator;
  late final bool _ownsAttemptEvaluator;

  VoicePromptService? _voicePromptService;
  bool _ownsVoicePromptService = false;
  bool _rolePlayCompleted = false;
  int _rolePlayTurnIndex = 0;
  int _challengeIndex = 0;
  int _attemptNumber = 0;
  bool _playingPrompt = false;
  bool _recording = false;
  bool _recordingUsesIosSpeech = false;
  bool _busy = false;
  String? _message;
  int _request = 0;
  Timer? _recordingAutoStopTimer;
  Timer? _promptCompletionTimer;
  Completer<void>? _promptCompletionWaiter;

  bool get _hasRolePlay {
    final rolePlay = widget.lesson.rolePlay;
    return widget.startAge >= 8 &&
        rolePlay != null &&
        rolePlay.turns.isNotEmpty;
  }

  bool get _inRolePlay => _hasRolePlay && !_rolePlayCompleted;

  ListeningRolePlayTurn? get _rolePlayTurn {
    if (!_inRolePlay) return null;
    final turns = widget.lesson.rolePlay!.turns;
    if (_rolePlayTurnIndex >= turns.length) return null;
    return turns[_rolePlayTurnIndex];
  }

  ListeningChallengeContent get _challenge =>
      widget.challenges[_challengeIndex];

  /// A HOMI line is playback-only. Every challenge and child role-play line
  /// opens the selected H20 microphone as soon as the coach prompt ends.
  bool get _shouldAutomaticallyRecord =>
      !_inRolePlay || _rolePlayTurn?.speaker == ListeningRolePlaySpeaker.child;

  bool get _usesIosOnDeviceRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      widget.iosSpeechInput != null;

  VoicePromptService get _prompt {
    final current = _voicePromptService;
    if (current != null) return current;
    _ownsVoicePromptService = true;
    return _voicePromptService = createVoicePromptService();
  }

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
    _request += 1;
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
    final request = ++_request;
    setState(() {
      _playingPrompt = true;
      _message = null;
    });
    try {
      // Own the selected H20 route before TTS starts and keep it through the
      // transition to recording. On iOS, allowing the prompt lease to be the
      // only owner makes AVAudioSession deactivate at didFinish, so the
      // automatic microphone opening can be lost during route renegotiation.
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!mounted || request != _request) return;
      final turn = _rolePlayTurn;
      if (turn != null) {
        if (turn.speaker == ListeningRolePlaySpeaker.homi) {
          await _speakPromptAndWait(turn.english, locale: 'en-US');
        } else {
          await _speakPromptAndWait('Bạn nói câu này nhé.');
        }
      } else {
        await _speakPromptAndWait(_challenge.prompt);
        if (!mounted || request != _request) return;
        await _speakPromptAndWait('Bạn nói đáp án bằng tiếng Anh nhé.');
      }
    } catch (_) {
      // The written prompt and recording controls stay available when TTS is
      // temporarily unavailable.
    } finally {
      if (mounted && request == _request) {
        setState(() => _playingPrompt = false);
      }
    }
    if (!mounted ||
        request != _request ||
        !_shouldAutomaticallyRecord ||
        _recording ||
        _busy) {
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
          // A small number of iOS AVSpeechSynthesizer route transitions do not
          // deliver didFinish. Stop the stale utterance so the H20 mic can
          // still open instead of leaving the child on a frozen screen.
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
    final expected = _expectedEnglish;
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
          // startLessonEnglishRecognition now owns the same native HFP lease
          // that kept the question on H20. Future prompts must reacquire it.
          widget.mediaService.handoffSelectedLessonOutputToNativeCapture();
        } catch (error) {
          debugPrint(
            'HOMI iOS challenge on-device recognition unavailable; '
            'using recorded/backend fallback: $error',
          );
          await iosSpeechInput.cancel().catchError((Object _) {});
        }
      }
      if (!usesIosSpeech) {
        await widget.mediaService.startRecording(
          lessonId: widget.lesson.id,
          sentenceNumber: _recordingNumber,
          lessonTitle: widget.lesson.titleVi,
          sentenceId: _attemptId,
          english: expected,
          vietnamese: _expectedVietnamese,
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
          lessonCode: widget.lesson.code,
          sentenceId: _attemptId,
          expectedEnglish: _expectedEnglish,
          recordingPath: recording.filePath,
          recordingDuration: recording.duration,
          attemptNumber: ++_attemptNumber,
          childAge: widget.startAge,
          acceptedVariants: _acceptedRecognitionVariants,
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
    // `_advance` has already finished the next coach prompt by this point.
    // Wait until the scoring state is released before claiming the H20 route;
    // otherwise the second challenge silently leaves its microphone closed.
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
              _expectedEnglish,
              candidate,
              acceptedVariants: _acceptedRecognitionVariants,
              requireAllExpectedTokens: false,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
    } on StreamingSpeechInputException catch (error) {
      debugPrint(
        'HOMI iOS challenge recognition returned no usable speech: '
        'code=${error.code ?? 'unknown'}',
      );
      return LessonAttemptOutcome.unclear;
    } catch (error) {
      debugPrint('HOMI iOS challenge recognition failed locally: $error');
      return LessonAttemptOutcome.unclear;
    }
  }

  Future<bool> _applyOutcome(LessonAttemptOutcome outcome) async {
    if (outcome == LessonAttemptOutcome.good) {
      return _advance();
    }
    // Never trap a child in an endless recognition loop. Offline engines can
    // consistently miss one short function word even when the answer was
    // spoken. Keep the tolerant match, then resolve the authored challenge
    // after the same two-attempt allowance used by Level Mission.
    if (_attemptNumber >= 2) {
      return _advance();
    }
    final message = switch (outcome) {
      LessonAttemptOutcome.unclear => 'Cô chưa nghe rõ. Bạn nói lại nhé.',
      LessonAttemptOutcome.retry || LessonAttemptOutcome.needsPractice =>
        _inRolePlay
            ? 'Bạn nói đầy đủ cả câu tiếng Anh nhé.'
            : 'Bạn nói lại đáp án bằng tiếng Anh nhé.',
      LessonAttemptOutcome.good => '',
    };
    if (mounted) setState(() => _message = message);
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      await _speakPromptAndWait(message);
    } catch (_) {
      // The written feedback remains visible; recording still resumes so a
      // temporary TTS outage never forces the child to use the phone.
    }
    return mounted;
  }

  Future<bool> _advance() async {
    if (_inRolePlay) {
      final nextIndex = _rolePlayTurnIndex + 1;
      if (nextIndex < widget.lesson.rolePlay!.turns.length) {
        setState(() {
          _rolePlayTurnIndex = nextIndex;
          _attemptNumber = 0;
          _message = null;
        });
        await _playCurrentPrompt(allowBusy: true);
        return true;
      }
      setState(() {
        _rolePlayCompleted = true;
        _attemptNumber = 0;
        _message = null;
      });
      await _playCurrentPrompt(allowBusy: true);
      return true;
    }

    if (_challengeIndex < widget.challenges.length - 1) {
      setState(() {
        _challengeIndex += 1;
        _attemptNumber = 0;
        _message = null;
      });
      await _playCurrentPrompt(allowBusy: true);
      return true;
    }
    if (mounted) Navigator.of(context).pop(true);
    return false;
  }

  Future<void> _restartRolePlay() async {
    if (!_hasRolePlay || _busy || _recording) return;
    setState(() {
      _rolePlayTurnIndex = 0;
      _attemptNumber = 0;
      _message = null;
    });
    await _playCurrentPrompt();
  }

  String get _expectedEnglish {
    final turn = _rolePlayTurn;
    return turn?.english ?? _challenge.correctAnswer;
  }

  String get _expectedVietnamese {
    final turn = _rolePlayTurn;
    return turn?.vietnamese ?? _challenge.correctVietnamese;
  }

  Iterable<String> get _acceptedRecognitionVariants {
    final turn = _rolePlayTurn;
    if (turn != null) return <String>[turn.english];
    for (final sentence in widget.lesson.sentences) {
      if (sentence.id == _challenge.targetId) {
        return sentence.recognitionVariants;
      }
    }
    return const <String>[];
  }

  String get _attemptId {
    final turn = _rolePlayTurn;
    return turn == null
        ? _challenge.id
        : '${widget.lesson.id}-roleplay-${_rolePlayTurnIndex + 1}';
  }

  int get _recordingNumber {
    return _inRolePlay ? _rolePlayTurnIndex + 1 : 100 + _challengeIndex + 1;
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
    final turn = _rolePlayTurn;
    final isHomiTurn = turn?.speaker == ListeningRolePlaySpeaker.homi;
    final rolePlay = widget.lesson.rolePlay;
    final totalSteps =
        widget.challenges.length + (_hasRolePlay ? rolePlay!.turns.length : 0);
    final currentStep = _inRolePlay
        ? _rolePlayTurnIndex
        : (_hasRolePlay ? rolePlay!.turns.length : 0) + _challengeIndex;
    final progress = totalSteps == 0 ? 0.0 : (currentStep / totalSteps);

    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-challenge-screen'),
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
                            : () => Navigator.of(context).pop(false),
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
                    _inRolePlay ? 'Đoạn hội thoại' : 'Thử thách nghe',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _inRolePlay
                        ? rolePlay!.scenarioVi
                        : 'Câu ${_challengeIndex + 1}/${widget.challenges.length}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _inRolePlay
                          ? _RolePlayCard(
                              turn: turn!,
                              openingHint: _rolePlayTurnIndex == 0
                                  ? rolePlay!.openingHint
                                  : null,
                            )
                          : _ChallengeCard(challenge: _challenge),
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
                  if (_inRolePlay && isHomiTurn)
                    FilledButton.icon(
                      onPressed: _playingPrompt || _busy ? null : _advance,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Tiếp tục'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('lesson-challenge-record-button'),
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
                  if (_inRolePlay) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy || _recording ? null : _restartRolePlay,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Làm lại đoạn hội thoại'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RolePlayCard extends StatelessWidget {
  const _RolePlayCard({required this.turn, this.openingHint});

  final ListeningRolePlayTurn turn;
  final String? openingHint;

  @override
  Widget build(BuildContext context) {
    final isChild = turn.speaker == ListeningRolePlaySpeaker.child;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isChild ? AppColors.lavenderSoft : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isChild ? AppColors.periwinkle : AppColors.lavenderBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isChild ? 'Lượt của bạn' : 'HOMI nói',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isChild ? AppColors.indigo : AppColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(turn.english, style: Theme.of(context).textTheme.titleLarge),
          if (isChild) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              turn.vietnamese,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            if (openingHint != null && openingHint!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                'Gợi ý: $openingHint',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.indigo,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge});

  final ListeningChallengeContent challenge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.lavenderBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Nghe và trả lời',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(challenge.prompt, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 18),
          for (final choice in challenge.choices) ...<Widget>[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                choice,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Hãy nói đáp án bằng tiếng Anh, không nói A hoặc B.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
