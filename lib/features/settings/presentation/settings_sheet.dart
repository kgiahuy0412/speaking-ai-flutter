import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/audio/audio_input.dart';
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
                    _InnotrikStatusCard(
                      status: controller.bluetoothAudioStatus,
                      disabled: controller.isBusy,
                      diagnosticRunning: controller.bleDiagnosticRunning,
                      onScan: () => _scanAndConnect(context),
                      onTest: () => _testInnotrik(context),
                      onDisconnect: controller.disconnectInnotrikDevice,
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
                                enabled:
                                    mode.isBackendSupported &&
                                    (mode != AsrMode.deviceStreaming ||
                                        controller.canUseInnotrikBle),
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
                                    controller.canUseInnotrikBle
                                        ? 'INNOTRIK Opus → PCM16 24 kHz → Realtime/Batch'
                                        : 'Kết nối Mic INNOTRIK ở phía trên để bật',
                                    controller.canUseInnotrikBle
                                        ? 'INNOTRIK Opus → PCM16 24 kHz → 实时/分块识别'
                                        : '请先在上方连接 INNOTRIK 麦克风',
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

  Future<void> _scanAndConnect(BuildContext context) async {
    try {
      final devices = await controller.scanInnotrikDevices();
      if (!context.mounted) {
        return;
      }
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không tìm thấy thiết bị. Hãy bật INNOTRIK và thử lại.',
                '未找到设备。请打开 INNOTRIK 后重试。',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<BluetoothAudioDevice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Chọn thiết bị INNOTRIK', '选择 INNOTRIK 设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Thiết bị đúng giao thức được ưu tiên ở đầu danh sách.',
                    '符合协议的设备会优先显示在列表顶部。',
                  ),
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: device.isLikelyInnotrik
                              ? AppColors.lavender
                              : const Color(0xFFF1F2F8),
                          child: Icon(
                            device.isLikelyInnotrik
                                ? Icons.bluetooth_connected_rounded
                                : Icons.bluetooth_rounded,
                            color: device.isLikelyInnotrik
                                ? AppColors.indigo
                                : AppColors.muted,
                          ),
                        ),
                        title: Text(device.displayName),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
                        trailing: device.isLikelyInnotrik
                            ? const Icon(
                                Icons.verified_rounded,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !context.mounted) {
        return;
      }
      await controller.connectInnotrikDevice(selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Đã kết nối. Hãy nói thử để kiểm tra Mic INNOTRIK.',
                '已连接。请说话测试 INNOTRIK 麦克风。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _testInnotrik(BuildContext context) async {
    try {
      await controller.testInnotrikMicrophone();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Kiểm tra hoàn tất. Nếu nghe đúng giọng vừa nói, decoder hoạt động tốt.',
                '测试完成。如果能听到刚才的声音，说明解码器工作正常。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
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

class _InnotrikStatusCard extends StatelessWidget {
  const _InnotrikStatusCard({
    required this.status,
    required this.disabled,
    required this.diagnosticRunning,
    required this.onScan,
    required this.onTest,
    required this.onDisconnect,
  });

  final BluetoothAudioStatus status;
  final bool disabled;
  final bool diagnosticRunning;
  final VoidCallback onScan;
  final VoidCallback onTest;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = status.isConnected;
    final busy = status.isBusy;
    final stateColor = connected
        ? AppColors.success
        : status.phase == BluetoothAudioConnectionPhase.error
        ? AppColors.coral
        : AppColors.muted;
    final deviceName = status.deviceName?.trim();
    final detail = _detail(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: connected ? AppColors.successSoft : const Color(0xFFF8F8FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: stateColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_searching_rounded,
                  color: stateColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deviceName == null || deviceName.isEmpty
                          ? context.tr('Mic INNOTRIK', 'INNOTRIK 麦克风')
                          : deviceName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    if (status.packetCount > 0) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        context.tr(
                          '${status.packetCount} gói • ${status.decodedPcmBytes ~/ 1024} KB PCM • ${status.invalidPacketCount} lỗi',
                          '${status.packetCount} 个数据包 • ${status.decodedPcmBytes ~/ 1024} KB PCM • ${status.invalidPacketCount} 个错误',
                        ),
                        style: const TextStyle(
                          color: AppColors.indigo,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (busy || diagnosticRunning)
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  if (connected)
                    TextButton.icon(
                      onPressed: disabled ? null : onTest,
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: Text(context.tr('Test mic 4 giây', '测试麦克风 4 秒')),
                    ),
                  TextButton(
                    onPressed:
                        disabled ||
                            status.phase ==
                                BluetoothAudioConnectionPhase.unsupported ||
                            status.phase ==
                                BluetoothAudioConnectionPhase.disabled
                        ? null
                        : connected
                        ? () => onDisconnect()
                        : onScan,
                    child: Text(
                      connected
                          ? context.tr('Ngắt', '断开')
                          : context.tr('Quét & nối', '扫描连接'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _detail(BuildContext context) {
    return switch (status.phase) {
      BluetoothAudioConnectionPhase.disabled => context.tr(
        'BLE INNOTRIK đang tắt trong cấu hình bản build.',
        '此构建中已关闭 INNOTRIK BLE。',
      ),
      BluetoothAudioConnectionPhase.unsupported => context.tr(
        'Điện thoại hoặc bản ứng dụng này không hỗ trợ BLE.',
        '此手机或应用版本不支持 BLE。',
      ),
      BluetoothAudioConnectionPhase.permissionRequired => context.tr(
        'Cần quyền Thiết bị ở gần/Bluetooth.',
        '需要“附近设备/蓝牙”权限。',
      ),
      BluetoothAudioConnectionPhase.scanning => context.tr(
        'Đang tìm thiết bị ở gần…',
        '正在搜索附近设备…',
      ),
      BluetoothAudioConnectionPhase.connecting => context.tr(
        'Đang kết nối GATT…',
        '正在连接 GATT…',
      ),
      BluetoothAudioConnectionPhase.discovering => context.tr(
        'Đang kiểm tra FF12/FF13/FF14…',
        '正在检查 FF12/FF13/FF14…',
      ),
      BluetoothAudioConnectionPhase.ready => context.tr(
        'Đã kết nối • Opus decoder sẵn sàng • 24 kHz PCM',
        '已连接 • Opus 解码器就绪 • 24 kHz PCM',
      ),
      BluetoothAudioConnectionPhase.recording => context.tr(
        'Đang nhận audio thật từ INNOTRIK',
        '正在接收 INNOTRIK 的真实音频',
      ),
      BluetoothAudioConnectionPhase.error =>
        status.message ?? context.tr('Kết nối gặp lỗi.', '连接发生错误。'),
      BluetoothAudioConnectionPhase.idle => context.tr(
        'Bật thiết bị rồi quét để kết nối.',
        '打开设备后扫描连接。',
      ),
    };
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
