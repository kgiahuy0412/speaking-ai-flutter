import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_media_service.dart';
import '../domain/listening_content.dart';

enum LessonReviewMode { overview, learned }

enum LessonReviewAction { nextLesson, restartLesson, returnToListening }

class LessonReviewScreen extends StatefulWidget {
  const LessonReviewScreen({
    required this.language,
    required this.lesson,
    required this.mediaService,
    this.unrecordedSentenceIndexes = const <int>{},
    this.learnNowBuilder,
    this.mode = LessonReviewMode.overview,
    this.hasNextLesson = false,
    super.key,
  });

  final DisplayLanguage language;
  final ListeningLessonContent lesson;
  final LessonMediaService mediaService;
  final Set<int> unrecordedSentenceIndexes;
  final WidgetBuilder? learnNowBuilder;
  final LessonReviewMode mode;
  final bool hasNextLesson;

  @override
  State<LessonReviewScreen> createState() => _LessonReviewScreenState();
}

class _LessonReviewScreenState extends State<LessonReviewScreen> {
  static const int _completionDelaySeconds = 6;

  int? _playingIndex;
  bool _autoPlayActive = false;
  int _playbackRequest = 0;
  int _completionUnlockSeconds = _completionDelaySeconds;
  String? _message;
  Timer? _reviewGapTimer;
  Timer? _completionUnlockTimer;
  Completer<bool>? _reviewGapCompleter;
  bool _handingOffMediaPlayback = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == LessonReviewMode.overview) {
      _startCompletionUnlockTimer();
    } else {
      _completionUnlockSeconds = 0;
    }
  }

  @override
  void dispose() {
    _playbackRequest += 1;
    _cancelReviewGap();
    _completionUnlockTimer?.cancel();
    if (!_handingOffMediaPlayback) {
      widget.mediaService.stopPlayback();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-review-screen'),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 20, 8),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: context.tr('Quay lại bài học', '返回课程'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _title(context),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('replay-lesson-review'),
                        onPressed: _playReview,
                        icon: const Icon(Icons.replay_rounded),
                        tooltip: context.tr('Phát lại từ đầu', '从头播放'),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  itemCount: widget.lesson.sentences.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final sentence = widget.lesson.sentences[index];
                    return _ReviewSentenceTile(
                      index: index,
                      sentence: sentence,
                      lessonType: widget.lesson.type,
                      playing: _playingIndex == index,
                      recordingStatus: widget.mode == LessonReviewMode.learned
                          ? widget.unrecordedSentenceIndexes.contains(index)
                                ? _ReviewRecordingStatus.unrecorded
                                : _ReviewRecordingStatus.recorded
                          : null,
                      redesigned: widget.mode == LessonReviewMode.overview,
                      featured:
                          widget.mode == LessonReviewMode.overview &&
                          index == 0,
                      onPlay: () => _playSentence(index),
                    );
                  },
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: widget.mode == LessonReviewMode.learned
                      ? _buildLearnedActions(context)
                      : _buildOverviewActions(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title(BuildContext context) => widget.mode == LessonReviewMode.learned
      ? context.tr('Đã học', '已学习')
      : context.tr('Nghe tổng quan', '整体听一遍');

  Widget _buildOverviewActions(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('auto-play-lesson-review'),
            onPressed: _toggleAutoReview,
            icon: Icon(
              _autoPlayActive
                  ? Icons.graphic_eq_rounded
                  : Icons.play_circle_outline_rounded,
              size: 20,
            ),
            label: Text(
              context.tr('Tự động phát', '自动播放'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: _autoPlayActive
                  ? AppColors.indigo
                  : Colors.white,
              foregroundColor: _autoPlayActive
                  ? Colors.white
                  : AppColors.indigo,
              side: BorderSide(
                color: _autoPlayActive
                    ? AppColors.indigo
                    : AppColors.lavenderBorder,
                width: 1.5,
              ),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 260),
            opacity: _completionUnlockSeconds == 0 ? 1 : 0.48,
            child: FilledButton.icon(
              key: const Key('complete-lesson-review'),
              onPressed: _completionUnlockSeconds == 0 ? _startLearning : null,
              icon: Icon(
                _completionUnlockSeconds == 0
                    ? Icons.play_arrow_rounded
                    : Icons.lock_clock_rounded,
                size: 20,
              ),
              label: Text(
                _completionUnlockSeconds == 0
                    ? context.tr('Học ngay', '立即学习')
                    : context.tr(
                        'Học ngay sau $_completionUnlockSeconds giây',
                        '$_completionUnlockSeconds 秒后开始学习',
                      ),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                disabledBackgroundColor: AppColors.periwinkle,
                disabledForegroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLearnedActions(BuildContext context) {
    final primaryAction = widget.hasNextLesson
        ? LessonReviewAction.nextLesson
        : LessonReviewAction.returnToListening;
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('post-lesson-primary-action'),
            onPressed: () => _finishLearnedReview(primaryAction),
            icon: Icon(
              widget.hasNextLesson
                  ? Icons.skip_next_rounded
                  : Icons.headphones_rounded,
              size: 20,
            ),
            label: Text(
              widget.hasNextLesson
                  ? context.tr('Bài tiếp theo', '下一课')
                  : context.tr('Luyện nghe', '听力练习'),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: AppColors.indigo,
              side: const BorderSide(
                color: AppColors.lavenderBorder,
                width: 1.5,
              ),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            key: const Key('restart-lesson-review'),
            onPressed: () =>
                _finishLearnedReview(LessonReviewAction.restartLesson),
            icon: const Icon(Icons.replay_rounded, size: 20),
            label: Text(
              context.tr('Luyện lại từ đầu', '从头练习'),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _finishLearnedReview(LessonReviewAction action) async {
    await _stopAutoReview();
    if (!mounted) {
      return;
    }
    // The route receiving this result may start another lesson before the
    // pop animation disposes this review route. Playback is already stopped,
    // so dispose must not stop the newly started audio on the shared service.
    _handingOffMediaPlayback = true;
    Navigator.of(context).pop(action);
  }

  Future<void> _startLearning() async {
    await _stopAutoReview();
    if (!mounted) {
      return;
    }
    _handingOffMediaPlayback = true;
    final builder = widget.learnNowBuilder;
    if (builder == null) {
      Navigator.of(context).pop(-1);
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement<void, void>(MaterialPageRoute<void>(builder: builder));
  }

  Future<void> _toggleAutoReview() async {
    if (_autoPlayActive) {
      await _stopAutoReview();
      return;
    }
    await _playReview();
  }

  void _startCompletionUnlockTimer() {
    _completionUnlockTimer?.cancel();
    _completionUnlockTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_completionUnlockSeconds <= 1) {
        timer.cancel();
        _completionUnlockTimer = null;
        setState(() => _completionUnlockSeconds = 0);
        return;
      }
      setState(() => _completionUnlockSeconds--);
    });
  }

  Future<void> _playReview() async {
    final request = ++_playbackRequest;
    _cancelReviewGap();
    await widget.mediaService.stopPlayback();
    if (!mounted || request != _playbackRequest) {
      return;
    }
    setState(() {
      _autoPlayActive = true;
      _message = null;
      _playingIndex = null;
    });

    final fullAudio = widget.lesson.fullAudioUri;
    if (fullAudio != null &&
        widget.lesson.type != ListeningLessonType.standard) {
      try {
        await widget.mediaService.playToCompletion(fullAudio);
      } catch (error) {
        if (request == _playbackRequest) {
          _setMessage(error.toString());
        }
      } finally {
        if (mounted && request == _playbackRequest) {
          setState(() {
            _autoPlayActive = false;
            _playingIndex = null;
          });
        }
      }
      return;
    }

    for (var index = 0; index < widget.lesson.sentences.length; index++) {
      if (!mounted || request != _playbackRequest) {
        return;
      }
      setState(() => _playingIndex = index);
      final uri = widget.lesson.sentences[index].audioUri;
      if (uri != null) {
        try {
          await widget.mediaService.playToCompletion(uri);
        } catch (_) {}
      }
      if (!mounted || request != _playbackRequest) {
        return;
      }
      if (!await _waitReviewGap()) {
        return;
      }
    }
    if (mounted && request == _playbackRequest) {
      setState(() {
        _autoPlayActive = false;
        _playingIndex = null;
        if (widget.lesson.sentences.every(
          (sentence) => sentence.audioUri == null,
        )) {
          _message = context.tr(
            'Danh sách đã sẵn sàng; audio Cloudinary sẽ được gắn sau.',
            '列表已准备好；Cloudinary 音频稍后接入。',
          );
        }
      });
    }
  }

  Future<void> _playSentence(int index) async {
    await _stopAutoReview();
    if (!mounted) {
      return;
    }
    final request = ++_playbackRequest;
    final sentence = widget.lesson.sentences[index];
    if (sentence.audioUri == null) {
      _setMessage(context.tr('Audio câu này sẽ được gắn sau.', '本句音频稍后接入。'));
      return;
    }
    if (mounted) {
      setState(() => _playingIndex = index);
    }
    try {
      await widget.mediaService.playToCompletion(sentence.audioUri!);
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted && request == _playbackRequest) {
        setState(() => _playingIndex = null);
      }
    }
  }

  Future<void> _stopAutoReview() async {
    _playbackRequest += 1;
    _cancelReviewGap();
    await widget.mediaService.stopPlayback();
    if (mounted) {
      setState(() {
        _autoPlayActive = false;
        _playingIndex = null;
      });
    }
  }

  void _setMessage(String message) {
    if (mounted) {
      setState(() => _message = message);
    }
  }

  Future<bool> _waitReviewGap() {
    _cancelReviewGap();
    final completer = Completer<bool>();
    _reviewGapCompleter = completer;
    _reviewGapTimer = Timer(const Duration(seconds: 1), () {
      _reviewGapTimer = null;
      _reviewGapCompleter = null;
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    });
    return completer.future;
  }

  void _cancelReviewGap() {
    _reviewGapTimer?.cancel();
    _reviewGapTimer = null;
    final completer = _reviewGapCompleter;
    _reviewGapCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }
}

class _ReviewSentenceTile extends StatelessWidget {
  const _ReviewSentenceTile({
    required this.index,
    required this.sentence,
    required this.lessonType,
    required this.playing,
    required this.recordingStatus,
    required this.redesigned,
    required this.featured,
    required this.onPlay,
  });

  final int index;
  final ListeningSentenceContent sentence;
  final ListeningLessonType lessonType;
  final bool playing;
  final _ReviewRecordingStatus? recordingStatus;
  final bool redesigned;
  final bool featured;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final statusAccent = switch (recordingStatus) {
      _ReviewRecordingStatus.recorded => AppColors.success,
      _ReviewRecordingStatus.unrecorded => AppColors.coral,
      null => AppColors.indigo,
    };
    final tileColor = switch (recordingStatus) {
      _ReviewRecordingStatus.recorded => AppColors.successSoft,
      _ReviewRecordingStatus.unrecorded => AppColors.coralSoft,
      null => Colors.white,
    };
    final statusBorder = switch (recordingStatus) {
      _ReviewRecordingStatus.recorded => AppColors.success.withValues(
        alpha: 0.48,
      ),
      _ReviewRecordingStatus.unrecorded => AppColors.coral.withValues(
        alpha: 0.48,
      ),
      null => AppColors.lavenderBorder,
    };

    return AnimatedContainer(
      key: ValueKey('review-sentence-tile-${index + 1}'),
      duration: const Duration(milliseconds: 220),
      padding: redesigned
          ? EdgeInsets.fromLTRB(14, featured ? 8 : 10, 8, featured ? 8 : 10)
          : const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: playing ? AppColors.indigo : statusBorder,
          width: playing || recordingStatus != null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: recordingStatus == null
                ? AppColors.lavenderSoft
                : statusAccent.withValues(alpha: 0.1),
            foregroundColor: statusAccent,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sentence.english,
                  key: ValueKey('review-sentence-${index + 1}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lessonType == ListeningLessonType.dialogue &&
                    sentence.voice.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    sentence.voice,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
                if (recordingStatus != null) ...<Widget>[
                  const SizedBox(height: 3),
                  _ReviewRecordingBadge(index: index, status: recordingStatus!),
                ],
              ],
            ),
          ),
          if (redesigned)
            _ReviewPlayControl(
              index: index,
              playing: playing,
              showMascot: featured,
              onPressed: onPlay,
              tooltip: context.tr('Nghe câu này', '播放本句'),
            )
          else
            IconButton(
              onPressed: onPlay,
              icon: Icon(
                playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
              ),
              tooltip: context.tr('Nghe câu này', '播放本句'),
            ),
        ],
      ),
    );
  }
}

enum _ReviewRecordingStatus { recorded, unrecorded }

class _ReviewRecordingBadge extends StatelessWidget {
  const _ReviewRecordingBadge({required this.index, required this.status});

  final int index;
  final _ReviewRecordingStatus status;

  @override
  Widget build(BuildContext context) {
    final recorded = status == _ReviewRecordingStatus.recorded;
    final accent = recorded ? AppColors.success : AppColors.coral;
    return Row(
      children: <Widget>[
        Icon(
          recorded ? Icons.check_circle_rounded : Icons.mic_off_rounded,
          size: 14,
          color: accent,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            recorded
                ? context.tr('Đã ghi âm', '已录音')
                : context.tr('Chưa ghi âm', '尚未录音'),
            key: ValueKey('review-recording-status-${index + 1}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewPlayControl extends StatefulWidget {
  const _ReviewPlayControl({
    required this.index,
    required this.playing,
    required this.showMascot,
    required this.onPressed,
    required this.tooltip,
  });

  static const _mascotAsset = MascotAssets.speak;

  final int index;
  final bool playing;
  final bool showMascot;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<_ReviewPlayControl> createState() => _ReviewPlayControlState();
}

class _ReviewPlayControlState extends State<_ReviewPlayControl> {
  Timer? _learningHintTimer;
  bool _learningHintHighlighted = true;

  @override
  void initState() {
    super.initState();
    if (widget.showMascot) {
      _learningHintTimer = Timer.periodic(const Duration(milliseconds: 700), (
        _,
      ) {
        if (mounted) {
          setState(() => _learningHintHighlighted = !_learningHintHighlighted);
        }
      });
    }
  }

  @override
  void dispose() {
    _learningHintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = _ReviewPlayButton(
      key: ValueKey('review-sentence-play-${widget.index + 1}'),
      playing: widget.playing,
      onPressed: widget.onPressed,
      tooltip: widget.tooltip,
    );
    if (!widget.showMascot) {
      return button;
    }

    return SizedBox(
      width: 132,
      height: 110,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(right: 0, top: 25, child: button),
          Positioned(
            left: 0,
            top: 18,
            width: 100,
            height: 92,
            child: IgnorePointer(
              child: Image.asset(
                _ReviewPlayControl._mascotAsset,
                key: const Key('review-first-sentence-mascot'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            left: 5,
            top: 0,
            width: 92,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: const Key('review-first-sentence-learning-hint'),
                opacity: _learningHintHighlighted ? 1 : 0.28,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lavenderBorder),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.indigo.withValues(alpha: 0.14),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    context.tr('Bẩm để học', '点击学习'),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.indigoDark,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPlayButton extends StatelessWidget {
  const _ReviewPlayButton({
    required this.playing,
    required this.onPressed,
    required this.tooltip,
    super.key,
  });

  final bool playing;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7C2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: playing
                      ? AppColors.periwinkle
                      : const Color(0xFFFFD49A),
                  width: playing ? 1.5 : 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFA86C).withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.indigo.withValues(
                          alpha: playing ? 0.36 : 0.22,
                        ),
                        blurRadius: playing ? 13 : 9,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    color: AppColors.indigoDark,
                    size: 29,
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
