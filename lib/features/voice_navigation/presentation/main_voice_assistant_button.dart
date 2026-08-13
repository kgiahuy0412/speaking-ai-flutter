import 'dart:async';

import 'package:flutter/material.dart';

import '../../conversation/presentation/conversation_controller.dart';
import '../application/main_speaking_session_controller.dart';
import '../application/voice_navigation_controller.dart';

class MainVoiceAssistantButton extends StatelessWidget {
  const MainVoiceAssistantButton({
    required this.voiceController,
    required this.conversationController,
    required this.speakingSessionController,
    required this.isActivationPending,
    required this.onPressed,
    super.key,
  });

  final VoiceNavigationController voiceController;
  final ConversationController conversationController;
  final MainSpeakingSessionController speakingSessionController;
  final bool isActivationPending;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        voiceController,
        conversationController,
        speakingSessionController,
      ]),
      builder: (context, _) {
        final speakingState = speakingSessionController.state;
        final isSpeakingMode = speakingSessionController.isActive;
        final isAssistantBusy = voiceController.isMainButtonSessionActive;
        final canActivate =
            !isActivationPending &&
            !isSpeakingMode &&
            !conversationController.isBusy &&
            !conversationController.isPlaybackPlaying &&
            !isAssistantBusy;
        final label = isSpeakingMode
            ? switch (speakingState) {
                MainSpeakingSessionState.ready => 'Đang chuẩn bị...',
                MainSpeakingSessionState.recording => 'Đang nghe...',
                MainSpeakingSessionState.processing =>
                  conversationController.isPreparingMicrophone
                      ? 'Đang chuẩn bị...'
                      : 'Đang dịch...',
                MainSpeakingSessionState.playing => 'Đang phát...',
                MainSpeakingSessionState.inactive => 'Main',
              }
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAcknowledgingWakeWord
            ? 'Bi cô đang nói...'
            : voiceController.isMainButtonSessionActive &&
                  (voiceController.isAwaitingCommand ||
                      voiceController.isListening)
            ? 'Đang nghe...'
            : 'Main';
        final icon = isSpeakingMode
            ? switch (speakingState) {
                MainSpeakingSessionState.ready => Icons.mic_rounded,
                MainSpeakingSessionState.recording => Icons.hearing_rounded,
                MainSpeakingSessionState.processing => Icons.sync_rounded,
                MainSpeakingSessionState.playing => Icons.volume_up_rounded,
                MainSpeakingSessionState.inactive => Icons.auto_awesome_rounded,
              }
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAwaitingCommand
            ? Icons.hearing_rounded
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAcknowledgingWakeWord
            ? Icons.campaign_rounded
            : Icons.auto_awesome_rounded;

        return Semantics(
          button: true,
          label: canActivate
              ? 'Main, gọi Bi cô để chọn tính năng'
              : isSpeakingMode
              ? '$label, ứng dụng sẽ tự động chuyển sang lượt tiếp theo'
              : '$label, vui lòng chờ',
          child: FloatingActionButton.extended(
            key: const Key('main-voice-assistant-button'),
            heroTag: 'main-voice-assistant-button',
            onPressed: canActivate ? () => unawaited(onPressed()) : null,
            icon: Icon(icon),
            label: Text(label),
          ),
        );
      },
    );
  }
}
