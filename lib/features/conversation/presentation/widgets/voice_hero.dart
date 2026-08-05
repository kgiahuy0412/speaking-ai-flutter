import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../app/mascot_assets.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

class VoiceHero extends StatelessWidget {
  const VoiceHero({
    required this.phase,
    required this.processingStage,
    required this.amplitude,
    required this.onStop,
    super.key,
  });

  final ConversationPhase phase;
  final ConversationProcessingStage processingStage;
  final double amplitude;
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
          AnimatedScale(
            duration: motionDuration,
            scale: isRecording ? 0.96 + (amplitude * 0.08) : 1,
            child: SizedBox(
              height: compact ? 158 : 178,
              child: Transform.scale(
                scale: 1.28,
                child: Image.asset(
                  MascotAssets.listen,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 2 : 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _statusLabel(context),
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
            _supportingText(context),
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
            height: compact ? 64 : 72,
            child: Center(
              child: phase == ConversationPhase.processing
                  ? const SizedBox.square(
                      dimension: 46,
                      child: CircularProgressIndicator(
                        strokeWidth: 5,
                        color: AppColors.indigo,
                      ),
                    )
                  : AnimatedScale(
                      duration: motionDuration,
                      scale: isRecording ? 0.94 + (amplitude * 0.14) : 1,
                      child: Transform.scale(
                        scaleX: 1.75,
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: accent.withValues(
                            alpha: isRecording ? 0.88 : 0.62,
                          ),
                          size: compact ? 54 : 64,
                          semanticLabel: context.tr('Mức âm thanh', '音量'),
                        ),
                      ),
                    ),
            ),
          ),
          if (isRecording)
            FilledButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded),
              label: Text(context.tr('Dừng', '停止')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(132, 46),
                backgroundColor: AppColors.coral,
                foregroundColor: Colors.white,
              ),
            )
          else
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
