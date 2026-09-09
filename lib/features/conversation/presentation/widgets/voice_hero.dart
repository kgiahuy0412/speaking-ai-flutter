import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../app/mascot_assets.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

const _homeHeroBlobAsset = 'assets/images/home-hero-blob.png';
const _homeWaveformAsset = 'assets/images/home-waveform.png';

class VoiceHero extends StatelessWidget {
  const VoiceHero({
    required this.phase,
    required this.processingStage,
    required this.amplitude,
    this.isPreparingMicrophone = false,
    required this.onStop,
    super.key,
  });

  final ConversationPhase phase;
  final ConversationProcessingStage processingStage;
  final double amplitude;
  final bool isPreparingMicrophone;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRecording = phase == ConversationPhase.recording;
    final accent = isRecording ? AppColors.coral : AppColors.indigo;
    final compact = MediaQuery.sizeOf(context).height < 900;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: compact ? 205 : 232,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Transform.scale(
                    scale: 1.32,
                    child: Opacity(
                      opacity: isDark ? 0.18 : 1,
                      child: Image.asset(
                        _homeHeroBlobAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
                AnimatedScale(
                  duration: motionDuration,
                  scale: isRecording ? 0.96 + (amplitude * 0.08) : 1,
                  child: Transform.scale(
                    scale: 1.12,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Image.asset(
                        MascotAssets.listen,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          Semantics(
            liveRegion: true,
            child: Text(
              isPreparingMicrophone
                  ? context.tr('Đang chuẩn bị micro…', '正在准备麦克风…')
                  : _statusLabel(context),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: isRecording
                    ? AppColors.coral
                    : isDark
                    ? colorScheme.primary
                    : AppColors.indigoDark,
                fontSize: compact ? 27 : 31,
                shadows: <Shadow>[
                  Shadow(
                    color: isDark ? Colors.black54 : Colors.white,
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            isPreparingMicrophone
                ? context.tr(
                    'Đợi một chút rồi nói khi màn hình báo đang nghe nhé',
                    '请稍候，显示正在聆听后再开始说话',
                  )
                : _supportingText(context),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? colorScheme.onSurfaceVariant : AppColors.muted,
              fontSize: compact ? 15 : 17,
              fontWeight: FontWeight.w600,
              shadows: <Shadow>[
                Shadow(
                  color: isDark ? Colors.black54 : Colors.white,
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          SizedBox(
            height: compact ? 68 : 76,
            child: Center(
              child: _AnimatedHomeWaveform(
                active:
                    isRecording ||
                    phase == ConversationPhase.processing ||
                    isPreparingMicrophone,
                amplitude: amplitude,
                isDark: isDark,
                accent: accent,
                width: compact ? 330 : 350,
                height: compact ? 68 : 76,
                semanticLabel: context.tr('Mức âm thanh', '音量'),
              ),
            ),
          ),
          if (!isRecording && !isPreparingMicrophone)
            Text(
              _helperText(context),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? colorScheme.onSurfaceVariant : AppColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows: <Shadow>[
                  Shadow(
                    color: isDark ? Colors.black54 : Colors.white,
                    blurRadius: 7,
                  ),
                  Shadow(
                    color: isDark ? Colors.black54 : Colors.white,
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(BuildContext context) => switch (phase) {
    ConversationPhase.idle => context.tr('Con nói tiếng Việt', '请说越南语'),
    ConversationPhase.recording => context.tr('Mình đang nghe…', '正在聆听…'),
    ConversationPhase.processing => switch (processingStage) {
      ConversationProcessingStage.recognizing => context.tr(
        'Đang nhận giọng nói…',
        '正在识别语音…',
      ),
      ConversationProcessingStage.translating => context.tr(
        'Đang dịch sang tiếng Anh…',
        '正在翻译成英语…',
      ),
      ConversationProcessingStage.preparingAudio => context.tr(
        'Đang chuẩn bị âm thanh…',
        '正在准备语音…',
      ),
    },
    ConversationPhase.ready => context.tr('Đã có câu tiếng Anh', '英语句子已准备好'),
    ConversationPhase.error => context.tr('Mình thử lại nhé', '我们再试一次'),
  };

  String _supportingText(BuildContext context) => switch (phase) {
    ConversationPhase.idle => context.tr(
      'Mình sẽ giúp nói bằng tiếng Anh',
      '我会帮你用英语表达',
    ),
    ConversationPhase.recording => context.tr(
      'Nói tự nhiên và rõ ràng nhé',
      '请自然、清晰地说话',
    ),
    ConversationPhase.processing => switch (processingStage) {
      ConversationProcessingStage.recognizing => context.tr(
        'Cloudflare đang nghe lại câu con vừa nói',
        'Cloudflare 正在识别刚才说的话',
      ),
      ConversationProcessingStage.translating => context.tr(
        'Sắp có câu tiếng Anh rồi',
        '英语句子马上就好',
      ),
      ConversationProcessingStage.preparingAudio => context.tr(
        'Sắp phát câu tiếng Anh cho con',
        '马上播放英语句子',
      ),
    },
    ConversationPhase.ready => context.tr(
      'Con có thể nghe lại câu bên dưới',
      '可以播放下面的句子',
    ),
    ConversationPhase.error => context.tr(
      'Kiểm tra micro hoặc kết nối',
      '请检查麦克风或网络连接',
    ),
  };

  String _helperText(BuildContext context) => switch (phase) {
    ConversationPhase.idle => context.tr(
      'Bấm nút micro bên dưới để bắt đầu',
      '点击下方麦克风按钮开始',
    ),
    ConversationPhase.processing => '',
    ConversationPhase.ready => context.tr(
      'Bấm “Nói câu mới” để tiếp tục',
      '点击“说新句子”继续',
    ),
    ConversationPhase.error => context.tr(
      'Bấm “Thử lại” khi con sẵn sàng',
      '准备好后点击“重试”',
    ),
    ConversationPhase.recording => '',
  };
}

class _AnimatedHomeWaveform extends StatefulWidget {
  const _AnimatedHomeWaveform({
    required this.active,
    required this.amplitude,
    required this.isDark,
    required this.accent,
    required this.width,
    required this.height,
    required this.semanticLabel,
  });

  final bool active;
  final double amplitude;
  final bool isDark;
  final Color accent;
  final double width;
  final double height;
  final String semanticLabel;

  @override
  State<_AnimatedHomeWaveform> createState() => _AnimatedHomeWaveformState();
}

class _AnimatedHomeWaveformState extends State<_AnimatedHomeWaveform> {
  Timer? _pulseTimer;
  bool _pulseExpanded = true;
  bool _reduceMotion = false;
  bool _hasDependencies = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_hasDependencies || reduceMotion != _reduceMotion) {
      _hasDependencies = true;
      _reduceMotion = reduceMotion;
      _syncPulse();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedHomeWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncPulse();
  }

  void _syncPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulseExpanded = true;
    if (widget.active && !_reduceMotion) {
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
        if (!mounted) return;
        setState(() => _pulseExpanded = !_pulseExpanded);
      });
    }
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        key: Key(
          widget.active
              ? 'conversation-animated-waveform'
              : 'conversation-static-waveform',
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: widget.active ? 0.72 : 1,
            end: widget.active && !_reduceMotion
                ? (_pulseExpanded ? 1 : 0.72)
                : 1,
          ),
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          builder: (context, pulseScale, child) {
            final measuredAmplitude = widget.amplitude.clamp(0.0, 1.0);
            final amplitudeScale = 0.72 + (measuredAmplitude * 0.28);
            final scaleY = widget.active && amplitudeScale > pulseScale
                ? amplitudeScale
                : pulseScale;
            final pulseProgress = ((pulseScale - 0.72) / 0.28).clamp(0.0, 1.0);
            final scaleX = widget.active
                ? 0.985 + (pulseProgress * 0.015)
                : 1.0;
            return Opacity(
              opacity: widget.active ? 0.78 + (pulseProgress * 0.22) : 1,
              child: Transform.scale(
                alignment: Alignment.center,
                scaleX: scaleX,
                scaleY: scaleY,
                child: child,
              ),
            );
          },
          child: widget.isDark
              ? SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: widget.accent.withValues(
                        alpha: widget.active ? 0.88 : 0.62,
                      ),
                      size: 64,
                    ),
                  ),
                )
              : Image.asset(
                  _homeWaveformAsset,
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
        ),
      ),
    );
  }
}
