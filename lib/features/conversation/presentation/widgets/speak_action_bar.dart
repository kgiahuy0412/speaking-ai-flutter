import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../domain/conversation_models.dart';

class SpeakActionBar extends StatelessWidget {
  const SpeakActionBar({
    required this.phase,
    required this.onPressed,
    super.key,
  });

  final ConversationPhase phase;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isRecording = phase == ConversationPhase.recording;
    final isProcessing = phase == ConversationPhase.processing;
    final primary = isRecording ? AppColors.coral : AppColors.indigo;
    final secondary = isRecording
        ? const Color(0xFFE9524A)
        : AppColors.indigoDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SafeArea(
        top: false,
        child: Semantics(
          button: true,
          enabled: !isProcessing,
          label: _label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isProcessing
                    ? <Color>[
                        AppColors.indigo.withValues(alpha: 0.38),
                        AppColors.indigoDark.withValues(alpha: 0.38),
                      ]
                    : <Color>[primary, secondary],
              ),
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
                        isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 31,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            _label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: Colors.white, fontSize: 20),
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

  String get _label => switch (phase) {
    ConversationPhase.recording => 'Dừng ghi âm',
    ConversationPhase.processing => 'Đang xử lý…',
    ConversationPhase.ready => 'Nói câu mới',
    ConversationPhase.error => 'Thử lại',
    ConversationPhase.idle => 'Bắt đầu nói',
  };
}
