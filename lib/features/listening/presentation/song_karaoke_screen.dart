import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_media_service.dart';
import '../domain/listening_content.dart';

bool shouldUseSongKaraoke({
  required int startAge,
  required ListeningLessonContent lesson,
}) => startAge >= 6 && lesson.type == ListeningLessonType.song;

class SongKaraokeScreen extends StatefulWidget {
  const SongKaraokeScreen({
    required this.language,
    required this.lesson,
    required this.mediaService,
    required this.practiceBuilder,
    required this.topicTitle,
    this.autoPlayDelay = const Duration(seconds: 3),
    this.backgroundAsset = learningSceneryAsset,
    super.key,
  });

  final DisplayLanguage language;
  final ListeningLessonContent lesson;
  final LessonMediaService mediaService;
  final WidgetBuilder practiceBuilder;
  final String topicTitle;
  final Duration autoPlayDelay;
  final String backgroundAsset;

  @override
  State<SongKaraokeScreen> createState() => _SongKaraokeScreenState();
}

class _SongKaraokeScreenState extends State<SongKaraokeScreen> {
  Timer? _autoPlayTimer;
  Timer? _countdownTimer;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _mediaBusy = false;
  bool _leaving = false;
  late int _secondsUntilAutoPlay;
  String? _message;

  Uri? get _songUri => widget.lesson.fullAudioUri;

  List<ListeningSentenceContent> get _lyrics =>
      widget.lesson.karaokeLines.isNotEmpty
      ? widget.lesson.karaokeLines
      : widget.lesson.sentences;

  @override
  void initState() {
    super.initState();
    _position = widget.mediaService.playbackPosition;
    _duration = widget.mediaService.playbackDuration;
    _secondsUntilAutoPlay = math.max(
      0,
      (widget.autoPlayDelay.inMilliseconds / 1000).ceil(),
    );
    _playingSubscription = widget.mediaService.playbackPlayingStream.listen((
      playing,
    ) {
      if (mounted) {
        setState(() => _playing = playing);
      }
    });
    _positionSubscription = widget.mediaService.playbackPositionStream.listen((
      position,
    ) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSubscription = widget.mediaService.playbackDurationStream.listen((
      duration,
    ) {
      if (mounted && duration != null && duration > Duration.zero) {
        setState(() => _duration = duration);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareAndSchedule());
  }

  Future<void> _prepareAndSchedule() async {
    final uri = _songUri;
    if (uri != null) {
      try {
        await widget.mediaService.preload(uri);
      } catch (_) {
        // Playback still gets one normal attempt after the countdown.
      }
    }
    if (!mounted) {
      return;
    }
    if (widget.autoPlayDelay <= Duration.zero) {
      await _playSong();
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsUntilAutoPlay = math.max(0, _secondsUntilAutoPlay - 1);
      });
    });
    _autoPlayTimer = Timer(widget.autoPlayDelay, () {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() => _secondsUntilAutoPlay = 0);
        unawaited(_playSong());
      }
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_playingSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    if (!_leaving) {
      unawaited(widget.mediaService.stopPlayback());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _karaokeSnapshot();
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('song-karaoke-screen'),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              widget.backgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
            ),
            const _SongReadabilityOverlay(),
            Positioned.fill(
              child: IgnorePointer(
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 22,
                            bottom: 150,
                          ),
                          child: Image.asset(
                            MascotAssets.sing,
                            width: 112,
                            height: 112,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 720;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : 20,
                          10,
                          compact ? 16 : 20,
                          compact ? 12 : 18,
                        ),
                        child: Column(
                          children: <Widget>[
                            _SongHeader(
                              title: _songTitle,
                              subtitle: widget.topicTitle,
                              onEnd: _showEndDialog,
                            ),
                            SizedBox(height: compact ? 22 : 44),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: _KaraokeLyrics(
                                  currentLine: snapshot.currentLine,
                                  translationLine: snapshot.translationLine,
                                  highlightedWordCount:
                                      snapshot.highlightedWordCount,
                                  compact: compact,
                                ),
                              ),
                            ),
                            _SongPlayer(
                              title: _songTitle,
                              progress: _progress,
                              position: _position,
                              duration: _effectiveDuration,
                              playing: _playing,
                              busy: _mediaBusy,
                              secondsUntilAutoPlay: _secondsUntilAutoPlay,
                              message: _message,
                              onPlayPause: _togglePlayback,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _songTitle => widget.lesson.titleEn.trim().isNotEmpty
      ? widget.lesson.titleEn.trim()
      : widget.lesson.titleVi.trim();

  Duration get _effectiveDuration {
    final duration = _duration;
    if (duration != null && duration > Duration.zero) {
      return duration;
    }
    final explicitEnd = _lyrics
        .map((line) => line.karaokeEnd ?? Duration.zero)
        .fold<Duration>(
          Duration.zero,
          (latest, end) => end > latest ? end : latest,
        );
    if (explicitEnd > Duration.zero) {
      return explicitEnd;
    }
    return Duration(seconds: math.max(30, _lyrics.length * 6));
  }

  double get _progress {
    final totalMs = _effectiveDuration.inMilliseconds;
    if (totalMs <= 0) {
      return 0;
    }
    return (_position.inMilliseconds / totalMs).clamp(0, 1).toDouble();
  }

  _KaraokeSnapshot _karaokeSnapshot() {
    final lines = _lyrics;
    if (lines.isEmpty) {
      return _KaraokeSnapshot(
        currentLine: context.tr('Lời bài hát sẽ được bổ sung sớm.', '歌词即将补充。'),
        translationLine: '',
        highlightedWordCount: 0,
      );
    }
    final windows = _buildLineWindows(lines, _effectiveDuration);
    var activeIndex = windows.lastIndexWhere(
      (window) => _position >= window.start,
    );
    if (activeIndex < 0) {
      activeIndex = 0;
    }
    final activeWindow = windows[activeIndex];
    final lineDuration = math.max(
      1,
      activeWindow.end.inMilliseconds - activeWindow.start.inMilliseconds,
    );
    final lineProgress =
        ((_position.inMilliseconds - activeWindow.start.inMilliseconds) /
                lineDuration)
            .clamp(0, 1)
            .toDouble();
    final currentLine = lines[activeIndex].english.trim();
    final wordCount = currentLine.isEmpty
        ? 0
        : currentLine.split(RegExp(r'\s+')).length;
    return _KaraokeSnapshot(
      currentLine: currentLine,
      translationLine: _vietnameseForLine(lines[activeIndex]),
      highlightedWordCount: (lineProgress * wordCount).ceil().clamp(
        0,
        wordCount,
      ),
    );
  }

  String _vietnameseForLine(ListeningSentenceContent line) {
    final embeddedTranslation = line.vietnamese.trim();
    if (embeddedTranslation.isNotEmpty) {
      return embeddedTranslation;
    }

    final english = line.english.trim();
    for (final sentence in widget.lesson.sentences) {
      if (sentence.number == line.number &&
          sentence.english.trim() == english) {
        return sentence.vietnamese.trim();
      }
    }
    return '';
  }

  List<_KaraokeWindow> _buildLineWindows(
    List<ListeningSentenceContent> lines,
    Duration duration,
  ) {
    final hasExplicitTimings = lines.every(
      (line) =>
          line.karaokeStart != null &&
          line.karaokeEnd != null &&
          line.karaokeEnd! > line.karaokeStart!,
    );
    if (hasExplicitTimings) {
      return lines
          .map(
            (line) => _KaraokeWindow(
              start: line.karaokeStart!,
              end: line.karaokeEnd!,
            ),
          )
          .toList(growable: false);
    }

    final weights = lines
        .map(
          (line) =>
              math.max(1, line.english.trim().split(RegExp(r'\s+')).length),
        )
        .toList(growable: false);
    final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
    var elapsedWeight = 0;
    return List<_KaraokeWindow>.generate(lines.length, (index) {
      final start = Duration(
        milliseconds: duration.inMilliseconds * elapsedWeight ~/ totalWeight,
      );
      elapsedWeight += weights[index];
      final end = Duration(
        milliseconds: duration.inMilliseconds * elapsedWeight ~/ totalWeight,
      );
      return _KaraokeWindow(start: start, end: end);
    }, growable: false);
  }

  Future<void> _togglePlayback() async {
    _autoPlayTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() => _secondsUntilAutoPlay = 0);
    }
    if (_playing) {
      await widget.mediaService.stopPlayback();
      if (mounted) {
        setState(() => _playing = false);
      }
      return;
    }
    await _playSong();
  }

  Future<void> _playSong() async {
    if (_mediaBusy || _leaving) {
      return;
    }
    final uri = _songUri;
    if (uri == null) {
      if (mounted) {
        setState(() {
          _message = context.tr(
            'Audio bài hát sẽ được bổ sung sớm.',
            '歌曲音频即将补充。',
          );
        });
      }
      return;
    }
    setState(() {
      _mediaBusy = true;
      _message = null;
    });
    try {
      await widget.mediaService.play(uri);
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = context.tr(
            'Chưa thể phát bài hát. Con hãy bấm Phát nhạc để thử lại.',
            '暂时无法播放歌曲，请点击播放重试。',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  Future<void> _showEndDialog() async {
    if (_leaving) {
      return;
    }
    final action = await showDialog<_SongEndAction>(
      context: context,
      builder: (dialogContext) => _SongEndDialog(
        songTitle: _songTitle,
        onPractice: () =>
            Navigator.of(dialogContext).pop(_SongEndAction.practice),
        onExit: () => Navigator.of(dialogContext).pop(_SongEndAction.exit),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    _leaving = true;
    _autoPlayTimer?.cancel();
    _countdownTimer?.cancel();
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    if (action == _SongEndAction.practice) {
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: widget.practiceBuilder),
      );
    } else {
      Navigator.of(context).pop();
    }
  }
}

enum _SongEndAction { practice, exit }

class _SongReadabilityOverlay extends StatelessWidget {
  const _SongReadabilityOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0, 0.36, 0.72, 1],
          colors: <Color>[
            Colors.white.withValues(alpha: 0.12),
            const Color(0xFFFFFDF7).withValues(alpha: 0.58),
            Colors.white.withValues(alpha: 0.05),
            const Color(0xFFFFFBF2).withValues(alpha: 0.88),
          ],
        ),
      ),
    );
  }
}

class _SongHeader extends StatelessWidget {
  const _SongHeader({
    required this.title,
    required this.subtitle,
    required this.onEnd,
  });

  final String title;
  final String subtitle;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.music_note_rounded, color: Color(0xFF155EEF)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.white, blurRadius: 12),
                  ],
                ),
              ),
              if (subtitle.trim().isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.indigoDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          key: const Key('song-karaoke-end'),
          onPressed: onEnd,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.94),
            foregroundColor: AppColors.ink,
            minimumSize: const Size(104, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: const StadiumBorder(),
            elevation: 2,
            shadowColor: AppColors.ink.withValues(alpha: 0.2),
          ),
          icon: const Icon(Icons.close_rounded, size: 24),
          label: Text(context.tr('Kết thúc', '结束')),
        ),
      ],
    );
  }
}

class _KaraokeLyrics extends StatelessWidget {
  const _KaraokeLyrics({
    required this.currentLine,
    required this.translationLine,
    required this.highlightedWordCount,
    required this.compact,
  });

  final String currentLine;
  final String translationLine;
  final int highlightedWordCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final words = currentLine.isEmpty
        ? const <String>[]
        : currentLine.split(RegExp(r'\s+'));
    final currentStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      color: AppColors.ink,
      fontSize: compact ? 34 : 43,
      height: 1.16,
      letterSpacing: -0.8,
      fontWeight: FontWeight.w800,
      shadows: <Shadow>[
        Shadow(color: Colors.white.withValues(alpha: 0.85), blurRadius: 14),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            label: currentLine,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  for (var index = 0; index < words.length; index += 1)
                    TextSpan(
                      text:
                          '${words[index]}${index == words.length - 1 ? '' : ' '}',
                      style: currentStyle?.copyWith(
                        color: index < highlightedWordCount
                            ? const Color(0xFF2536E8)
                            : AppColors.ink,
                      ),
                    ),
                ],
              ),
              key: const Key('song-karaoke-current-line'),
            ),
          ),
          if (translationLine.isNotEmpty) ...<Widget>[
            const SizedBox(height: 30),
            Text(
              translationLine,
              key: const Key('song-karaoke-translation-line'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF47628F),
                fontSize: compact ? 20 : 25,
                height: 1.25,
                fontWeight: FontWeight.w700,
                shadows: <Shadow>[
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.88),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SongPlayer extends StatelessWidget {
  const _SongPlayer({
    required this.title,
    required this.progress,
    required this.position,
    required this.duration,
    required this.playing,
    required this.busy,
    required this.secondsUntilAutoPlay,
    required this.message,
    required this.onPlayPause,
  });

  final String title;
  final double progress;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool busy;
  final int secondsUntilAutoPlay;
  final String? message;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final status =
        message ??
        (secondsUntilAutoPlay > 0
            ? context.tr(
                'Bài hát bắt đầu sau $secondsUntilAutoPlay giây',
                '歌曲将在 $secondsUntilAutoPlay 秒后开始',
              )
            : context.tr('Bài hát tiếng Anh', '英语歌曲'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xF5FFFBF2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xCCFFFFFF), width: 1.4),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2B142451),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: message == null
                        ? AppColors.success
                        : AppColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    key: const Key('song-karaoke-progress'),
                    value: progress,
                    minHeight: 7,
                    color: AppColors.indigo,
                    backgroundColor: const Color(0xFFDCE5F7),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(_formatDuration(position)),
                    Text('-${_formatDuration(duration - position)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                button: true,
                label: playing
                    ? context.tr('Tạm dừng bài hát', '暂停歌曲')
                    : context.tr('Phát bài hát', '播放歌曲'),
                child: InkResponse(
                  key: const Key('song-karaoke-play'),
                  onTap: busy ? null : onPlayPause,
                  radius: 48,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: busy ? AppColors.periwinkle : AppColors.indigo,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x403D4DD6),
                          blurRadius: 20,
                          offset: Offset(0, 9),
                        ),
                      ],
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(23),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 4,
                            ),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                playing
                    ? context.tr('Tạm dừng', '暂停')
                    : context.tr('Phát nhạc', '播放音乐'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.indigoDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final totalSeconds = math.max(0, value.inSeconds);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _SongEndDialog extends StatelessWidget {
  const _SongEndDialog({
    required this.songTitle,
    required this.onPractice,
    required this.onExit,
  });

  final String songTitle;
  final VoidCallback onPractice;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('song-karaoke-end-dialog'),
      icon: Container(
        width: 58,
        height: 58,
        decoration: const BoxDecoration(
          color: AppColors.lavender,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.music_note_rounded,
          color: AppColors.indigo,
          size: 32,
        ),
      ),
      title: Text(
        context.tr('Con muốn làm gì tiếp?', '接下来想做什么？'),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            context.tr(
              'Con có thể luyện từng dòng của “$songTitle” hoặc kết thúc tại đây.',
              '你可以逐句练习《$songTitle》，也可以在这里结束。',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('song-karaoke-practice'),
              onPressed: onPractice,
              icon: const Icon(Icons.mic_rounded),
              label: Text(context.tr('Luyện theo bài hát', '跟着歌曲练习')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('song-karaoke-confirm-exit'),
              onPressed: onExit,
              icon: const Icon(Icons.exit_to_app_rounded),
              label: Text(context.tr('Xác nhận thoát', '确认退出')),
            ),
          ),
        ],
      ),
    );
  }
}

class _KaraokeSnapshot {
  const _KaraokeSnapshot({
    required this.currentLine,
    required this.translationLine,
    required this.highlightedWordCount,
  });

  final String currentLine;
  final String translationLine;
  final int highlightedWordCount;
}

class _KaraokeWindow {
  const _KaraokeWindow({required this.start, required this.end});

  final Duration start;
  final Duration end;
}
