import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_guide_audio_library.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_recording_history_sheet.dart';
import 'lesson_review_screen.dart';
import 'listening_navigation_bar.dart';

class LessonPracticeScreen extends StatefulWidget {
  const LessonPracticeScreen({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    required this.progressStore,
    required this.mediaService,
    this.controller,
    this.guideAudioLibrary,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ConversationController? controller;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LessonGuideAudioLibrary? guideAudioLibrary;

  @override
  State<LessonPracticeScreen> createState() => _LessonPracticeScreenState();
}

class _LessonPracticeScreenState extends State<LessonPracticeScreen> {
  int _sentenceIndex = 0;
  bool _recording = false;
  bool _mediaBusy = false;
  String? _recordingPath;
  Duration? _recordingDuration;
  String? _message;
  bool _showSkip = false;
  _LessonCoachPopupKind? _coachPopupKind;
  final Set<int> _skippedSentenceIndexes = <int>{};
  Timer? _idleReminderTimer;
  Timer? _coachPopupTimer;
  late final LessonGuideAudioLibrary _guideAudioLibrary;
  bool _recordingStartPending = false;
  int _recordingStartRequest = 0;

  ListeningSentenceContent get _sentence =>
      widget.lesson.sentences[_sentenceIndex];

  @override
  void initState() {
    super.initState();
    _guideAudioLibrary = widget.guideAudioLibrary ?? LessonGuideAudioLibrary();
    unawaited(_loadStartingPoint());
  }

  @override
  void dispose() {
    _recordingStartRequest += 1;
    _cancelIdleReminder();
    _coachPopupTimer?.cancel();
    if (_recording) {
      widget.mediaService.cancelRecording();
    }
    widget.mediaService.stopPlayback();
    super.dispose();
  }

  Future<void> _loadStartingPoint() async {
    final currentSentence = await widget.progressStore.readCurrentSentence(
      widget.lesson.id,
    );
    Set<int> skippedSentences = <int>{};
    try {
      skippedSentences = await widget.progressStore.readSkippedSentences(
        widget.lesson.id,
      );
    } catch (_) {
      // A fresh or restricted browser session starts without skip markers.
    }
    final sentenceIndex = currentSentence.clamp(
      0,
      widget.lesson.sentences.length - 1,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = sentenceIndex;
      _skippedSentenceIndexes
        ..clear()
        ..addAll(skippedSentences);
    });
    await _activateCurrentSentence(autoPlay: true);
  }

  Future<void> _activateCurrentSentence({required bool autoPlay}) async {
    _cancelIdleReminder();
    _hideCoachPopup();
    if (mounted) {
      setState(() {
        _showSkip = false;
        _message = null;
      });
    }
    await _loadRecording();
    if (autoPlay && _sentence.audioUri != null) {
      await _runMediaAction(
        () => widget.mediaService.play(_sentence.audioUri!),
      );
    }
    _scheduleIdleReminder();
  }

  Future<void> _loadRecording() async {
    final path = await widget.mediaService.existingRecording(
      lessonId: widget.lesson.id,
      sentenceNumber: _sentence.number,
      sentenceId: _sentence.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _recordingPath = path;
      _recordingDuration = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lesson.sentences.length;
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-practice-screen'),
        body: Stack(
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  _LessonHeader(
                    current: _sentenceIndex + 1,
                    total: total,
                    onBack: _exitLesson,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        children: <Widget>[
                          _SentenceCard(
                            sentence: _sentence,
                            lessonType: widget.lesson.type,
                            current: _sentenceIndex + 1,
                            total: total,
                            onPlaySample: _playSample,
                            onPlayVietnamese: _playVietnamese,
                          ),
                          const SizedBox(height: 18),
                          _RecordButton(
                            recording: _recording,
                            busy: _mediaBusy,
                            onTap: _toggleRecording,
                            onLongPressStart: _startRecording,
                            onLongPressEnd: _stopRecording,
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _recordingPath == null
                                ? const SizedBox(height: 14)
                                : Padding(
                                    key: ValueKey(_recordingPath),
                                    padding: const EdgeInsets.only(top: 16),
                                    child: _RecordingCard(
                                      duration: _recordingDuration,
                                      onPlay: _playRecording,
                                    ),
                                  ),
                          ),
                          if (_message != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                          const SizedBox(height: 18),
                          if (_recordingPath != null)
                            _PostRecordingActions(
                              busy: _recording || _mediaBusy,
                              onPlaySample: _playSample,
                              onPlayRecording: _playRecording,
                              onRecordAgain: _startRecording,
                              onContinue: _continue,
                              onPrevious: _previous,
                              canGoPrevious: _sentenceIndex > 0,
                              finalSentence: _sentenceIndex == total - 1,
                            )
                          else
                            _LessonNavigationActions(
                              current: _sentenceIndex,
                              total: total,
                              busy: _recording || _mediaBusy,
                              onPrevious: _previous,
                              onContinue: _continue,
                            ),
                          if (_showSkip && _recordingPath == null) ...<Widget>[
                            const SizedBox(height: 10),
                            TextButton.icon(
                              key: const Key('skip-lesson-sentence'),
                              onPressed: _recording || _mediaBusy
                                  ? null
                                  : _skip,
                              icon: const Icon(Icons.fast_forward_rounded),
                              label: Text(context.tr('Bỏ qua câu này', '跳过本句')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: curved, child: child),
                    );
                  },
                  child: _coachPopupKind == null
                      ? const SizedBox.shrink()
                      : _LessonCoachPopup(
                          key: ValueKey(_coachPopupKind),
                          kind: _coachPopupKind!,
                        ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: ListeningNavigationBar(
          onCommunication: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onHistory: _showHistory,
        ),
      ),
    );
  }

  Future<void> _playSample() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final uri = _sentence.audioUri;
    if (uri == null) {
      _setMessage(
        context.tr(
          'Audio mẫu sẽ sẵn sàng sau khi cập nhật thư viện Cloudinary.',
          'Cloudinary 音频库更新后即可播放示范音频。',
        ),
      );
      _scheduleIdleReminder();
      return;
    }
    await _runMediaAction(() => widget.mediaService.play(uri));
    if (_recordingPath == null) {
      _scheduleIdleReminder();
    }
  }

  Future<void> _playVietnamese() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final uri = _sentence.vietnameseAudioUri;
    if (uri == null) {
      _setMessage(
        context.tr(
          'Audio tiếng Việt sẽ được gắn sau. Nút đã sẵn sàng.',
          '越南语音频稍后接入，按钮已准备好。',
        ),
      );
      if (_recordingPath == null) {
        _scheduleIdleReminder();
      }
      return;
    }
    await _runMediaAction(() => widget.mediaService.play(uri));
    if (_recordingPath == null) {
      _scheduleIdleReminder();
    }
  }

  Future<void> _playRecording() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final path = _recordingPath;
    if (path == null) {
      return;
    }
    final parsed = Uri.tryParse(path);
    final uri = parsed != null && parsed.hasScheme ? parsed : Uri.file(path);
    await _runMediaAction(() => widget.mediaService.play(uri));
  }

  Future<void> _runMediaAction(Future<void> Function() action) async {
    if (_mediaBusy || _recording) {
      return;
    }
    setState(() {
      _mediaBusy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_recording || _mediaBusy) {
      return;
    }
    final request = ++_recordingStartRequest;
    _cancelIdleReminder();
    _hideCoachPopup();
    setState(() {
      _mediaBusy = true;
      _recordingStartPending = true;
      _message = null;
    });
    try {
      await _playGuideCue(LessonGuideCue.record);
      if (!mounted || request != _recordingStartRequest) {
        return;
      }
      await widget.mediaService.startRecording(
        lessonId: widget.lesson.id,
        sentenceNumber: _sentence.number,
        lessonTitle: widget.lesson.titleVi,
        sentenceId: _sentence.id,
        english: _sentence.english,
        vietnamese: _sentence.vietnamese,
      );
      if (!mounted || request != _recordingStartRequest) {
        await widget.mediaService.cancelRecording();
        return;
      }
      if (mounted) {
        setState(() {
          _recording = true;
          _mediaBusy = false;
          _recordingStartPending = false;
        });
      }
    } catch (error) {
      if (request != _recordingStartRequest) {
        await widget.mediaService.cancelRecording();
        return;
      }
      if (mounted) {
        setState(() {
          _mediaBusy = false;
          _recordingStartPending = false;
        });
      }
      _setMessage(error.toString());
    }
  }

  Future<void> _stopRecording() async {
    if (_recordingStartPending && !_recording) {
      _recordingStartRequest += 1;
      _recordingStartPending = false;
      await widget.mediaService.stopPlayback();
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
      return;
    }
    if (!_recording || _mediaBusy) {
      return;
    }
    setState(() => _mediaBusy = true);
    try {
      final recording = await widget.mediaService.stopRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _recording = false;
        _mediaBusy = false;
        _recordingPath = recording.filePath;
        _recordingDuration = recording.duration;
        _message = null;
        _skippedSentenceIndexes.remove(_sentenceIndex);
      });
      try {
        await widget.progressStore.clearSkippedSentence(
          widget.lesson.id,
          _sentenceIndex,
        );
      } catch (_) {
        // The successful recording remains usable even if progress sync fails.
      }
      _showCoachPopup(_LessonCoachPopupKind.praise);
      unawaited(_playGuideCue(LessonGuideCue.praise));
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _mediaBusy = false;
        });
      }
      _setMessage(error.toString());
      if (_recordingPath == null) {
        _scheduleIdleReminder();
      }
    }
  }

  Future<void> _continue() =>
      _advanceToNext(playNextGuide: true, autoPlaySentence: false);

  Future<void> _advanceToNext({
    required bool playNextGuide,
    required bool autoPlaySentence,
  }) async {
    if (_recording || _mediaBusy) {
      return;
    }
    _cancelIdleReminder();
    _hideCoachPopup();
    await widget.progressStore.saveLesson(widget.lesson.id, _sentenceIndex + 1);
    if (!mounted) {
      return;
    }
    if (_sentenceIndex == widget.lesson.sentences.length - 1) {
      await widget.progressStore.saveCurrentSentence(
        widget.lesson.id,
        _sentenceIndex,
      );
      await _openReview();
      return;
    }
    final nextSentence = _sentenceIndex + 1;
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      nextSentence,
    );
    if (!mounted) {
      return;
    }
    if (playNextGuide) {
      await _playGuideCueWithBusyState(LessonGuideCue.next);
      if (!mounted) {
        return;
      }
    }
    setState(() {
      _sentenceIndex = nextSentence;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    await _activateCurrentSentence(autoPlay: autoPlaySentence);
  }

  Future<void> _previous() async {
    if (_sentenceIndex == 0) {
      return;
    }
    _cancelIdleReminder();
    _hideCoachPopup();
    await _playGuideCueWithBusyState(LessonGuideCue.praise);
    if (!mounted) {
      return;
    }
    final previousSentence = _sentenceIndex - 1;
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      previousSentence,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = previousSentence;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    await _activateCurrentSentence(autoPlay: false);
  }

  Future<void> _exitLesson() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      _sentenceIndex,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    _skippedSentenceIndexes.add(_sentenceIndex);
    try {
      await widget.progressStore.saveSkippedSentence(
        widget.lesson.id,
        _sentenceIndex,
      );
    } catch (_) {
      // Keep the current-session marker when local persistence is unavailable.
    }
    if (mounted) {
      setState(() {
        _showSkip = false;
        _message = context.tr(
          'Không sao, mình đánh dấu “Chưa ghi âm” và học tiếp nhé.',
          '没关系，已标记为“尚未录音”，继续学习吧。',
        );
      });
    }
    await _playGuideCueWithBusyState(LessonGuideCue.skip);
    await _advanceToNext(playNextGuide: false, autoPlaySentence: true);
  }

  Future<void> _openReview() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final unrecordedSentenceIndexes = await _readUnrecordedSentenceIndexes();
    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => LessonReviewScreen(
          language: widget.language,
          lesson: widget.lesson,
          mediaService: widget.mediaService,
          unrecordedSentenceIndexes: unrecordedSentenceIndexes,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result < 0) {
      await _showCompletion();
      return;
    }
    final retryIndex = result.clamp(0, widget.lesson.sentences.length - 1);
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      retryIndex,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = retryIndex;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    await _activateCurrentSentence(autoPlay: true);
  }

  Future<Set<int>> _readUnrecordedSentenceIndexes() async {
    final recordings = await Future.wait<String?>(
      widget.lesson.sentences.map(
        (sentence) => widget.mediaService.existingRecording(
          lessonId: widget.lesson.id,
          sentenceNumber: sentence.number,
          sentenceId: sentence.id,
        ),
      ),
    );
    return <int>{
      for (var index = 0; index < recordings.length; index++)
        if (recordings[index] == null) index,
    };
  }

  void _scheduleIdleReminder() {
    _cancelIdleReminder();
    if (!mounted || _recording || _recordingPath != null) {
      return;
    }
    _idleReminderTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _recording || _recordingPath != null) {
        return;
      }
      setState(() => _message = null);
      _showCoachPopup(_LessonCoachPopupKind.firstReminder);
      unawaited(_playGuideCue(LessonGuideCue.idleFirst));
      _idleReminderTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted || _recording || _recordingPath != null) {
          return;
        }
        setState(() {
          _showSkip = true;
          _message = null;
        });
        _showCoachPopup(_LessonCoachPopupKind.secondReminder);
        unawaited(_playGuideCue(LessonGuideCue.idleSecond));
      });
    });
  }

  void _cancelIdleReminder() {
    _idleReminderTimer?.cancel();
    _idleReminderTimer = null;
  }

  Future<Uri?> _randomGuideUri(LessonGuideCue cue) async {
    try {
      return await _guideAudioLibrary.randomUri(
        cue,
        startAge: widget.startAge,
        endAge: widget.endAge,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _playGuideCue(LessonGuideCue cue) async {
    final uri = await _randomGuideUri(cue);
    if (uri == null || !mounted) {
      return false;
    }
    try {
      await widget.mediaService.playToCompletion(uri);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _playGuideCueWithBusyState(LessonGuideCue cue) async {
    if (!mounted) {
      return;
    }
    setState(() => _mediaBusy = true);
    try {
      await _playGuideCue(cue);
    } finally {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  void _showCoachPopup(_LessonCoachPopupKind kind) {
    _coachPopupTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _coachPopupKind = kind);
    _coachPopupTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _coachPopupKind != kind) {
        return;
      }
      setState(() => _coachPopupKind = null);
      _coachPopupTimer = null;
    });
  }

  void _hideCoachPopup() {
    _coachPopupTimer?.cancel();
    _coachPopupTimer = null;
    if (mounted && _coachPopupKind != null) {
      setState(() => _coachPopupKind = null);
    }
  }

  Future<void> _showCompletion() async {
    final guideUri = await _randomGuideUri(LessonGuideCue.ending);
    if (!mounted) {
      return;
    }
    final uri = guideUri ?? widget.lesson.outroAudioUri;
    if (uri != null) {
      unawaited(widget.mediaService.play(uri).catchError((_) {}));
    }
    final leaveLesson = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.lavenderSoft,
      builder: (sheetContext) => _CompletionSheet(
        message: widget.lesson.outro,
        onClose: () => Navigator.of(sheetContext).pop(true),
        onReview: () => Navigator.of(sheetContext).pop(false),
      ),
    );
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    if (leaveLesson == true) {
      Navigator.of(context).pop();
    } else if (leaveLesson == false) {
      try {
        await widget.progressStore.clearSkippedSentences(widget.lesson.id);
      } catch (_) {
        // Restarting still works when local progress storage is unavailable.
      }
      await widget.progressStore.saveCurrentSentence(widget.lesson.id, 0);
      if (!mounted) {
        return;
      }
      setState(() {
        _sentenceIndex = 0;
        _skippedSentenceIndexes.clear();
        _recordingPath = null;
        _recordingDuration = null;
        _message = null;
      });
      await _activateCurrentSentence(autoPlay: true);
    }
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          LessonRecordingHistorySheet(mediaService: widget.mediaService),
    );
  }

  void _setMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _message = message);
  }
}

class _LessonHeader extends StatelessWidget {
  const _LessonHeader({
    required this.current,
    required this.total,
    required this.onBack,
  });

  final int current;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: context.tr('Quay lại', '返回'),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.lavenderBorder),
            ),
            child: Text(
              context.tr('Câu $current/$total', '第 $current/$total 句'),
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppColors.lavenderBorder),
            ),
            child: const Icon(Icons.star_rounded, color: Color(0xFFFFC75B)),
          ),
        ],
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({
    required this.sentence,
    required this.lessonType,
    required this.current,
    required this.total,
    required this.onPlaySample,
    required this.onPlayVietnamese,
  });

  final ListeningSentenceContent sentence;
  final ListeningLessonType lessonType;
  final int current;
  final int total;
  final VoidCallback onPlaySample;
  final VoidCallback onPlayVietnamese;

  @override
  Widget build(BuildContext context) {
    final englishSize = sentence.english.length > 55
        ? 28.0
        : sentence.english.length > 30
        ? 34.0
        : 46.0;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.lavenderBorder),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10142451),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          if (lessonType != ListeningLessonType.standard) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: lessonType == ListeningLessonType.song
                    ? const Color(0xFFFFF1F5)
                    : AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    lessonType == ListeningLessonType.song
                        ? Icons.music_note_rounded
                        : Icons.forum_rounded,
                    size: 18,
                    color: lessonType == ListeningLessonType.song
                        ? AppColors.coral
                        : AppColors.indigo,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    lessonType == ListeningLessonType.song
                        ? context.tr(
                            'Dòng $current/$total',
                            '歌词 $current/$total',
                          )
                        : context.tr(
                            '${sentence.voice.isEmpty ? 'Lượt thoại' : sentence.voice} · $current/$total',
                            '${sentence.voice.isEmpty ? '对话角色' : sentence.voice} · $current/$total',
                          ),
                    style: const TextStyle(
                      color: AppColors.indigoDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            sentence.english,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: englishSize,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            sentence.vietnamese,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.indigo,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 20),
          const Icon(
            Icons.graphic_eq_rounded,
            size: 52,
            color: AppColors.periwinkle,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('play-lesson-sample'),
                  onPressed: onPlaySample,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: Text(context.tr('Nghe mẫu', '听示范')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.lavenderSoft,
                    foregroundColor: AppColors.indigoDark,
                    side: const BorderSide(color: AppColors.lavenderBorder),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('play-vietnamese-meaning'),
                  onPressed: onPlayVietnamese,
                  icon: const Icon(Icons.translate_rounded),
                  label: Text(context.tr('Nghe tiếng Việt', '听越南语')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFFFFF6EE),
                    foregroundColor: AppColors.indigoDark,
                    side: const BorderSide(color: Color(0xFFFFD8C4)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.busy,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final bool recording;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      liveRegion: recording,
      label: recording
          ? context.tr('Đang ghi âm, thả để lưu', '正在录音，松开保存')
          : context.tr('Nhấn và giữ để ghi âm', '长按录音'),
      child: GestureDetector(
        onTap: busy ? null : onTap,
        onLongPressStart: busy ? null : (_) => onLongPressStart(),
        onLongPressEnd: busy ? null : (_) => onLongPressEnd(),
        child: AnimatedContainer(
          key: const Key('record-lesson-sentence'),
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: recording ? AppColors.coral : AppColors.indigo,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x303D4DD6),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              else
                Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.tr(
                    recording ? 'Thả để lưu bản ghi' : 'Nhấn và giữ để ghi âm',
                    recording ? '松开保存录音' : '长按录音',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LessonCoachPopupKind { praise, firstReminder, secondReminder }

class _LessonCoachPopup extends StatefulWidget {
  const _LessonCoachPopup({required this.kind, super.key});

  final _LessonCoachPopupKind kind;

  @override
  State<_LessonCoachPopup> createState() => _LessonCoachPopupState();
}

class _LessonCoachPopupState extends State<_LessonCoachPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final praise = widget.kind == _LessonCoachPopupKind.praise;
    final secondReminder = widget.kind == _LessonCoachPopupKind.secondReminder;
    final title = switch (widget.kind) {
      _LessonCoachPopupKind.praise => context.tr(
        'Con làm tuyệt lắm!',
        '你做得太棒了！',
      ),
      _LessonCoachPopupKind.firstReminder => context.tr(
        'Đến lượt con rồi!',
        '轮到你啦！',
      ),
      _LessonCoachPopupKind.secondReminder => context.tr(
        'Mình thử nhẹ nhàng nhé',
        '我们轻松试一试吧',
      ),
    };
    final message = switch (widget.kind) {
      _LessonCoachPopupKind.praise => context.tr(
        'Bản ghi đã được lưu. Con có thể nghe lại hoặc tự bấm sang câu tiếp theo.',
        '录音已保存。你可以回听，或自己点击进入下一句。',
      ),
      _LessonCoachPopupKind.firstReminder => context.tr(
        'Nhấn và giữ nút micro để đọc theo câu mẫu nhé.',
        '请长按麦克风按钮，跟着示范句朗读。',
      ),
      _LessonCoachPopupKind.secondReminder => context.tr(
        'Con có thể nghe mẫu lại, nói chậm hơn hoặc chọn bỏ qua câu này.',
        '你可以重听示范、慢慢说，或选择跳过本句。',
      ),
    };
    final surface = praise
        ? const Color(0xFFF0FBF5)
        : secondReminder
        ? const Color(0xFFFFF7EA)
        : const Color(0xFFF2F1FF);
    final border = praise
        ? const Color(0xFFAFE4C3)
        : secondReminder
        ? const Color(0xFFFFD89A)
        : AppColors.lavenderBorder;
    final accent = praise
        ? AppColors.success
        : secondReminder
        ? const Color(0xFFE58A2B)
        : AppColors.indigo;

    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      child: ColoredBox(
        color: const Color(0x24142451),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                key: Key('lesson-coach-popup-${widget.kind.name}'),
                color: surface,
                elevation: 18,
                shadowColor: const Color(0x553D4DD6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: BorderSide(color: border, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        height: 132,
                        width: 210,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final progress = _controller.value;
                            return Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Positioned(
                                  left: 8,
                                  top: 24 - (progress * 8),
                                  child: Transform.rotate(
                                    angle: -0.2 + (progress * 0.18),
                                    child: Icon(
                                      praise
                                          ? Icons.celebration_rounded
                                          : Icons.auto_awesome_rounded,
                                      color: const Color(0xFFFFB84D),
                                      size: 34,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 12,
                                  top: 14 + (progress * 8),
                                  child: Icon(
                                    secondReminder
                                        ? Icons.favorite_rounded
                                        : Icons.star_rounded,
                                    color: secondReminder
                                        ? AppColors.coral
                                        : AppColors.periwinkle,
                                    size: 31,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(0, -5 * progress),
                                  child: Transform.rotate(
                                    angle: -0.025 + (progress * 0.05),
                                    child: Transform.scale(
                                      scale: 0.97 + (progress * 0.05),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                          child: Image.asset(
                            'assets/images/mascot-robot.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostRecordingActions extends StatelessWidget {
  const _PostRecordingActions({
    required this.busy,
    required this.onPlaySample,
    required this.onPlayRecording,
    required this.onRecordAgain,
    required this.onContinue,
    required this.onPrevious,
    required this.canGoPrevious,
    required this.finalSentence,
  });

  final bool busy;
  final VoidCallback onPlaySample;
  final VoidCallback onPlayRecording;
  final VoidCallback onRecordAgain;
  final VoidCallback onContinue;
  final VoidCallback onPrevious;
  final bool canGoPrevious;
  final bool finalSentence;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _CompactAction(
        icon: Icons.volume_up_rounded,
        label: context.tr('Nghe câu mẫu', '听示范'),
        onPressed: busy ? null : onPlaySample,
      ),
      _CompactAction(
        icon: Icons.play_circle_rounded,
        label: context.tr('Nghe bản ghi', '听录音'),
        onPressed: busy ? null : onPlayRecording,
      ),
      _CompactAction(
        icon: Icons.mic_rounded,
        label: context.tr('Ghi âm lại', '重新录音'),
        onPressed: busy ? null : onRecordAgain,
      ),
      _CompactAction(
        key: const Key('continue-lesson-sentence'),
        icon: finalSentence
            ? Icons.fact_check_rounded
            : Icons.arrow_forward_rounded,
        label: context.tr(
          finalSentence ? 'Ôn tập' : 'Câu tiếp theo',
          finalSentence ? '复习' : '下一句',
        ),
        filled: true,
        onPressed: busy ? null : onContinue,
      ),
    ];
    return Column(
      children: <Widget>[
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.45,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: actions,
        ),
        if (canGoPrevious) ...<Widget>[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('previous-lesson-sentence'),
            onPressed: busy ? null : onPrevious,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(context.tr('Câu trước', '上一句')),
          ),
        ],
      ],
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, textAlign: TextAlign.center, maxLines: 2),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center, maxLines: 2),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.indigo,
        side: const BorderSide(color: AppColors.lavenderBorder),
      ),
    );
  }
}

class _LessonNavigationActions extends StatelessWidget {
  const _LessonNavigationActions({
    required this.current,
    required this.total,
    required this.busy,
    required this.onPrevious,
    required this.onContinue,
  });

  final int current;
  final int total;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('previous-lesson-sentence'),
            onPressed: current == 0 || busy ? null : onPrevious,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(62),
              foregroundColor: AppColors.indigo,
              side: const BorderSide(color: AppColors.lavenderBorder),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(context.tr('Câu trước', '上一句'), maxLines: 1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('continue-lesson-sentence'),
            onPressed: busy ? null : onContinue,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(62),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconAlignment: IconAlignment.end,
            icon: Icon(
              current == total - 1
                  ? Icons.fact_check_rounded
                  : Icons.arrow_forward_rounded,
            ),
            label: Text(
              context.tr(
                current == total - 1 ? 'Ôn tập' : 'Tiếp tục',
                current == total - 1 ? '复习' : '继续',
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.duration, required this.onPlay});

  final Duration? duration;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final seconds = duration?.inSeconds.clamp(0, 99);
    final durationLabel = seconds == null
        ? context.tr('Đã lưu', '已保存')
        : '00:${seconds.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lavenderBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('Bản ghi của con', '孩子的录音'),
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              IconButton(
                key: const Key('play-lesson-recording'),
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: context.tr('Nghe lại', '回放'),
              ),
              const Expanded(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: AppColors.periwinkle,
                  size: 44,
                ),
              ),
              Text(
                durationLabel,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({
    required this.message,
    required this.onClose,
    required this.onReview,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback onReview;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 680;
    final mascotSize = compact ? 170.0 : 220.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, compact ? 0 : 6, 24, 28),
      child: Column(
        key: const Key('completion-celebration'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            height: mascotSize + 34,
            child: AnimatedBuilder(
              animation: _celebrationController,
              builder: (context, child) {
                final progress = _celebrationController.value;
                final pulse = 0.96 + (progress * 0.08);
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 18,
                      top: 34 - (progress * 12),
                      child: Transform.rotate(
                        angle: -0.18 + (progress * 0.2),
                        child: const Icon(
                          Icons.celebration_rounded,
                          color: Color(0xFFFF9C6C),
                          size: 46,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 26,
                      top: 14 + (progress * 10),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFFFC75B),
                        size: 42,
                      ),
                    ),
                    Positioned(
                      left: 42,
                      bottom: 18 + (progress * 8),
                      child: const Icon(
                        Icons.star_rounded,
                        color: AppColors.periwinkle,
                        size: 34,
                      ),
                    ),
                    Positioned(
                      right: 48,
                      bottom: 28 - (progress * 6),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.coral,
                        size: 34,
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, -6 * progress),
                      child: Transform.scale(scale: pulse, child: child),
                    ),
                  ],
                );
              },
              child: SizedBox(
                width: mascotSize,
                height: mascotSize,
                child: Image.asset(
                  'assets/images/mascot-robot.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          Text(
            context.tr('Con đã hoàn thành!', '学习完成！'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.indigoDark,
              fontSize: compact ? 28 : 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.45),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('finish-listening-lesson'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.check_circle_rounded),
              label: Text(context.tr('Về chủ đề', '返回主题')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('review-listening-lesson'),
            onPressed: widget.onReview,
            icon: const Icon(Icons.replay_rounded),
            label: Text(context.tr('Luyện lại từ đầu', '从头复习')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.indigo,
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
