import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/presentation/conversation_controller.dart';
import 'history_sheet.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
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
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Cài đặt lượt nói',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Đóng',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionLabel(label: 'Ngữ cảnh'),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<PracticeContext>(
                    showSelectedIcon: false,
                    segments: PracticeContext.values
                        .map(
                          (item) => ButtonSegment<PracticeContext>(
                            value: item,
                            label: Text(item.label),
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
                const _SectionLabel(label: 'Nguồn âm thanh'),
                const SizedBox(height: 10),
                _StatusTile(
                  icon: Icons.mic_rounded,
                  title: controller.inputLabel,
                  detail: switch (controller.asrMode) {
                    AsrMode.androidStreaming =>
                      'Nhận chữ trực tiếp • fast path',
                    AsrMode.openAiRealtime =>
                      'PCM16 24 kHz • ASR trực tiếp • Batch dự phòng',
                    AsrMode.bleOfflineIntent =>
                      'BLE • offline fast path • Realtime dự phòng',
                    AsrMode.batchChunks => 'PCM16 • chế độ dự phòng tự động',
                    AsrMode.deviceStreaming => 'Opus BLE • cần thiết bị thật',
                  },
                  trailing: 'Đang dùng',
                  stateColor: AppColors.success,
                ),
                const SizedBox(height: 10),
                const _StatusTile(
                  icon: Icons.bluetooth_rounded,
                  title: 'Mic INNOTRIK',
                  detail: 'Cần native Opus decoder + thiết bị thật',
                  trailing: 'Chưa bật',
                  stateColor: AppColors.muted,
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'ASR mode'),
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
                        .where((mode) => mode.isUserSelectable)
                        .map(
                          (mode) => RadioListTile<AsrMode>(
                            contentPadding: EdgeInsets.zero,
                            value: mode,
                            enabled: mode.isBackendSupported,
                            title: Text(mode.label),
                            subtitle: Text(switch (mode) {
                              AsrMode.androidStreaming =>
                                'Nhanh như web streaming; tự dùng dịch vụ Android',
                              AsrMode.openAiRealtime =>
                                'Nhận chữ khi đang nói; chỉ xử lý AI một lần sau khi dừng',
                              AsrMode.bleOfflineIntent =>
                                'Tự động cho BLE khi ý định có độ tin cậy cao',
                              AsrMode.batchChunks =>
                                'Tự bật khi Realtime gặp lỗi; không cần chọn thủ công',
                              AsrMode.deviceStreaming =>
                                'Bật sau khi hoàn thiện BLE + Opus decoder',
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
                    const _SectionLabel(label: 'VAD tự dừng'),
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
                  '700 ms là mặc định; có thể tăng nếu trẻ thường ngắt câu.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Backend'),
                const SizedBox(height: 8),
                SelectableText(
                  config.backendBaseUri.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => _showHistory(context),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Xem lịch sử gần đây'),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(label: 'Dữ liệu và quyền riêng tư'),
                const SizedBox(height: 10),
                _DataPrivacyCard(onOpenHistory: () => _showHistory(context)),
                const SizedBox(height: 10),
                Text(
                  'API key chỉ nằm trên backend; APK không chứa khóa OpenAI.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
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
      label:
          'Dữ liệu lượt nói được lưu để phụ huynh xem lại. '
          'Có thể xóa từng lượt, xóa toàn bộ hoặc xuất bản sao từ trang admin.',
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
              'Quyền kiểm soát của phụ huynh',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.success),
            ),
            const SizedBox(height: 8),
            Text(
              'Lịch sử giúp phụ huynh kiểm tra câu trẻ đã nói và phản hồi của hệ thống. '
              'Bạn có thể xóa từng lượt hoặc toàn bộ lịch sử bất cứ lúc nào. '
              'Bản xuất JSON theo thiết bị có trong trang admin.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenHistory,
              icon: const Icon(Icons.manage_history_rounded),
              label: const Text('Xem hoặc xóa dữ liệu'),
            ),
          ],
        ),
      ),
    );
  }
}
