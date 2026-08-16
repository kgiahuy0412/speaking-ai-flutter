import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../conversation/domain/conversation_models.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/main_speaking_session_controller.dart';
import '../application/voice_navigation_controller.dart';

class MainVoiceAssistantButton extends StatelessWidget {
  const MainVoiceAssistantButton({
    required this.voiceController,
    required this.conversationController,
    required this.speakingSessionController,
    required this.singleSentenceModeActive,
    required this.isActivationPending,
    required this.onPressed,
    required this.onLongPressed,
    required this.onLongPressReleased,
    super.key,
  });

  final VoiceNavigationController voiceController;
  final ConversationController conversationController;
  final MainSpeakingSessionController speakingSessionController;
  final bool singleSentenceModeActive;
  final bool isActivationPending;
  final Future<void> Function() onPressed;
  final Future<void> Function() onLongPressed;
  final Future<void> Function() onLongPressReleased;

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
        final canActivate = singleSentenceModeActive
            ? !isActivationPending &&
                  !isAssistantBusy &&
                  !conversationController.isPreparingMicrophone &&
                  conversationController.phase !=
                      ConversationPhase.processing &&
                  !conversationController.isPlaybackPlaying
            : !isActivationPending &&
                  !isSpeakingMode &&
                  !conversationController.isBusy &&
                  !conversationController.isPlaybackPlaying &&
                  !isAssistantBusy;
        final label = singleSentenceModeActive
            ? switch (conversationController.phase) {
                ConversationPhase.recording => 'Bấm để dịch',
                ConversationPhase.processing => 'Đang dịch...',
                _ when conversationController.isPreparingMicrophone =>
                  'Đang chuẩn bị...',
                _ when conversationController.isPlaybackPlaying =>
                  'Đang phát...',
                _ => 'Bấm để nói',
              }
            : isSpeakingMode
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
        final icon = singleSentenceModeActive
            ? switch (conversationController.phase) {
                ConversationPhase.recording => Icons.stop_rounded,
                ConversationPhase.processing => Icons.sync_rounded,
                _ when conversationController.isPlaybackPlaying =>
                  Icons.volume_up_rounded,
                _ => Icons.mic_rounded,
              }
            : isSpeakingMode
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
          label: singleSentenceModeActive
              ? '$label. Bấm ngắn để bắt đầu hoặc kết thúc câu; nhấn giữ một phẩy năm giây để gọi trợ lý.'
              : canActivate
              ? 'Main, gọi Bi cô để chọn tính năng'
              : isSpeakingMode
              ? '$label, ứng dụng sẽ tự động chuyển sang lượt tiếp theo'
              : '$label, vui lòng chờ',
          child: RawGestureDetector(
            gestures: <Type, GestureRecognizerFactory>{
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 1500),
                    ),
                    (recognizer) {
                      recognizer.onLongPress = () => unawaited(onLongPressed());
                      recognizer.onLongPressEnd = (_) =>
                          unawaited(onLongPressReleased());
                      recognizer.onLongPressCancel = () =>
                          unawaited(onLongPressReleased());
                    },
                  ),
            },
            child: FloatingActionButton.extended(
              key: const Key('main-voice-assistant-button'),
              heroTag: 'main-voice-assistant-button',
              onPressed: canActivate ? () => unawaited(onPressed()) : null,
              icon: Icon(icon),
              label: Text(label),
            ),
          ),
        );
      },
    );
  }
}
