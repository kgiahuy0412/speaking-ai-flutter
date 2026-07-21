import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../domain/conversation_models.dart';

class VoiceHero extends StatelessWidget {
  const VoiceHero({
    required this.phase,
    required this.amplitude,
    required this.onStop,
    super.key,
  });

  final ConversationPhase phase;
  final double amplitude;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isRecording = phase == ConversationPhase.recording;
    final accent = isRecording ? AppColors.coral : AppColors.indigo;
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 25),
          child: AnimatedContainer(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(24, 38, 24, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isRecording
                    ? const <Color>[Color(0xFFFFF7F5), AppColors.coralSoft]
                    : const <Color>[Color(0xFFFAF9FF), Color(0xFFF0EFFF)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(58),
                topRight: Radius.circular(58),
                bottomLeft: Radius.circular(42),
                bottomRight: Radius.circular(58),
              ),
              border: Border.all(
                color: isRecording
                    ? AppColors.coral.withValues(alpha: 0.45)
                    : Colors.white,
                width: 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  _statusIcon,
                  color: accent,
                  size: 38,
                  semanticLabel: _statusLabel,
                ),
                const SizedBox(height: 5),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _statusLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: accent,
                      fontSize: 27,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _supportingText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(
                  height: 82,
                  child: Center(
                    child: phase == ConversationPhase.processing
                        ? const SizedBox.square(
                            dimension: 50,
                            child: CircularProgressIndicator(
                              strokeWidth: 5,
                              color: AppColors.indigo,
                            ),
                          )
                        : AnimatedScale(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 90),
                            scale: isRecording ? 0.94 + (amplitude * 0.14) : 1,
                            child: Transform.scale(
                              scaleX: 1.85,
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: accent.withValues(
                                  alpha: isRecording ? 0.88 : 0.58,
                                ),
                                size: 70,
                                semanticLabel: 'Mức âm thanh',
                              ),
                            ),
                          ),
                  ),
                ),
                if (isRecording)
                  FilledButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Dừng'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(132, 48),
                      backgroundColor: AppColors.coral,
                      foregroundColor: Colors.white,
                      elevation: 2,
                    ),
                  )
                else
                  Text(
                    _helperText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: -10,
          top: 0,
          child: IgnorePointer(
            child: Image.asset(
              'assets/images/mascot-robot.png',
              width: 94,
              height: 94,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'Robot trợ lý đang vẫy tay',
            ),
          ),
        ),
      ],
    );
  }

  String get _statusLabel => switch (phase) {
    ConversationPhase.idle => 'Con nói tiếng Việt',
    ConversationPhase.recording => 'Mình đang nghe…',
    ConversationPhase.processing => 'Mình đang giúp con…',
    ConversationPhase.ready => 'Đã có câu tiếng Anh',
    ConversationPhase.error => 'Mình thử lại nhé',
  };

  String get _supportingText => switch (phase) {
    ConversationPhase.idle => 'Mình sẽ giúp nói bằng tiếng Anh',
    ConversationPhase.recording => 'Nói tự nhiên và rõ ràng nhé',
    ConversationPhase.processing => 'Chỉ một chút thôi nhé',
    ConversationPhase.ready => 'Con có thể nghe lại câu bên dưới',
    ConversationPhase.error => 'Kiểm tra micro hoặc kết nối backend',
  };

  String get _helperText => switch (phase) {
    ConversationPhase.idle => 'Bấm nút micro bên dưới để bắt đầu',
    ConversationPhase.processing => '',
    ConversationPhase.ready => 'Bấm “Nói câu mới” để tiếp tục',
    ConversationPhase.error => 'Bấm “Thử lại” khi con sẵn sàng',
    ConversationPhase.recording => '',
  };

  IconData get _statusIcon => switch (phase) {
    ConversationPhase.idle => Icons.sentiment_very_satisfied_outlined,
    ConversationPhase.recording => Icons.hearing_rounded,
    ConversationPhase.processing => Icons.auto_awesome_rounded,
    ConversationPhase.ready => Icons.check_circle_outline_rounded,
    ConversationPhase.error => Icons.refresh_rounded,
  };
}
