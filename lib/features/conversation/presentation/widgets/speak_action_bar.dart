import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

class SpeakActionBar extends StatelessWidget {
  const SpeakActionBar({
    required this.phase,
    required this.processingStage,
    this.isPreparingMicrophone = false,
    required this.onPressed,
    super.key,
  });

  final ConversationPhase phase;
  final ConversationProcessingStage processingStage;
  final bool isPreparingMicrophone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRecording = phase == ConversationPhase.recording;
    final isProcessing =
        phase == ConversationPhase.processing || isPreparingMicrophone;
    final primary = isRecording
        ? (isDark ? theme.colorScheme.secondary : AppColors.accentPink)
        : (isDark ? theme.colorScheme.primary : AppColors.primaryNavy);
    final foreground = isDark && !isRecording
        ? theme.colorScheme.onPrimary
        : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 24),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Semantics(
              button: true,
              enabled: !isProcessing,
              label: isPreparingMicrophone
                  ? context.tr('Đang chuẩn bị micro…', '正在准备麦克风…')
                  : _label(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isProcessing
                      ? (isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : AppColors.softNavy.withValues(alpha: 0.72))
                      : primary,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: primary.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isProcessing ? null : onPressed,
                    borderRadius: BorderRadius.circular(34),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 66),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            isRecording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            color: foreground,
                            size: 31,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                isPreparingMicrophone
                                    ? context.tr(
                                        'Đang chuẩn bị micro…',
                                        '正在准备麦克风…',
                                      )
                                    : _label(context),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: foreground,
                                  fontSize: 20,
                                ),
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
        ),
      ),
    );
  }

  String _label(BuildContext context) => switch (phase) {
    ConversationPhase.recording => context.tr('Dừng ghi âm', '停止录音'),
    ConversationPhase.processing => switch (processingStage) {
      ConversationProcessingStage.recognizing => context.tr(
        'Đang nhận giọng nói…',
        '正在识别语音…',
      ),
      ConversationProcessingStage.translating => context.tr(
        'Đang dịch…',
        '正在翻译…',
      ),
      ConversationProcessingStage.preparingAudio => context.tr(
        'Đang chuẩn bị âm thanh…',
        '正在准备语音…',
      ),
    },
    ConversationPhase.ready => context.tr('Nói câu mới', '说新句子'),
    ConversationPhase.error => context.tr('Thử lại', '重试'),
    ConversationPhase.idle => context.tr('Bắt đầu nói', '开始说话'),
  };
}
