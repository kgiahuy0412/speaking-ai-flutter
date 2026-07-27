import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_media_service.dart';
import '../domain/listening_content.dart';

class LessonReviewScreen extends StatefulWidget {
  const LessonReviewScreen({
    required this.language,
    required this.lesson,
    required this.mediaService,
    this.skippedSentenceIndexes = const <int>{},
    super.key,
  });

  final DisplayLanguage language;
  final ListeningLessonContent lesson;
  final LessonMediaService mediaService;
  final Set<int> skippedSentenceIndexes;

  @override
  State<LessonReviewScreen> createState() => _LessonReviewScreenState();
}

class _LessonReviewScreenState extends State<LessonReviewScreen> {
  static const int _completionDelaySeconds = 6;

  int? _playingIndex;
  bool _autoPlaying = true;
  bool _stopped = false;
  int _completionUnlockSeconds = _completionDelaySeconds;
  String? _message;
  Timer? _reviewGapTimer;
  Timer? _completionUnlockTimer;
  Completer<bool>? _reviewGapCompleter;

  @override
  void initState() {
    super.initState();
    _startCompletionUnlockTimer();
    unawaited(_playReview());
  }

  @override
  void dispose() {
    _stopped = true;
    _cancelReviewGap();
    _completionUnlockTimer?.cancel();
    widget.mediaService.stopPlayback();
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _title(context),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              context.tr(
                                '${widget.lesson.sentences.length} câu tiếng Anh đã học',
                                '已学习 ${widget.lesson.sentences.length} 句英语',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: _ReviewHero(
                    lesson: widget.lesson,
                    autoPlaying: _autoPlaying,
                    onStop: _stopAutoReview,
                  ),
                ),
                if (widget.skippedSentenceIndexes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _SkippedBanner(
                      count: widget.skippedSentenceIndexes.length,
                      onRetry: () => Navigator.of(
                        context,
                      ).pop(widget.skippedSentenceIndexes.first),
                    ),
                  ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  itemCount: widget.lesson.sentences.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final sentence = widget.lesson.sentences[index];
                    return _ReviewSentenceTile(
                      index: index,
                      sentence: sentence,
                      lessonType: widget.lesson.type,
                      playing: _playingIndex == index,
                      skipped: widget.skippedSentenceIndexes.contains(index),
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
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: _completionUnlockSeconds == 0 ? 1 : 0.48,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('complete-lesson-review'),
                        onPressed: _completionUnlockSeconds == 0
                            ? () => Navigator.of(context).pop(-1)
                            : null,
                        icon: Icon(
                          _completionUnlockSeconds == 0
                              ? Icons.celebration_rounded
                              : Icons.lock_clock_rounded,
                        ),
                        label: Text(
                          _completionUnlockSeconds == 0
                              ? context.tr('Hoàn thành bài', '完成课程')
                              : context.tr(
                                  'Hoàn thành sau $_completionUnlockSeconds giây',
                                  '$_completionUnlockSeconds 秒后可完成',
                                ),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(60),
                          disabledBackgroundColor: AppColors.periwinkle,
                          disabledForegroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title(BuildContext context) => switch (widget.lesson.type) {
    ListeningLessonType.dialogue => context.tr(
      'Nghe hội thoại hoàn chỉnh',
      '完整对话',
    ),
    ListeningLessonType.song => context.tr('Cùng nghe bài hát', '一起听歌曲'),
    ListeningLessonType.standard => context.tr('Ôn tập cuối bài', '课后复习'),
  };

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
    _stopped = false;
    _cancelReviewGap();
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    setState(() {
      _autoPlaying = true;
      _message = null;
      _playingIndex = null;
    });

    final fullAudio = widget.lesson.fullAudioUri;
    if (fullAudio != null &&
        widget.lesson.type != ListeningLessonType.standard) {
      try {
        await widget.mediaService.play(fullAudio);
      } catch (error) {
        _setMessage(error.toString());
      }
      if (mounted) {
        setState(() => _autoPlaying = false);
      }
      return;
    }

    for (var index = 0; index < widget.lesson.sentences.length; index++) {
      if (_stopped || !mounted) {
        return;
      }
      setState(() => _playingIndex = index);
      final uri = widget.lesson.sentences[index].audioUri;
      if (uri != null) {
        try {
          await widget.mediaService.play(uri);
        } catch (_) {}
      }
      if (!await _waitReviewGap()) {
        return;
      }
    }
    if (mounted && !_stopped) {
      setState(() {
        _playingIndex = null;
        _autoPlaying = false;
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
    final sentence = widget.lesson.sentences[index];
    if (sentence.audioUri == null) {
      _setMessage(context.tr('Audio câu này sẽ được gắn sau.', '本句音频稍后接入。'));
      return;
    }
    if (mounted) {
      setState(() => _playingIndex = index);
    }
    try {
      await widget.mediaService.play(sentence.audioUri!);
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _playingIndex = null);
      }
    }
  }

  Future<void> _stopAutoReview() async {
    _stopped = true;
    _cancelReviewGap();
    await widget.mediaService.stopPlayback();
    if (mounted) {
      setState(() {
        _autoPlaying = false;
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
    _reviewGapTimer = Timer(const Duration(seconds: 2), () {
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

class _ReviewHero extends StatelessWidget {
  const _ReviewHero({
    required this.lesson,
    required this.autoPlaying,
    required this.onStop,
  });

  final ListeningLessonContent lesson;
  final bool autoPlaying;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final icon = switch (lesson.type) {
      ListeningLessonType.dialogue => Icons.forum_rounded,
      ListeningLessonType.song => Icons.music_note_rounded,
      ListeningLessonType.standard => Icons.headphones_rounded,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: autoPlaying ? const Color(0xFFE9E8FF) : AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.lavenderBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: AppColors.indigo,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  autoPlaying
                      ? context.tr('Đang tự động phát', '正在自动播放')
                      : context.tr('Sẵn sàng nghe lại', '可以重新收听'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    'Chỉ phát tiếng Anh · mỗi câu cách nhau 2 giây',
                    '仅播放英语 · 每句间隔 2 秒',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (autoPlaying)
            IconButton(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: context.tr('Dừng phát', '停止播放'),
            ),
        ],
      ),
    );
  }
}

class _SkippedBanner extends StatelessWidget {
  const _SkippedBanner({required this.count, required this.onRetry});

  final int count;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD89A)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.favorite_outline_rounded, color: Color(0xFFFF9C6C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                '$count câu chưa ghi âm — không sao đâu!',
                '$count 句尚未录音——没关系！',
              ),
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            key: const Key('retry-skipped-sentences'),
            onPressed: onRetry,
            child: Text(context.tr('Thử lại', '再试一次')),
          ),
        ],
      ),
    );
  }
}

class _ReviewSentenceTile extends StatelessWidget {
  const _ReviewSentenceTile({
    required this.index,
    required this.sentence,
    required this.lessonType,
    required this.playing,
    required this.skipped,
    required this.onPlay,
  });

  final int index;
  final ListeningSentenceContent sentence;
  final ListeningLessonType lessonType;
  final bool playing;
  final bool skipped;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: playing ? const Color(0xFFE9E8FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: playing ? AppColors.indigo : AppColors.lavenderBorder,
          width: playing ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: skipped
                ? const Color(0xFFFFF1E8)
                : AppColors.lavenderSoft,
            foregroundColor: skipped ? AppColors.coral : AppColors.indigo,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sentence.english,
                  style: Theme.of(context).textTheme.titleMedium,
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
                if (skipped) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    context.tr('Chưa ghi âm', '尚未录音'),
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
