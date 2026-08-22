import 'dart:async';

import 'package:flutter/gestures.dart';
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
    required this.onLongPressed,
    required this.onLongPressReleased,
    super.key,
  });

  final VoiceNavigationController voiceController;
  final ConversationController conversationController;
  final MainSpeakingSessionController speakingSessionController;
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
        final canActivate =
            !isActivationPending &&
            !isSpeakingMode &&
            !conversationController.isBusy &&
            !conversationController.isPlaybackPlaying &&
            !isAssistantBusy;
        final microphoneError = voiceController.lastErrorMessage;
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
                  voiceController.isListening
            ? 'Đang nghe...'
            : voiceController.isMainButtonSessionActive &&
                  microphoneError != null
            ? 'Đang thử lại mic...'
            : voiceController.isMainButtonSessionActive &&
                  (voiceController.isStarting ||
                      voiceController.isAwaitingCommand)
            ? 'Đang chuẩn bị mic...'
            : microphoneError != null
            ? 'Thử lại mic'
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
                  voiceController.isListening
            ? Icons.hearing_rounded
            : voiceController.isMainButtonSessionActive &&
                  microphoneError != null
            ? Icons.sync_problem_rounded
            : voiceController.isMainButtonSessionActive &&
                  (voiceController.isStarting ||
                      voiceController.isAwaitingCommand)
            ? Icons.mic_none_rounded
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAcknowledgingWakeWord
            ? Icons.campaign_rounded
            : microphoneError != null
            ? Icons.error_outline_rounded
            : Icons.auto_awesome_rounded;
        final microphoneStatus = microphoneError == null
            ? '${voiceController.activeInputLabel}: $label'
            : '$microphoneError Bấm Main để thử lại.';

        return Semantics(
          button: true,
          label: canActivate
              ? microphoneError == null
                    ? 'Main, gọi Bi cô để chọn tính năng'
                    : microphoneStatus
              : isSpeakingMode
              ? '$label, ứng dụng sẽ tự động chuyển sang lượt tiếp theo'
              : '$microphoneStatus Vui lòng chờ.',
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
              tooltip: microphoneStatus,
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
