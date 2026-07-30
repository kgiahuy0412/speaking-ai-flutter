import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../l10n/display_language.dart';
import '../../listening/presentation/listening_route_names.dart';
import '../../listening/presentation/topic_listening_screen.dart';
import '../../settings/presentation/history_sheet.dart';
import '../../settings/presentation/settings_sheet.dart';
import '../domain/conversation_models.dart';
import 'conversation_controller.dart';
import 'widgets/feedback_buttons.dart';
import 'widgets/result_panel.dart';
import 'widgets/speak_action_bar.dart';
import 'widgets/voice_hero.dart';

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    required this.controller,
    required this.config,
    super.key,
  });

  final ConversationController controller;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  _AppHeader(
                    inputLabel: controller.inputLabel,
                    isReady: controller.isInputAvailable,
                    onHistory: () => _showHistory(context),
                    onSettings: () => _showSettings(context),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 5, 20, 18),
                      child: Column(
                        children: <Widget>[
                          _TopicListeningShortcut(
                            childAge: config.childAge,
                            onPressed: () => _openTopicListening(context),
                          ),
                          const SizedBox(height: 12),
                          VoiceHero(
                            phase: controller.phase,
                            processingStage: controller.processingStage,
                            amplitude: controller.amplitude,
                            onStop: () => unawaited(
                              controller.stopRecording(manual: true),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ResultPanel(
                            result: controller.result,
                            onPlay: () => unawaited(controller.playResult()),
                          ),
                          const SizedBox(height: 12),
                          FeedbackButtons(
                            enabled:
                                controller.result != null &&
                                controller.phase !=
                                    ConversationPhase.processing,
                            selectedValue: controller.qualityApproved,
                            onSelected: (value) =>
                                unawaited(controller.submitReview(value)),
                          ),
                          if (controller.errorMessage != null ||
                              controller.transientMessage != null) ...<Widget>[
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
                  SpeakActionBar(
                    phase: controller.phase,
                    processingStage: controller.processingStage,
                    onPressed: () => unawaited(controller.onPrimaryAction()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SettingsSheet(controller: controller),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistorySheet(controller: controller),
    );
  }

  void _openTopicListening(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: ListeningRouteNames.topicCatalog),
        builder: (_) => TopicListeningScreen(
          language: controller.displayLanguage,
          childAge: config.childAge,
          controller: controller,
        ),
      ),
    );
  }
}

class _TopicListeningShortcut extends StatelessWidget {
  const _TopicListeningShortcut({
    required this.childAge,
    required this.onPressed,
  });

  final int childAge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = context.tr('Luyện nghe theo chủ đề', '按主题练听力');
    final subtitle = context.tr(
      '50 chủ đề theo độ tuổi của con',
      '50 个适合孩子年龄的主题',
    );
    final ageLabel = _ageLabel(context);

    return Semantics(
      button: true,
      label: title,
      hint: context.tr('Mở danh sách chủ đề luyện nghe', '打开听力主题列表'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFD9DFFF),
                Color(0xFFF0E7FF),
                Color(0xFFDEDBFF),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFD7D8FF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x160D1B4C),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            key: const Key('topic-listening-shortcut'),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 112),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 78,
                      height: 90,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: <Widget>[
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xB3FFFFFF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Transform.scale(
                            scale: 1.28,
                            child: Image.asset(
                              'assets/images/mascot-robot.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: AppColors.ink,
                                  fontSize: 17,
                                  height: 1.15,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: <Widget>[
                              _ShortcutBadge(
                                icon: Icons.face_rounded,
                                label: ageLabel,
                              ),
                              _ShortcutBadge(
                                icon: Icons.menu_book_rounded,
                                label: context.tr('10 bài/chủ đề', '每主题 10 课'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: AppColors.indigo,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Color(0x403D4DD6),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _ageLabel(BuildContext context) {
    final range = switch (childAge) {
      <= 5 => '3–5',
      <= 7 => '6–7',
      <= 10 => '8–10',
      <= 12 => '11–12',
      _ => '13–15',
    };
    return context.tr('$range tuổi', '$range 岁');
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD9FFFFFF),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFC9CAFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: AppColors.indigo),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: const TextStyle(
                  color: AppColors.indigoDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.inputLabel,
    required this.isReady,
    required this.onHistory,
    required this.onSettings,
  });

  final String inputLabel;
  final bool isReady;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final compactInputLabel = context.trKnown(switch (inputLabel) {
      final label when label.contains('Android') => 'Chế độ tiêu chuẩn',
      final label when label.contains('INNOTRIK') => 'Mic INNOTRIK',
      final label => label,
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 7),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.lavender,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x140D1B4C),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Transform.scale(
              scale: 1.15,
              child: Image.asset(
                'assets/images/mascot-robot.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Trợ lý giao tiếp', '沟通助手'),
                  maxLines: largeText ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: largeText ? 20 : 24,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: isReady ? AppColors.success : AppColors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isReady
                            ? '$compactInputLabel • ${context.tr('Sẵn sàng', '已就绪')}'
                            : context.tr('Chưa kết nối', '未连接'),
                        maxLines: largeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          fontSize: largeText ? 12 : 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded),
            tooltip: context.tr('Lịch sử gần đây', '最近记录'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              maximumSize: const Size.square(44),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              maximumSize: const Size.square(44),
            ),
            tooltip: context.tr('Cài đặt', '设置'),
          ),
        ],
      ),
    );
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
