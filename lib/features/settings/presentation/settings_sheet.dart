import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../privacy/presentation/parental_gate.dart';
import 'history_sheet.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    required this.controller,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    super.key,
  });

  final ConversationController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isAndroid =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
        final nativeDiagnostic = controller.nativeSpeechDiagnostic;
        final h20State = controller.h20ConnectionState();
        final nativeDiagnosticTimeline = controller
            .nativeSpeechDiagnosticLog
            .reversed
            .take(40)
            .toList(growable: false)
            .reversed
            .map(
              (item) => <String>[
                if (item.elapsedMs != null) '+${item.elapsedMs}ms',
                item.stage,
                if (item.caller != null) '@${item.caller}',
              ].join(' '),
            )
            .join('\n');
        final nativeDiagnosticDetail = nativeDiagnostic == null
            ? null
            : <String>[
                if (nativeDiagnosticTimeline.isNotEmpty)
                  nativeDiagnosticTimeline,
                if (nativeDiagnostic.turnId != null)
                  'turn=${nativeDiagnostic.turnId}',
                if (nativeDiagnostic.audioSource != null)
                  'source=${nativeDiagnostic.audioSource}',
                if (nativeDiagnostic.audioRoute != null)
                  'route=${nativeDiagnostic.audioRoute}',
                if (nativeDiagnostic.code != null)
                  'code=${nativeDiagnostic.code}',
                if (nativeDiagnostic.message != null) nativeDiagnostic.message!,
              ].join(' • ');
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
                    _AppearanceSelector(
                      value: themeMode,
                      onChanged: onThemeModeChanged,
                    ),
                    const SizedBox(height: 24),
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
                    _SectionLabel(
                      label: context.tr('Nhóm tuổi của trẻ', '孩子年龄组'),
                    ),
                    const SizedBox(height: 10),
                    _ChildAgeGroupSelector(
                      childAge: controller.childAge,
                      enabled: !controller.isBusy && onChildAgeChanged != null,
                      onChanged: onChildAgeChanged,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: context.tr('Nguồn âm thanh', '音频输入')),
                    const SizedBox(height: 10),
                    _StatusTile(
                      icon: Icons.mic_rounded,
                      title: context.trKnown(controller.inputLabel),
                      detail: isAndroid
                          ? context.tr(
                              controller.usesHfpInput
                                  ? 'H20 qua HFP/SCO • Chế độ tiêu chuẩn'
                                  : 'Mic điện thoại • Chế độ tiêu chuẩn',
                              controller.usesHfpInput
                                  ? 'H20 通过 HFP/SCO • 标准模式'
                                  : '手机麦克风 • 标准模式',
                            )
                          : isIOS
                          ? context.tr(
                              controller.usesHfpInput
                                  ? 'Mic H20 qua HFP • Apple Speech ưu tiên'
                                  : 'Mic iPhone/iPad • Apple Speech ưu tiên',
                              controller.usesHfpInput
                                  ? 'H20 HFP 麦克风 • 优先使用 Apple Speech'
                                  : 'iPhone/iPad 麦克风 • 优先使用 Apple Speech',
                            )
                          : switch (controller.asrMode) {
                              AsrMode.androidStreaming => context.tr(
                                'Nhận chữ trực tiếp • fast path',
                                '直接识别文字 • 快速路径',
                              ),
                              AsrMode.hfpStreaming => context.tr(
                                controller.supportsBrowserHfp
                                    ? 'Mic Bluetooth HFP • trình duyệt quản lý'
                                    : 'Mic Bluetooth HFP/SCO • Android ASR',
                                controller.supportsBrowserHfp
                                    ? '蓝牙 HFP 麦克风 • 浏览器管理'
                                    : '蓝牙 HFP/SCO 麦克风 • Android 识别',
                              ),
                              AsrMode.openAiRealtime => context.tr(
                                'PCM16 16 kHz • ASR trực tiếp • Batch dự phòng',
                                'PCM16 16 kHz • 实时识别 • 分块备用',
                              ),
                              AsrMode.bleOfflineIntent => context.tr(
                                'BLE • offline fast path • Cloudflare Batch dự phòng',
                                'BLE • 离线快速路径 • Cloudflare 分块备用',
                              ),
                              AsrMode.workerAsrPilot => context.tr(
                                'PCM16 16 kHz • Worker ASR Pilot • Batch dự phòng',
                                'PCM16 16 kHz • Worker 识别试验 • 分块备用',
                              ),
                              AsrMode.batchChunks => context.tr(
                                kIsWeb
                                    ? 'PCM16 • truyền trong lúc nói • Cloudflare chính'
                                    : 'PCM16 • Cloudflare ASR chính',
                                kIsWeb
                                    ? 'PCM16 • 说话时传输 • Cloudflare 主服务'
                                    : 'PCM16 • Cloudflare 语音识别主服务',
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
                      icon: Icons.headset_mic_rounded,
                      title: context.tr('Trạng thái H20 tổng hợp', 'H20 综合状态'),
                      detail: context.tr(
                        h20State.isH20Ready
                            ? 'HFP và BLE Control đều sẵn sàng.'
                            : h20State.hfpReady
                            ? 'HFP sẵn sàng; BLE Control chưa sẵn sàng.'
                            : h20State.bleReady
                            ? 'BLE Control sẵn sàng; HFP chưa sẵn sàng.'
                            : 'HFP và BLE Control chưa sẵn sàng.',
                        h20State.isH20Ready
                            ? 'HFP 与 BLE 控制均已就绪。'
                            : h20State.hfpReady
                            ? 'HFP 已就绪；BLE 控制尚未就绪。'
                            : h20State.bleReady
                            ? 'BLE 控制已就绪；HFP 尚未就绪。'
                            : 'HFP 与 BLE 控制均未就绪。',
                      ),
                      trailing: h20State.isH20Ready
                          ? context.tr('Sẵn sàng', '已就绪')
                          : context.tr('Chưa đủ', '未完整'),
                      stateColor: h20State.isH20Ready
                          ? AppColors.success
                          : AppColors.coral,
                    ),
                    ...<Widget>[
                      const SizedBox(height: 10),
                      _Aiv0BleControlCard(
                        status: controller.aiv0BleStatus,
                        events: controller.aiv0ButtonEventLog,
                        mainDispatchStatus: controller.aiv0MainDispatchStatus,
                        mainDispatchAt: controller.aiv0MainDispatchAt,
                        disabled: controller.isBusy,
                        onScan: () => _scanAndConnectAiv0(context),
                        onDisconnect: controller.disconnectAiv0Device,
                      ),
                      const SizedBox(height: 10),
                      _HfpStatusCard(
                        status: controller.hfpAudioStatus,
                        browserManaged: controller.supportsBrowserHfp,
                        selected: controller.usesHfpInput,
                        disabled: controller.isBusy,
                        onFind: () => _findAndConnectHfp(context),
                        onDisconnect: controller.disconnectHfpDevice,
                      ),
                    ],
                    if (isAndroid) ...<Widget>[
                      const SizedBox(height: 10),
                      _H20OfflineHardwareTestCard(
                        enabled: controller.h20HardwareTestModeEnabled,
                        phase: controller.h20HardwareTestPhase,
                        message: controller.h20HardwareTestMessage,
                        result: controller.h20HardwareTestResult,
                        bleConnected: controller.canUseAiv0Ble,
                        mainProtocolConfirmed:
                            controller.aiv0BleStatus.protocolConfirmed,
                        hfpStatus: controller.hfpAudioStatus,
                        conversationBusy:
                            controller.phase == ConversationPhase.recording ||
                            controller.phase == ConversationPhase.processing,
                        onEnabledChanged: (enabled) =>
                            _setH20HardwareTestMode(context, enabled),
                        onRecord: () => _toggleH20OfflineRecording(context),
                        onSpeakerTest: () => _playH20SpeakerTest(context),
                        onPlaybackConfirmed:
                            controller.confirmH20PlaybackAudible,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: kIsWeb
                          ? context.tr('Chế độ nhận diện', '识别模式')
                          : context.tr('Nhận dạng', '语音识别'),
                    ),
                    const SizedBox(height: 8),
                    if (isAndroid)
                      _StatusTile(
                        key: const Key('android-standard-recognition'),
                        icon: Icons.record_voice_over_rounded,
                        title: context.tr('Chế độ tiêu chuẩn', '标准模式'),
                        detail: context.tr(
                          'Nhận dạng trực tiếp bằng dịch vụ Android. Cloudflare chỉ dịch văn bản và tạo giọng đọc khi cần, không nhận dạng audio.',
                          '使用 Android 服务直接识别。Cloudflare 仅在需要时翻译文本和生成语音，不识别音频。',
                        ),
                        trailing: context.tr('Mặc định', '默认'),
                        stateColor: AppColors.success,
                      )
                    else if (isIOS)
                      _StatusTile(
                        key: const Key('ios-native-recognition'),
                        icon: Icons.record_voice_over_rounded,
                        title: context.tr(
                          'Apple Native Speech',
                          'Apple 原生语音识别',
                        ),
                        detail: context.tr(
                          'iOS dùng một luồng Apple Native Speech cho MAIN; không đổi mic hoặc chuyển sang Batch trong cùng lượt.${nativeDiagnosticDetail == null ? '' : '\n\n$nativeDiagnosticDetail'}',
                          'iOS 的 MAIN 仅使用一条 Apple 原生语音识别流程；同一轮不会切换麦克风或转入 Batch。${nativeDiagnosticDetail == null ? '' : '\n\n$nativeDiagnosticDetail'}',
                        ),
                        trailing:
                            nativeDiagnostic?.stage ??
                            context.tr('Ưu tiên', '优先'),
                        stateColor: nativeDiagnostic?.isError == true
                            ? AppColors.coral
                            : AppColors.success,
                      )
                    else
                      _StatusTile(
                        key: const Key('web-online-recognition'),
                        icon: Icons.cloud_done_rounded,
                        title: context.tr(
                          'Nhận giọng nói trực tuyến',
                          '在线语音识别',
                        ),
                        detail: context.tr(
                          controller.usesHfpInput
                              ? 'Đang nhận âm thanh từ mic Bluetooth đã chọn; Cloudflare xử lý nhận dạng, dịch và phát âm.'
                              : 'Đang nhận âm thanh từ mic mặc định; Cloudflare xử lý nhận dạng, dịch và phát âm.',
                          controller.usesHfpInput
                              ? '使用已选择的蓝牙麦克风；由 Cloudflare 完成识别、翻译和语音合成。'
                              : '使用默认麦克风；由 Cloudflare 完成识别、翻译和语音合成。',
                        ),
                        trailing: context.tr('Mặc định', '默认'),
                        stateColor: AppColors.success,
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
                    const SizedBox(height: 26),
                    _SectionLabel(
                      label: context.tr('Dữ liệu và quyền riêng tư', '数据与隐私'),
                    ),
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      key: const Key('settings-privacy-policy'),
                      icon: Icons.privacy_tip_outlined,
                      title: context.tr('Chính sách quyền riêng tư', '隐私政策'),
                      detail: context.tr(
                        'Xem dữ liệu được thu thập, nhà cung cấp AI, thời hạn lưu và cách yêu cầu xóa.',
                        '查看所收集的数据、AI 服务商、保存期限和删除方式。',
                      ),
                      onTap: () => _openParentLink(
                        context,
                        config?.privacyPolicyUri,
                        context.tr('Chính sách quyền riêng tư', '隐私政策'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsActionTile(
                      key: const Key('settings-terms'),
                      icon: Icons.description_outlined,
                      title: context.tr('Điều khoản sử dụng', '使用条款'),
                      detail: context.tr(
                        'Điều khoản dành cho phụ huynh và người giám hộ.',
                        '面向家长和监护人的使用条款。',
                      ),
                      onTap: () => _openParentLink(
                        context,
                        config?.termsUri,
                        context.tr('Điều khoản sử dụng', '使用条款'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsActionTile(
                      key: const Key('settings-support'),
                      icon: Icons.support_agent_rounded,
                      title: context.tr('Hỗ trợ', '支持'),
                      detail: context.tr(
                        'Liên hệ HOMI về quyền riêng tư, dữ liệu hoặc lỗi ứng dụng.',
                        '就隐私、数据或应用问题联系 HOMI。',
                      ),
                      onTap: () => _openParentLink(
                        context,
                        config?.supportUri,
                        context.tr('Hỗ trợ', '支持'),
                      ),
                    ),
                    if (privacyConsentGranted &&
                        !voiceAccessEnabled &&
                        onRequestVoiceAccess != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _SettingsActionTile(
                        key: const Key('settings-enable-voice'),
                        icon: Icons.mic_rounded,
                        title: context.tr('Cho phép micro', '允许麦克风'),
                        detail: context.tr(
                          'Mở hộp thoại quyền hệ thống. Audio chỉ được gửi sau khi có cả chấp thuận phụ huynh và quyền micro.',
                          '打开系统权限对话框。只有家长同意并授予麦克风权限后才会发送音频。',
                        ),
                        onTap: onRequestVoiceAccess!,
                      ),
                    ],
                    if (!privacyConsentGranted &&
                        onManagePrivacyConsent != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _SettingsActionTile(
                        key: const Key('settings-manage-privacy-consent'),
                        icon: Icons.verified_user_outlined,
                        title: context.tr(
                          'Thiết lập tính năng giọng nói',
                          '设置语音功能',
                        ),
                        detail: context.tr(
                          'Quay lại màn hình dành cho phụ huynh để đọc thông tin và chọn đồng ý.',
                          '返回家长设置页面，阅读说明并选择是否同意。',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          onManagePrivacyConsent!();
                        },
                      ),
                    ],
                    if (privacyConsentGranted &&
                        onRevokePrivacyConsent != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _SettingsActionTile(
                        key: const Key('settings-revoke-privacy-consent'),
                        icon: Icons.delete_forever_outlined,
                        title: context.tr(
                          'Rút chấp thuận và xóa dữ liệu',
                          '撤回同意并删除数据',
                        ),
                        detail: context.tr(
                          'Yêu cầu backend xóa lịch sử trước, sau đó xóa nhóm tuổi cục bộ và đặt lại mã cài đặt iOS/Web.',
                          '先请求后端删除历史记录，再删除本地年龄组并重置 iOS/Web 安装标识。',
                        ),
                        onTap: () => _revokeConsent(context),
                      ),
                    ],
                    if (onStartTutorial != null) ...<Widget>[
                      const SizedBox(height: 26),
                      _SectionLabel(label: context.tr('Hỗ trợ', '帮助')),
                      const SizedBox(height: 10),
                      _SettingsActionTile(
                        key: const Key('settings-start-user-tutorial'),
                        icon: Icons.school_rounded,
                        title: context.tr('Hướng dẫn sử dụng', '使用指南'),
                        detail: context.tr(
                          'Xem lại cách giao tiếp, học từ vựng và luyện nghe theo chủ đề',
                          '重新查看对话、词汇和主题听力的使用方法',
                        ),
                        onTap: () {
                          final startTutorial = onStartTutorial!;
                          Navigator.of(context).pop();
                          Future<void>.delayed(
                            const Duration(milliseconds: 260),
                            startTutorial,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openParentLink(
    BuildContext context,
    Uri? uri,
    String label,
  ) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !context.mounted) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }

  Future<void> _revokeConsent(BuildContext context) async {
    final revoke = onRevokePrivacyConsent;
    if (revoke == null ||
        !await showParentalGate(context) ||
        !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rút chấp thuận và yêu cầu xóa dữ liệu?'),
        content: const Text(
          'HOMI sẽ gửi yêu cầu xóa history tới backend trước khi xóa chấp thuận, nhóm tuổi lưu cục bộ và mã cài đặt iOS/Web. Nếu máy chủ không xác nhận, thao tác sẽ dừng và hiển thị lỗi.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Tiếp tục xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await revoke();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chưa thể xác nhận xóa dữ liệu trên máy chủ. Chấp thuận vẫn được giữ: $error',
          ),
        ),
      );
    }
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

  Future<void> _setH20HardwareTestMode(
    BuildContext context,
    bool enabled,
  ) async {
    try {
      await controller.setH20HardwareTestMode(enabled);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleH20OfflineRecording(BuildContext context) async {
    try {
      await controller.toggleH20OfflineRecordingTest();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _playH20SpeakerTest(BuildContext context) async {
    try {
      await controller.playH20BundledSpeakerTest();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _scanAndConnectAiv0(BuildContext context) async {
    try {
      final devices = await controller.scanAiv0Devices();
      if (!context.mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không tìm thấy H20/AIV0. Hãy bật thiết bị và thử lại.',
                '未找到 H20/AIV0。请开启设备后重试。',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<Aiv0BleDevice>(
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
                  context.tr('Chọn thiết bị BLE Control', '选择 BLE 控制设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'APK sẽ xác nhận service 9E3B0001. Âm thanh không truyền qua BLE.',
                    'APK 将验证 9E3B0001 服务。音频不通过 BLE 传输。',
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
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.lavender,
                          child: Icon(
                            Icons.bluetooth_rounded,
                            color: AppColors.indigo,
                          ),
                        ),
                        title: Text(device.name),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
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
      if (selected == null || !context.mounted) return;
      await controller.connectAiv0Device(selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Đã kết nối BLE Control. MAIN Raw Hex đã sẵn sàng.',
                'BLE 控制已连接。MAIN Raw Hex 已可使用。',
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

  // Kept only for release builds that intentionally re-enable legacy
  // FF12/FF13/FF14 audio through ENABLE_LEGACY_BLE_AUDIO.
  // ignore: unused_element
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

  // ignore: unused_element
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

  Future<void> _findAndConnectHfp(BuildContext context) async {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    try {
      final devices = await controller.findHfpDevices();
      if (!context.mounted) {
        return;
      }
      if (devices.isEmpty) {
        await _showHfpMessage(
          context,
          title: controller.supportsBrowserHfp
              ? context.tr('Chưa thấy mic Bluetooth trên Web', '网页中未发现蓝牙麦克风')
              : context.tr('Chưa có thiết bị HFP', '暂无 HFP 设备'),
          message: context.tr(
            controller.supportsBrowserHfp
                ? 'Web không thể tự kết nối HFP. Hãy kết nối tai nghe trong Cài đặt Bluetooth, cho phép quyền micro, tải lại trang rồi bấm Chọn mic HFP. Safari trên iPhone có thể chỉ cung cấp mic iPhone.'
                : isIOS
                ? 'iOS chỉ cho ứng dụng chọn mic HFP đang kết nối. Hãy kết nối H20 trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.'
                : 'Hãy ghép đôi tai nghe hoặc thiết bị HFP trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.',
            controller.supportsBrowserHfp
                ? '网页无法自行连接 HFP。请先在蓝牙设置中连接耳机、允许麦克风权限、刷新页面，再点击选择 HFP 麦克风。iPhone Safari 可能只提供 iPhone 麦克风。'
                : isIOS
                ? 'iOS 只能选择当前已连接的 HFP 麦克风。请先在蓝牙设置中连接 H20，然后返回并点击“查找 HFP”。'
                : '请先在蓝牙设置中配对耳机或 HFP 设备，然后返回并点击“查找 HFP”。',
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<HfpAudioDevice>(
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
                  controller.supportsBrowserHfp
                      ? context.tr('Chọn mic Bluetooth', '选择蓝牙麦克风')
                      : context.tr('Chọn thiết bị HFP', '选择 HFP 设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    controller.supportsBrowserHfp
                        ? 'Chỉ các mic Bluetooth mà trình duyệt công bố mới xuất hiện. Thiết bị đã chọn được ưu tiên.'
                        : isIOS
                        ? 'iOS chỉ hiển thị các mic HFP đang khả dụng trong AVAudioSession. Thiết bị đang dùng được ưu tiên.'
                        : 'Android chỉ cho ứng dụng dùng HFP đã ghép đôi. Thiết bị đang kết nối được ưu tiên.',
                    controller.supportsBrowserHfp
                        ? '这里只显示浏览器公开的蓝牙麦克风；已选择的设备优先。'
                        : isIOS
                        ? 'iOS 仅显示 AVAudioSession 中可用的 HFP 麦克风；当前设备优先。'
                        : 'Android 仅允许应用使用已配对的 HFP；已连接设备优先显示。',
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
                          backgroundColor: device.isConnected
                              ? AppColors.successSoft
                              : const Color(0xFFF1F2F8),
                          child: Icon(
                            Icons.headset_mic_rounded,
                            color: device.isConnected
                                ? AppColors.success
                                : AppColors.muted,
                          ),
                        ),
                        title: Text(device.displayName),
                        subtitle: Text(
                          device.isConnected
                              ? controller.supportsBrowserHfp
                                    ? context.tr(
                                        'Mic đang được chọn cho Web',
                                        '已选为网页麦克风',
                                      )
                                    : context.tr('HFP đang kết nối', 'HFP 已连接')
                              : context.tr(
                                  controller.supportsBrowserHfp
                                      ? 'Chạm để dùng mic này'
                                      : 'Đã ghép đôi • chạm để mở kết nối',
                                  controller.supportsBrowserHfp
                                      ? '点击使用此麦克风'
                                      : '已配对 • 点击连接',
                                ),
                        ),
                        trailing: device.isConnected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                              )
                            : const Icon(Icons.chevron_right_rounded),
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
      await controller.connectHfpDevice(selected);
    } catch (error) {
      if (context.mounted) {
        await _showHfpMessage(
          context,
          title: context.tr('Chưa thể dùng HFP', '暂时无法使用 HFP'),
          message: error.toString(),
        );
      }
    }
  }

  Future<void> _showHfpMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Đã hiểu', '知道了')),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : AppColors.lavenderSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildAgeGroupSelector extends StatelessWidget {
  const _ChildAgeGroupSelector({
    required this.childAge,
    required this.enabled,
    required this.onChanged,
  });

  final int childAge;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      key: const Key('settings-child-age-group'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.child_care_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  context.tr(
                    'Chọn một lần, dùng cho mọi bài học',
                    '选择一次，适用于所有课程',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final catalog in listeningCatalogs)
                ChoiceChip(
                  key: ValueKey('settings-age-${catalog.id}'),
                  showCheckmark: true,
                  label: Text(
                    context.tr(
                      '${catalog.startAge}–${catalog.endAge} tuổi',
                      '${catalog.startAge}–${catalog.endAge} 岁',
                    ),
                  ),
                  selected:
                      childAge >= catalog.startAge &&
                      childAge <= catalog.endAge,
                  onSelected: enabled
                      ? (_) => onChanged?.call(catalog.startAge)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'Trợ lý MAIN và mục Chủ đề sẽ tự dùng nhóm tuổi này. Phụ huynh có thể đổi lại tại đây.',
              'MAIN 助手和主题课程会自动使用此年龄组。家长可在此更改。',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSelector extends StatefulWidget {
  const _AppearanceSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  State<_AppearanceSelector> createState() => _AppearanceSelectorState();
}

class _AppearanceSelectorState extends State<_AppearanceSelector> {
  late ThemeMode _value = widget.value;

  @override
  void didUpdateWidget(covariant _AppearanceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  void _select(ThemeMode mode) {
    if (mode == _value) {
      return;
    }
    setState(() => _value = mode);
    widget.onChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = <({ThemeMode mode, IconData icon, String label})>[
      (
        mode: ThemeMode.system,
        icon: Icons.brightness_auto_rounded,
        label: context.tr('Hệ thống', '跟随系统'),
      ),
      (
        mode: ThemeMode.light,
        icon: Icons.light_mode_rounded,
        label: context.tr('Sáng', '浅色'),
      ),
      (
        mode: ThemeMode.dark,
        icon: Icons.dark_mode_rounded,
        label: context.tr('Tối', '深色'),
      ),
    ];
    final selectedLabel = options
        .firstWhere((option) => option.mode == _value)
        .label;

    return Container(
      key: const Key('appearance-settings-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (MediaQuery.textScalerOf(context).scale(1) >= 1.4)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.palette_outlined, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('Giao diện', '外观'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  selectedLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Icon(Icons.palette_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('Giao diện', '外观'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  selectedLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (option) => FilterChip(
                    key: ValueKey<String>('theme-mode-${option.mode.name}'),
                    avatar: Icon(option.icon, size: 18),
                    label: Text(option.label),
                    selected: _value == option.mode,
                    showCheckmark: false,
                    onSelected: widget.onChanged == null
                        ? null
                        : (_) => _select(option.mode),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'Màu giao diện đổi ngay và được giữ cho lần mở ứng dụng sau.',
              '外观会立即切换，并在下次打开应用时保留。',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String trailing;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
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

class _Aiv0BleControlCard extends StatelessWidget {
  const _Aiv0BleControlCard({
    required this.status,
    required this.events,
    required this.mainDispatchStatus,
    required this.mainDispatchAt,
    required this.disabled,
    required this.onScan,
    required this.onDisconnect,
  });

  final Aiv0BleStatus status;
  final List<Aiv0ButtonEvent> events;
  final String mainDispatchStatus;
  final DateTime? mainDispatchAt;
  final bool disabled;
  final VoidCallback onScan;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy =
        status.phase == Aiv0BlePhase.scanning ||
        status.phase == Aiv0BlePhase.connecting ||
        status.phase == Aiv0BlePhase.reconnecting;
    final stateColor = connected
        ? AppColors.success
        : status.phase == Aiv0BlePhase.error
        ? AppColors.coral
        : AppColors.muted;
    final name = status.deviceName?.trim();
    final hasNativeDiagnostics =
        status.peripheralState != null ||
        status.mainNotificationState != null ||
        status.lastDisconnectCode != null ||
        status.lastNotificationRecovery != null ||
        status.diagnosticTimeline.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: connected
            ? Color.alphaBlend(
                AppColors.success.withValues(alpha: 0.12),
                colorScheme.surfaceContainer,
              )
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: stateColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                connected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.settings_remote_rounded,
                color: stateColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name == null || name.isEmpty
                          ? context.tr('BLE Control AIV0 V1', 'AIV0 V1 BLE 控制')
                          : name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _detail(context),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'BLE: MAIN, pin, firmware và trạng thái • Âm thanh: HFP hai chiều',
              'BLE：MAIN、电量、固件和状态 • 音频：双向 HFP',
            ),
            style: const TextStyle(
              color: AppColors.indigo,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasNativeDiagnostics) ...<Widget>[
            const SizedBox(height: 9),
            Container(
              key: const Key('aiv0-native-diagnostics'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Aiv0DiagnosticLine(
                    label: context.tr('GATT thực tế', '实际 GATT'),
                    value:
                        '${status.peripheralState ?? 'unknown'} • MAIN Notify '
                        '${status.mainNotificationState ?? 'unknown'}',
                  ),
                  if (status.lastDisconnectCode != null ||
                      status.lastDisconnectMessage != null)
                    _Aiv0DiagnosticLine(
                      label: context.tr('Mất BLE gần nhất', '最近 BLE 断开'),
                      value: <String>[
                        if (status.lastDisconnectAt != null)
                          _formatEventTime(status.lastDisconnectAt!),
                        if (status.lastDisconnectCode != null)
                          status.lastDisconnectCode!,
                        if (status.lastDisconnectMessage != null)
                          status.lastDisconnectMessage!,
                      ].join(' • '),
                    ),
                  if (status.lastNotificationRecovery != null)
                    _Aiv0DiagnosticLine(
                      label: context.tr('Khôi phục MAIN', '恢复 MAIN'),
                      value: status.lastNotificationRecovery!,
                    ),
                  _Aiv0DiagnosticLine(
                    label: context.tr('Retry đang hoãn', '延迟重试'),
                    value: '${status.deferredRecoveryRepeatCount}',
                  ),
                  if (status.diagnosticTimeline.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'Timeline BLE / HFP (tối đa 80 sự kiện gần nhất)',
                        'BLE / HFP 时间线（最近最多 80 个事件）',
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      key: const Key('aiv0-ble-hfp-timeline'),
                      constraints: const BoxConstraints(maxHeight: 360),
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest.withValues(
                          alpha: 0.76,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          status.diagnosticTimeline
                              .skip(
                                status.diagnosticTimeline.length > 80
                                    ? status.diagnosticTimeline.length - 80
                                    : 0,
                              )
                              .map(_formatTimelineEvent)
                              .join('\n'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            height: 1.45,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (connected) ...<Widget>[
            const SizedBox(height: 9),
            _Aiv0DiagnosticLine(
              label: context.tr('Pin', '电量'),
              value: status.batteryPercent == null
                  ? context.tr('Chưa đọc được', '尚未读取')
                  : '${status.batteryPercent}%',
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Firmware', '固件'),
              value:
                  status.firmwareRevision ??
                  context.tr('Chưa đọc được', '尚未读取'),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Trạng thái sạc', '充电状态'),
              value: context.tr(
                'Chưa được H20 cung cấp qua BLE',
                'H20 尚未通过 BLE 提供',
              ),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Ghi 9E3B0003', '写入 9E3B0003'),
              value: status.writeMode == 'withResponse'
                  ? 'Write with response'
                  : status.writeMode == 'withoutResponse'
                  ? context.tr(
                      'WRITE_NO_RESPONSE • chờ ODM bổ sung ACK',
                      'WRITE_NO_RESPONSE • 等待 ODM 增加 ACK',
                    )
                  : context.tr('Chưa xác định', '尚未确定'),
            ),
          ],
          if (status.deviceId != null ||
              events.isNotEmpty ||
              status.packetCount > 0) ...<Widget>[
            const SizedBox(height: 9),
            _Aiv0DiagnosticLine(
              label: context.tr('Giao thức packet', '数据包协议'),
              value: status.protocolConfirmed
                  ? context.tr('Đã xác nhận', '已确认')
                  : context.tr(
                      'MAIN Raw Hex đã điều khiển APP • chưa gửi APP State',
                      'MAIN Raw Hex 已控制 APP • 尚未发送 APP State',
                    ),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('MAIN → trợ lý', 'MAIN → 助手'),
              value: mainDispatchAt == null
                  ? mainDispatchStatus
                  : '${_formatEventTime(mainDispatchAt!)} • '
                        '$mainDispatchStatus',
            ),
            if (events.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Log MAIN / Raw Hex gần nhất',
                  '最近的 MAIN / Raw Hex 日志',
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              ...events
                  .take(5)
                  .map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SelectableText(
                        '${_formatEventTime(event.receivedAt)}  '
                        '${event.isDuplicate ? '[TRÙNG] ' : ''}${event.rawHex}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: event.isDuplicate
                              ? AppColors.coral
                              : AppColors.indigo,
                        ),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 6),
            Text(
              context.tr(
                '${status.packetCount} gói • ${status.invalidPacketCount} lỗi • ${status.duplicatePacketCount} trùng • ${status.reconnectCount} reconnect',
                '${status.packetCount} 包 • ${status.invalidPacketCount} 错误 • ${status.duplicatePacketCount} 重复 • ${status.reconnectCount} 次重连',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: disabled || status.phase == Aiv0BlePhase.disabled
                    ? null
                    : connected
                    ? () => onDisconnect()
                    : onScan,
                icon: Icon(
                  connected ? Icons.link_off_rounded : Icons.search_rounded,
                ),
                label: Text(
                  connected
                      ? context.tr('Ngắt BLE', '断开 BLE')
                      : context.tr('Quét & kết nối', '扫描并连接'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _detail(BuildContext context) {
    return switch (status.phase) {
      Aiv0BlePhase.disabled => context.tr(
        'BLE Control AIV0 chỉ hoạt động trên Android/iOS native.',
        'AIV0 BLE 控制仅适用于 Android/iOS 原生应用。',
      ),
      Aiv0BlePhase.idle => context.tr(
        'Chưa kết nối service 9E3B0001.',
        '尚未连接 9E3B0001 服务。',
      ),
      Aiv0BlePhase.scanning => context.tr(
        'Đang tìm H20/AIV0 ở gần…',
        '正在搜索附近的 H20/AIV0…',
      ),
      Aiv0BlePhase.connecting => context.tr(
        'Đang xác nhận 9E3B0001/0002/0003…',
        '正在验证 9E3B0001/0002/0003…',
      ),
      Aiv0BlePhase.connected =>
        status.message ?? context.tr('BLE Control đã kết nối.', 'BLE 控制已连接。'),
      Aiv0BlePhase.reconnecting =>
        status.message ?? context.tr('Đang tự kết nối lại…', '正在自动重连…'),
      Aiv0BlePhase.error =>
        status.message ?? context.tr('Kết nối BLE gặp lỗi.', 'BLE 连接发生错误。'),
    };
  }

  String _formatEventTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}.'
        '${value.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatTimelineEvent(Aiv0BleDiagnosticEvent event) {
    final metadata = event.metadata.entries
        .where((entry) => entry.key != 'type')
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' • ');
    return <String>[
      '${_formatEventTime(event.occurredAt)}  ${event.stage}'
          '${event.caller == null ? '' : '  @${event.caller}'}',
      if (event.code != null) '  code=${event.code}',
      if (event.message != null) '  ${event.message}',
      if (metadata.isNotEmpty) '  $metadata',
      if (event.audioRoute != null) '  route=${event.audioRoute}',
    ].join('\n');
  }
}

class _Aiv0DiagnosticLine extends StatelessWidget {
  const _Aiv0DiagnosticLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// Legacy diagnostic is hidden in AIV0 V1 and retained for an explicit
// ENABLE_LEGACY_BLE_AUDIO compatibility build only.
// ignore: unused_element
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
    final colorScheme = Theme.of(context).colorScheme;
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
        color: connected
            ? Color.alphaBlend(
                AppColors.success.withValues(alpha: 0.12),
                colorScheme.surfaceContainer,
              )
            : colorScheme.surfaceContainer,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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

class _H20OfflineHardwareTestCard extends StatelessWidget {
  const _H20OfflineHardwareTestCard({
    required this.enabled,
    required this.phase,
    required this.message,
    required this.result,
    required this.bleConnected,
    required this.mainProtocolConfirmed,
    required this.hfpStatus,
    required this.conversationBusy,
    required this.onEnabledChanged,
    required this.onRecord,
    required this.onSpeakerTest,
    required this.onPlaybackConfirmed,
  });

  final bool enabled;
  final H20HardwareTestPhase phase;
  final String? message;
  final H20HardwareTestResult? result;
  final bool bleConnected;
  final bool mainProtocolConfirmed;
  final BluetoothAudioStatus hfpStatus;
  final bool conversationBusy;
  final ValueChanged<bool> onEnabledChanged;
  final Future<void> Function() onRecord;
  final Future<void> Function() onSpeakerTest;
  final ValueChanged<bool> onPlaybackConfirmed;

  bool get _running =>
      phase == H20HardwareTestPhase.openingRoute ||
      phase == H20HardwareTestPhase.recording ||
      phase == H20HardwareTestPhase.playing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hfpConnected = hfpStatus.isConnected || hfpStatus.deviceId != null;
    final routeActive = hfpStatus.routeActive;
    final canStart = enabled && hfpConnected && !conversationBusy && !_running;
    final canToggleRecording =
        phase == H20HardwareTestPhase.recording || canStart;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              (phase == H20HardwareTestPhase.error
                      ? AppColors.coral
                      : AppColors.indigo)
                  .withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr(
                        'Kiểm tra phần cứng H20 offline',
                        'H20 离线硬件测试',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr(
                        'Chỉ ghi file trên điện thoại; không gọi backend và không tải âm thanh lên cloud.',
                        '仅在手机本地录音；不调用后端，也不上传音频到云端。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(value: enabled, onChanged: onEnabledChanged),
            ],
          ),
          _Aiv0DiagnosticLine(
            label: 'BLE',
            value: bleConnected
                ? context.tr('Đã kết nối', '已连接')
                : context.tr('Chưa kết nối', '未连接'),
          ),
          _Aiv0DiagnosticLine(
            label: 'HFP',
            value: hfpConnected
                ? context.tr('Đã kết nối', '已连接')
                : context.tr('Chưa kết nối', '未连接'),
          ),
          _Aiv0DiagnosticLine(
            label: 'SCO',
            value: routeActive
                ? context.tr('Đang hoạt động', '正在使用')
                : context.tr('Chỉ mở trong lúc kiểm tra', '仅在测试时打开'),
          ),
          _Aiv0DiagnosticLine(
            label: 'MAIN',
            value: mainProtocolConfirmed
                ? context.tr(
                    'Đã xác nhận • điều khiển ghi/dừng',
                    '已确认 • 控制开始/停止录音',
                  )
                : context.tr(
                    'Raw Hex đã bật • điều khiển ghi/dừng',
                    'Raw Hex 已启用 • 控制开始/停止录音',
                  ),
          ),
          if (message != null && message!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: phase == H20HardwareTestPhase.error
                    ? AppColors.coral
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: 6),
            _Aiv0DiagnosticLine(
              label: context.tr('Micro đã kiểm', '麦克风验证'),
              value: result!.inputRouteVerified
                  ? result!.inputDeviceName ?? 'HFP/SCO'
                  : context.tr('Chưa xác nhận', '尚未确认'),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Loa đã kiểm', '扬声器验证'),
              value: result!.outputRouteVerified
                  ? result!.outputDeviceName ?? 'HFP/SCO'
                  : context.tr('Chưa xác nhận', '尚未确认'),
            ),
            if (result!.recordedDuration != null)
              _Aiv0DiagnosticLine(
                label: context.tr('Thời lượng', '录音时长'),
                value: '${result!.recordedDuration!.inMilliseconds / 1000.0} s',
              ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Bạn có nghe âm thanh từ loa H20 không?',
                '您是否从 H20 扬声器听到声音？',
              ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => onPlaybackConfirmed(true),
                  icon: Icon(
                    Icons.check_circle_outline_rounded,
                    color: result!.playbackAudible == true
                        ? AppColors.success
                        : null,
                  ),
                  label: Text(context.tr('Có', '是')),
                ),
                TextButton.icon(
                  onPressed: () => onPlaybackConfirmed(false),
                  icon: Icon(
                    Icons.error_outline_rounded,
                    color: result!.playbackAudible == false
                        ? AppColors.coral
                        : null,
                  ),
                  label: Text(context.tr('Không', '否')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: canStart ? () => onSpeakerTest() : null,
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(context.tr('Test loa offline', '离线测试扬声器')),
              ),
              FilledButton.icon(
                onPressed: canToggleRecording ? () => onRecord() : null,
                icon: Icon(
                  phase == H20HardwareTestPhase.recording
                      ? Icons.stop_circle_outlined
                      : Icons.mic_rounded,
                ),
                label: Text(
                  phase == H20HardwareTestPhase.recording
                      ? context.tr('Dừng & phát lại', '停止并回放')
                      : context.tr('Thu thử tối đa 5 giây', '录音测试（最多 5 秒）'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HfpStatusCard extends StatelessWidget {
  const _HfpStatusCard({
    required this.status,
    required this.browserManaged,
    required this.selected,
    required this.disabled,
    required this.onFind,
    required this.onDisconnect,
  });

  final BluetoothAudioStatus status;
  final bool browserManaged;
  final bool selected;
  final bool disabled;
  final VoidCallback onFind;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy = status.isBusy;
    final stateColor = selected
        ? AppColors.success
        : status.phase == BluetoothAudioConnectionPhase.error
        ? AppColors.coral
        : connected
        ? AppColors.indigo
        : AppColors.muted;
    final deviceName = status.deviceName?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: connected
            ? Color.alphaBlend(
                AppColors.success.withValues(alpha: 0.12),
                colorScheme.surfaceContainer,
              )
            : colorScheme.surfaceContainer,
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
                child: Icon(Icons.headset_mic_rounded, color: stateColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deviceName == null || deviceName.isEmpty
                          ? context.tr('Mic Bluetooth HFP', '蓝牙 HFP 麦克风')
                          : deviceName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _detail(context, selected: selected),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connected && !browserManaged) ...<Widget>[
            const SizedBox(height: 9),
            _Aiv0DiagnosticLine(
              label: context.tr('Micro thực tế', '实际麦克风'),
              value: status.routeActive
                  ? status.inputDeviceName ??
                        context.tr('HFP/SCO (không rõ tên)', 'HFP/SCO（名称未知）')
                  : context.tr(
                      'Chưa xác nhận • đường SCO chưa mở',
                      '尚未确认 • SCO 通道未打开',
                    ),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Loa thực tế', '实际扬声器'),
              value: status.routeActive
                  ? status.outputDeviceName ??
                        context.tr('HFP/SCO (không rõ tên)', 'HFP/SCO（名称未知）')
                  : context.tr(
                      'Chưa xác nhận • đường SCO chưa mở',
                      '尚未确认 • SCO 通道未打开',
                    ),
            ),
            _Aiv0DiagnosticLine(
              label: context.tr('Đường SCO', 'SCO 通道'),
              value: status.routeActive
                  ? context.tr('Đang hoạt động', '正在使用')
                  : context.tr('Chưa mở', '未打开'),
            ),
          ],
          const SizedBox(height: 6),
          if (busy)
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
              child: TextButton.icon(
                onPressed:
                    disabled ||
                        status.phase ==
                            BluetoothAudioConnectionPhase.unsupported ||
                        status.phase == BluetoothAudioConnectionPhase.disabled
                    ? null
                    : selected
                    ? () => onDisconnect()
                    : onFind,
                icon: Icon(
                  selected
                      ? Icons.link_off_rounded
                      : Icons.manage_search_rounded,
                ),
                label: Text(
                  selected
                      ? context.tr('Dùng mic điện thoại', '使用手机麦克风')
                      : connected && !browserManaged
                      ? context.tr('Dùng mic này', '使用此麦克风')
                      : browserManaged
                      ? context.tr('Chọn mic HFP', '选择 HFP 麦克风')
                      : context.tr('Tìm HFP', '查找 HFP'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _detail(BuildContext context, {required bool selected}) {
    if (browserManaged) {
      return switch (status.phase) {
        BluetoothAudioConnectionPhase.disabled => context.tr(
          'HFP Web đang tắt trong cấu hình bản build.',
          '此构建中已关闭网页 HFP。',
        ),
        BluetoothAudioConnectionPhase.unsupported => context.tr(
          'Trình duyệt này không hỗ trợ chọn mic Bluetooth.',
          '此浏览器不支持选择蓝牙麦克风。',
        ),
        BluetoothAudioConnectionPhase.permissionRequired => context.tr(
          'Cần cho phép quyền micro của trình duyệt.',
          '需要允许浏览器使用麦克风。',
        ),
        BluetoothAudioConnectionPhase.scanning => context.tr(
          'Đang kiểm tra các mic mà trình duyệt cung cấp…',
          '正在检查浏览器提供的麦克风…',
        ),
        BluetoothAudioConnectionPhase.connecting => context.tr(
          'Đang chọn mic Bluetooth…',
          '正在选择蓝牙麦克风…',
        ),
        BluetoothAudioConnectionPhase.discovering => context.tr(
          'Đang kiểm tra đường âm thanh của trình duyệt…',
          '正在检查浏览器音频通道…',
        ),
        BluetoothAudioConnectionPhase.ready => context.tr(
          'Đã chọn • sẵn sàng ghi âm qua Web',
          '已选择 • 可通过网页录音',
        ),
        BluetoothAudioConnectionPhase.recording => context.tr(
          'Đang ghi âm từ mic Bluetooth trên Web',
          '正在通过网页蓝牙麦克风录音',
        ),
        BluetoothAudioConnectionPhase.error =>
          status.message ??
              context.tr('Không thể dùng mic Bluetooth.', '无法使用蓝牙麦克风。'),
        BluetoothAudioConnectionPhase.idle => context.tr(
          'Kết nối tai nghe trong hệ thống rồi chọn mic tại đây.',
          '请先在系统中连接耳机，再在此选择麦克风。',
        ),
      };
    }
    return switch (status.phase) {
      BluetoothAudioConnectionPhase.disabled => context.tr(
        'HFP đang tắt trong cấu hình bản build.',
        '此构建中已关闭 HFP。',
      ),
      BluetoothAudioConnectionPhase.unsupported => context.tr(
        'Điện thoại hoặc bản ứng dụng này không hỗ trợ HFP.',
        '此手机或应用版本不支持 HFP。',
      ),
      BluetoothAudioConnectionPhase.permissionRequired => context.tr(
        'Cần quyền Thiết bị ở gần/Bluetooth.',
        '需要“附近设备/蓝牙”权限。',
      ),
      BluetoothAudioConnectionPhase.scanning => context.tr(
        'Đang tìm thiết bị HFP đã ghép đôi…',
        '正在查找已配对的 HFP 设备…',
      ),
      BluetoothAudioConnectionPhase.connecting => context.tr(
        'Đang kiểm tra kết nối HFP…',
        '正在检查 HFP 连接…',
      ),
      BluetoothAudioConnectionPhase.discovering => context.tr(
        'Đang kiểm tra đường âm thanh SCO…',
        '正在检查 SCO 音频通道…',
      ),
      BluetoothAudioConnectionPhase.ready => context.tr(
        selected
            ? 'Nguồn đang chọn • H20 qua HFP/SCO'
            : 'Đã kết nối • bấm “Dùng mic này” để chọn',
        selected ? '当前音源 • H20 通过 HFP/SCO' : '已连接 • 点击“使用此麦克风”',
      ),
      BluetoothAudioConnectionPhase.recording => context.tr(
        'Đang nhận diện từ mic HFP/SCO',
        '正在通过 HFP/SCO 麦克风识别',
      ),
      BluetoothAudioConnectionPhase.error =>
        status.message ?? context.tr('Kết nối HFP gặp lỗi.', 'HFP 连接发生错误。'),
      BluetoothAudioConnectionPhase.idle => context.tr(
        'Kết nối HFP trong Cài đặt hệ thống, rồi chọn mic tại đây.',
        '请先在系统设置中连接 HFP，再在此选择麦克风。',
      ),
    };
  }
}
