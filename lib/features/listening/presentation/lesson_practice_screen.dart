import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../settings/presentation/history_sheet.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'listening_navigation_bar.dart';

class LessonPracticeScreen extends StatefulWidget {
  const LessonPracticeScreen({
    required this.language,
    required this.topic,
    required this.lesson,
    required this.progressStore,
    required this.mediaService,
    this.controller,
    super.key,
  });

  final DisplayLanguage language;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ConversationController? controller;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;

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

  ListeningSentenceContent get _sentence =>
      widget.lesson.sentences[_sentenceIndex];

  @override
  void initState() {
    super.initState();
    unawaited(_loadStartingPoint());
  }

  @override
  void dispose() {
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
    final sentenceIndex = currentSentence.clamp(
      0,
      widget.lesson.sentences.length - 1,
    );
    if (!mounted) {
      return;
    }
    setState(() => _sentenceIndex = sentenceIndex);
    await _loadRecording();
  }

  Future<void> _loadRecording() async {
    final path = await widget.mediaService.existingRecording(
      lessonId: widget.lesson.id,
      sentenceNumber: _sentence.number,
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
        body: SafeArea(
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
                        onPlaySample: _playSample,
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
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('previous-lesson-sentence'),
                              onPressed:
                                  _sentenceIndex == 0 ||
                                      _recording ||
                                      _mediaBusy
                                  ? null
                                  : _previous,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(62),
                                foregroundColor: AppColors.indigo,
                                side: const BorderSide(
                                  color: AppColors.lavenderBorder,
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: Text(
                                context.tr('Câu trước', '上一句'),
                                maxLines: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const Key('continue-lesson-sentence'),
                              onPressed: _recording || _mediaBusy
                                  ? null
                                  : _continue,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(62),
                                textStyle: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      context.tr(
                                        _sentenceIndex == total - 1
                                            ? 'Hoàn thành'
                                            : 'Tiếp tục',
                                        _sentenceIndex == total - 1
                                            ? '完成'
                                            : '继续',
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    _sentenceIndex == total - 1
                                        ? Icons.check_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ListeningNavigationBar(
          onCommunication: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onHistory: widget.controller == null ? null : _showHistory,
        ),
      ),
    );
  }

  Future<void> _playSample() async {
    final uri = _sentence.audioUri;
    if (uri == null) {
      _setMessage(
        context.tr(
          'Audio mẫu sẽ sẵn sàng sau khi cập nhật thư viện Cloudinary.',
          'Cloudinary 音频库更新后即可播放示范音频。',
        ),
      );
      return;
    }
    await _runMediaAction(() => widget.mediaService.play(uri));
  }

  Future<void> _playRecording() async {
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
    setState(() {
      _mediaBusy = true;
      _message = null;
    });
    try {
      await widget.mediaService.startRecording(
        lessonId: widget.lesson.id,
        sentenceNumber: _sentence.number,
      );
      if (mounted) {
        setState(() {
          _recording = true;
          _mediaBusy = false;
          _recordingPath = null;
          _recordingDuration = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
      _setMessage(error.toString());
    }
  }

  Future<void> _stopRecording() async {
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
        _message = context.tr(
          'Đã lưu bản ghi của câu này trên điện thoại.',
          '本句录音已保存在手机上。',
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _mediaBusy = false;
        });
      }
      _setMessage(error.toString());
    }
  }

  Future<void> _continue() async {
    await widget.progressStore.saveLesson(widget.lesson.id, _sentenceIndex + 1);
    if (!mounted) {
      return;
    }
    if (_sentenceIndex == widget.lesson.sentences.length - 1) {
      await widget.progressStore.saveCurrentSentence(
        widget.lesson.id,
        _sentenceIndex,
      );
      await _showCompletion();
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
    setState(() {
      _sentenceIndex = nextSentence;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    await _loadRecording();
  }

  Future<void> _previous() async {
    if (_sentenceIndex == 0) {
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
    await _loadRecording();
  }

  Future<void> _exitLesson() async {
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      _sentenceIndex,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _showCompletion() async {
    final uri = widget.lesson.outroAudioUri;
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
      await widget.progressStore.saveCurrentSentence(widget.lesson.id, 0);
      if (!mounted) {
        return;
      }
      setState(() {
        _sentenceIndex = 0;
        _recordingPath = null;
        _recordingDuration = null;
        _message = null;
      });
      await _loadRecording();
    }
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistorySheet(controller: widget.controller!),
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
  const _SentenceCard({required this.sentence, required this.onPlaySample});

  final ListeningSentenceContent sentence;
  final VoidCallback onPlaySample;

  @override
  Widget build(BuildContext context) {
    final englishSize = sentence.english.length > 55
        ? 29.0
        : sentence.english.length > 30
        ? 36.0
        : 50.0;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 360),
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
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
          const SizedBox(height: 14),
          Text(
            sentence.vietnamese,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.indigo,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 28),
          const Icon(
            Icons.graphic_eq_rounded,
            size: 64,
            color: AppColors.periwinkle,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('play-lesson-sample'),
            onPressed: onPlaySample,
            icon: const Icon(Icons.volume_up_rounded),
            label: Text(context.tr('Nghe mẫu', '听示范')),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.lavenderSoft,
              foregroundColor: AppColors.indigoDark,
              side: const BorderSide(color: AppColors.lavenderBorder),
            ),
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
