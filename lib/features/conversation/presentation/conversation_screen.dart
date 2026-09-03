import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../config/app_config.dart';
import '../../../l10n/display_language.dart';
import '../../home/presentation/scenic_app_header.dart';
import '../../settings/presentation/history_sheet.dart';
import '../../settings/presentation/settings_sheet.dart';
import 'conversation_controller.dart';
import 'widgets/result_panel.dart';
import 'widgets/speak_action_bar.dart';
import 'widgets/voice_hero.dart';

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    required this.controller,
    required this.config,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.onModalVisibilityChanged,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.onOpenHistory,
    this.onOpenSettings,
    this.speakActionKey,
    this.resultPanelKey,
    this.historyButtonKey,
    this.settingsButtonKey,
    super.key,
  });

  final ConversationController controller;
  final AppConfig config;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final ValueChanged<bool>? onModalVisibilityChanged;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;
  final Key? speakActionKey;
  final Key? resultPanelKey;
  final Key? historyButtonKey;
  final Key? settingsButtonKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).height < 900;
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LearningScenery(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    ScenicAppHeader(
                      isReady: controller.isInputAvailable,
                      onHistory: onOpenHistory ?? () => _showHistory(context),
                      onSettings:
                          onOpenSettings ?? () => _showSettings(context),
                      historyButtonKey: historyButtonKey,
                      settingsButtonKey: settingsButtonKey,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SingleChildScrollView(
                            key: const Key('conversation-home-scroll'),
                            padding: EdgeInsets.fromLTRB(
                              28,
                              compact ? 44 : 70,
                              28,
                              18,
                            ),
                            child: Column(
                              children: <Widget>[
                                VoiceHero(
                                  phase: controller.phase,
                                  processingStage: controller.processingStage,
                                  amplitude: controller.amplitude,
                                  isPreparingMicrophone:
                                      controller.isPreparingMicrophone,
                                  onStop: () => unawaited(
                                    controller.stopRecording(manual: true),
                                  ),
                                ),
                                SizedBox(height: compact ? 24 : 28),
                                ResultPanel(
                                  key: resultPanelKey,
                                  result: controller.result,
                                  onPlay: () =>
                                      unawaited(controller.playResult()),
                                ),
                                if (controller.errorMessage != null ||
                                    controller.transientMessage !=
                                        null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  _InlineMessage(
                                    isError: controller.errorMessage != null,
                                    message:
                                        controller.errorMessage ??
                                        controller.transientMessage!,
                                    onDismiss: controller.clearMessage,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SpeakActionBar(
                      key: speakActionKey,
                      phase: controller.phase,
                      processingStage: controller.processingStage,
                      isPreparingMicrophone: controller.isPreparingMicrophone,
                      onPressed: () => unawaited(controller.onPrimaryAction()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    await controller.markParentDiagnosticsOpened();
    if (!context.mounted) return;
    onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SettingsSheet(
          controller: controller,
          themeMode: themeMode,
          onThemeModeChanged: onThemeModeChanged,
          onChildAgeChanged: onChildAgeChanged,
          onStartTutorial: onStartTutorial,
          config: config,
          privacyConsentGranted: privacyConsentGranted,
          voiceAccessEnabled: voiceAccessEnabled,
          onRequestVoiceAccess: onRequestVoiceAccess,
          onManagePrivacyConsent: onManagePrivacyConsent,
          onRevokePrivacyConsent: onRevokePrivacyConsent,
        ),
      );
    } finally {
      onModalVisibilityChanged?.call(false);
    }
  }

  Future<void> _showHistory(BuildContext context) async {
    onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HistorySheet(controller: controller),
      );
    } finally {
      onModalVisibilityChanged?.call(false);
    }
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.isError,
    required this.message,
    required this.onDismiss,
  });

  final bool isError;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Theme.of(context).colorScheme.error : AppColors.ink;
    final localizedMessage = context.trKnown(message);
    return Semantics(
      liveRegion: true,
      label: localizedMessage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: isError ? const Color(0xFFFFF1F0) : AppColors.lavender,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: color,
              size: 21,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localizedMessage,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
              tooltip: context.tr('Ẩn thông báo', '隐藏通知'),
            ),
          ],
        ),
      ),
    );
  }
}
