import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/presentation/conversation_controller.dart';
import 'history_sheet.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({required this.controller, super.key});

  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Builder(
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            context.tr('Cài đặt lượt nói', '对话设置'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: context.tr('Đóng', '关闭'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(
                      label: context.tr('Ngôn ngữ hiển thị', '显示语言'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<DisplayLanguage>(
                        showSelectedIcon: false,
                        segments: DisplayLanguage.values
                            .map(
                              (language) => ButtonSegment<DisplayLanguage>(
                                value: language,
                                label: Text(language.nativeLabel),
                              ),
                            )
                            .toList(growable: false),
                        selected: <DisplayLanguage>{controller.displayLanguage},
                        onSelectionChanged: (selection) =>
                            controller.setDisplayLanguage(selection.first),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: context.tr('Ngữ cảnh', '场景')),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<PracticeContext>(
                        showSelectedIcon: false,
                        segments: PracticeContext.values
                            .map(
                              (item) => ButtonSegment<PracticeContext>(
                                value: item,
                                label: Text(context.trKnown(item.label)),
                              ),
                            )
                            .toList(growable: false),
                        selected: <PracticeContext>{controller.context},
                        onSelectionChanged: controller.isBusy
                            ? null
                            : (selection) =>
                                  controller.selectContext(selection.first),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: context.tr('Nguồn âm thanh', '音频输入')),
                    const SizedBox(height: 10),
                    _StatusTile(
                      icon: Icons.mic_rounded,
                      title: context.trKnown(controller.inputLabel),
                      detail: switch (controller.asrMode) {
                        AsrMode.androidStreaming => context.tr(
                          'Nhận chữ trực tiếp • fast path',
                          '直接识别文字 • 快速路径',
                        ),
                        AsrMode.openAiRealtime => context.tr(
                          'PCM16 24 kHz • ASR trực tiếp • Batch dự phòng',
                          'PCM16 24 kHz • 实时识别 • 分块备用',
                        ),
                        AsrMode.bleOfflineIntent => context.tr(
                          'BLE • offline fast path • Realtime dự phòng',
                          'BLE • 离线快速路径 • 实时备用',
                        ),
                        AsrMode.batchChunks => context.tr(
                          kIsWeb
                              ? 'PCM16 • truyền trong lúc nói • tự động dự phòng'
                              : 'PCM16 • chế độ dự phòng tự động',
                          kIsWeb ? 'PCM16 • 说话时传输 • 自动备用' : 'PCM16 • 自动备用模式',
                        ),
                        AsrMode.deviceStreaming => context.tr(
                          'Opus BLE • cần thiết bị thật',
                          'Opus BLE • 需要真实设备',
                        ),
                      },
                      trailing: context.tr('Đang dùng', '使用中'),
                      stateColor: AppColors.success,
                    ),
                    const SizedBox(height: 10),
                    _StatusTile(
                      icon: Icons.bluetooth_rounded,
                      title: context.tr('Mic INNOTRIK', 'INNOTRIK 麦克风'),
                      detail: context.tr(
                        'Cần native Opus decoder + thiết bị thật',
                        '需要原生 Opus 解码器和真实设备',
                      ),
                      trailing: context.tr('Chưa bật', '未启用'),
                      stateColor: AppColors.muted,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: context.tr('Chế độ nhận diện', '识别模式'),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<AsrMode>(
                      groupValue: controller.asrMode,
                      onChanged: (value) {
                        if (value != null) {
                          controller.selectAsrMode(value);
                        }
                      },
                      child: Column(
                        children: AsrMode.values
                            .where(
                              (mode) =>
                                  (mode.isUserSelectable ||
                                      (kIsWeb &&
                                          mode == AsrMode.batchChunks)) &&
                                  (!kIsWeb || mode == AsrMode.batchChunks) &&
                                  (mode != AsrMode.androidStreaming ||
                                      controller.supportsAndroidStreaming),
                            )
                            .map(
                              (mode) => RadioListTile<AsrMode>(
                                contentPadding: EdgeInsets.zero,
                                value: mode,
                                enabled: mode.isBackendSupported,
                                title: Text(
                                  kIsWeb && mode == AsrMode.batchChunks
                                      ? context.tr(
                                          'Nhận giọng nói trực tuyến',
                                          '在线语音识别',
                                        )
                                      : context.trKnown(mode.label),
                                ),
                                subtitle: Text(switch (mode) {
                                  AsrMode.androidStreaming => context.tr(
                                    'Nhanh như web streaming; tự dùng dịch vụ Android',
                                    '与网页流式识别一样快；自动使用 Android 服务',
                                  ),
                                  AsrMode.openAiRealtime => context.tr(
                                    'Nhận chữ khi đang nói; chỉ xử lý AI một lần sau khi dừng',
                                    '说话时实时识别；停止后仅处理一次 AI',
                                  ),
                                  AsrMode.bleOfflineIntent => context.tr(
                                    'Tự động cho BLE khi ý định có độ tin cậy cao',
                                    '当意图置信度高时自动用于 BLE',
                                  ),
                                  AsrMode.batchChunks => context.tr(
                                    kIsWeb
                                        ? 'Gửi từng phần khi đang nói; xử lý an toàn khi dừng'
                                        : 'Tự bật khi Realtime gặp lỗi; không cần chọn thủ công',
                                    kIsWeb
                                        ? '说话时分段发送；停止后安全处理'
                                        : '实时识别失败时自动启用；无需手动选择',
                                  ),
                                  AsrMode.deviceStreaming => context.tr(
                                    'Bật sau khi hoàn thiện BLE + Opus decoder',
                                    '完成 BLE 和 Opus 解码器后启用',
                                  ),
                                }),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _SectionLabel(
                          label: context.tr(
                            'Tự động dừng khi im lặng',
                            '静音时自动停止',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${controller.vadSilenceMs} ms',
                            style: const TextStyle(
                              color: AppColors.indigo,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: controller.vadSilenceMs.toDouble(),
                      min: 400,
                      max: 1600,
                      divisions: 12,
                      label: '${controller.vadSilenceMs} ms',
                      onChanged: controller.isBusy
                          ? null
                          : (value) => controller.setVadSilence(value.round()),
                    ),
                    Text(
                      context.tr(
                        '700 ms là mặc định; có thể tăng nếu trẻ thường ngắt câu.',
                        '默认 700 毫秒；如果孩子说话经常停顿，可以调高。',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 22),
                    OutlinedButton.icon(
                      onPressed: () => _showHistory(context),
                      icon: const Icon(Icons.history_rounded),
                      label: Text(context.tr('Xem lịch sử gần đây', '查看最近记录')),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: context.tr('Dữ liệu và quyền riêng tư', '数据与隐私'),
                    ),
                    const SizedBox(height: 10),
                    _DataPrivacyCard(
                      onOpenHistory: () => _showHistory(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'Khóa dịch vụ không được lưu trong ứng dụng trên thiết bị.',
                        '服务密钥不会存储在设备上的应用中。',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
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

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistorySheet(controller: controller),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.stateColor,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String trailing;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavender.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: AppColors.indigo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              trailing,
              style: TextStyle(
                color: stateColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataPrivacyCard extends StatelessWidget {
  const _DataPrivacyCard({required this.onOpenHistory});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.tr(
        'Dữ liệu lượt nói được lưu để phụ huynh xem lại. Có thể xóa từng lượt hoặc xóa toàn bộ lịch sử.',
        '对话记录会保存供家长查看。可以删除单条记录或清除全部历史。',
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('Quyền kiểm soát của phụ huynh', '家长控制'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.success),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Lịch sử giúp phụ huynh kiểm tra câu trẻ đã nói và phản hồi của hệ thống. Bạn có thể xóa từng lượt hoặc toàn bộ lịch sử bất cứ lúc nào.',
                '历史记录可帮助家长查看孩子说过的句子和系统反馈。你可以随时删除单条记录或清除全部历史。',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenHistory,
              icon: const Icon(Icons.manage_history_rounded),
              label: Text(context.tr('Xem hoặc xóa dữ liệu', '查看或删除数据')),
            ),
          ],
        ),
      ),
    );
  }
}
