import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_media_service.dart';
import '../domain/lesson_guide_flow.dart';

enum V4SongStageAction { skipped, continued }

/// A V4 song placement is deliberately separate from the older song-lesson
/// player. The curriculum names five placements, but supplies no reusable
/// song recording. A future source recording can be attached through
/// [songAudioUri] without ever falling back to a legacy `fullAudioUri`.
class V4SongStageScreen extends StatefulWidget {
  const V4SongStageScreen({
    required this.language,
    required this.songTitle,
    required this.mediaService,
    this.songAudioId,
    this.songAudioUri,
    this.voicePromptService,
    super.key,
  });

  final DisplayLanguage language;
  final String songTitle;
  final LessonMediaService mediaService;
  final String? songAudioId;
  final Uri? songAudioUri;
  final VoicePromptService? voicePromptService;

  @override
  State<V4SongStageScreen> createState() => _V4SongStageScreenState();
}

class _V4SongStageScreenState extends State<V4SongStageScreen> {
  VoicePromptService? _voicePromptService;
  late final bool _ownsVoicePromptService;
  bool _announcing = false;
  bool _playing = false;
  String? _message;
  int _request = 0;

  VoicePromptService get _prompt {
    final current = _voicePromptService;
    if (current != null) return current;
    return _voicePromptService = createVoicePromptService();
  }

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService = widget.voicePromptService;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_announceSongStart()),
    );
  }

  @override
  void dispose() {
    _request += 1;
    unawaited(widget.mediaService.stopPlayback());
    final prompt = _voicePromptService;
    if (prompt != null) {
      if (_ownsVoicePromptService) {
        unawaited(prompt.dispose());
      } else {
        unawaited(prompt.stop());
      }
    }
    super.dispose();
  }

  Future<void> _announceSongStart() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _announcing = true;
      _message = null;
    });
    try {
      await _prompt.speakAndWait(
        v4SongStartCue(widget.songTitle),
        locale: 'vi-VN',
      );
    } catch (_) {
      // The stage remains usable if a device TTS voice is unavailable.
    } finally {
      if (mounted && request == _request) {
        setState(() => _announcing = false);
      }
    }
  }

  Future<void> _playSong() async {
    final uri = widget.songAudioUri;
    if (uri == null || _playing || !mounted) return;
    setState(() {
      _playing = true;
      _message = null;
    });
    try {
      await _prompt.stop();
      await widget.mediaService.playToCompletion(uri);
      if (mounted) {
        setState(() => _message = 'Bạn đã nghe xong bài hát rồi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Chưa thể phát bài hát. Bạn thử lại nhé.');
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _finish(V4SongStageAction action) async {
    _request += 1;
    unawaited(_prompt.stop());
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    if (mounted) Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFutureSongAudio = widget.songAudioUri != null;
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('v4-song-stage-screen'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                  child: Column(
                    children: <Widget>[
                      const Spacer(),
                      Image.asset(
                        MascotAssets.sing,
                        width: 142,
                        height: 142,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                      Text('Bài hát', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      Text(
                        widget.songTitle,
                        key: const Key('v4-song-stage-title'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: AppColors.indigoDark,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.lavenderBorder),
                        ),
                        child: Text(
                          v4SongStartCue(widget.songTitle),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (hasFutureSongAudio)
                        FilledButton.tonalIcon(
                          key: const Key('v4-song-stage-play'),
                          onPressed: _playing ? null : _playSong,
                          icon: Icon(
                            _playing
                                ? Icons.graphic_eq_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(
                            _playing ? 'Đang phát bài hát' : 'Phát bài hát',
                          ),
                        )
                      else
                        Text(
                          'Bản audio bài hát sẽ được bổ sung sau.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      if (_message != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                      const Spacer(),
                      TextButton.icon(
                        key: const Key('v4-song-stage-skip'),
                        onPressed: () => _finish(V4SongStageAction.skipped),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Bỏ qua bài hát'),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('v4-song-stage-continue'),
                          onPressed: () => _finish(V4SongStageAction.continued),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _announcing ? 'Tiếp tục' : 'Tiếp tục học',
                          ),
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
