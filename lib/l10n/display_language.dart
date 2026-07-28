import 'package:flutter/material.dart';

import 'display_language_persistence.dart';

enum DisplayLanguage {
  vietnamese('vi', 'Tiếng Việt', 'Tiếng Việt'),
  simplifiedChinese('zh-Hans', 'Tiếng Trung giản thể', '简体中文');

  const DisplayLanguage(this.code, this.vietnameseLabel, this.nativeLabel);

  final String code;
  final String vietnameseLabel;
  final String nativeLabel;

  String choose(String vietnamese, String simplifiedChinese) =>
      this == DisplayLanguage.simplifiedChinese
      ? simplifiedChinese
      : vietnamese;

  String translateKnown(String value) {
    if (this == DisplayLanguage.vietnamese) {
      return value;
    }
    if (value.startsWith('Đang học ')) {
      return value.replaceFirst('Đang học ', '学习中 ');
    }
    if (value.startsWith('Ứng dụng đang ghi nhớ câu này ')) {
      return value.replaceFirst('Ứng dụng đang ghi nhớ câu này ', '应用正在记住这句话 ');
    }
    return _simplifiedChinese[value] ?? value;
  }
}

class DisplayLanguageStore {
  const DisplayLanguageStore();

  Future<DisplayLanguage> read() async {
    try {
      final code = (await readDisplayLanguageCode())?.trim();
      return DisplayLanguage.values.firstWhere(
        (language) => language.code == code,
        orElse: () => DisplayLanguage.vietnamese,
      );
    } catch (_) {
      return DisplayLanguage.vietnamese;
    }
  }

  Future<void> write(DisplayLanguage language) =>
      writeDisplayLanguageCode(language.code);
}

class DisplayLanguageScope extends InheritedWidget {
  const DisplayLanguageScope({
    required this.language,
    required super.child,
    super.key,
  });

  final DisplayLanguage language;

  static DisplayLanguage of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DisplayLanguageScope>()
          ?.language ??
      DisplayLanguage.vietnamese;

  @override
  bool updateShouldNotify(DisplayLanguageScope oldWidget) =>
      language != oldWidget.language;
}

extension DisplayLanguageBuildContext on BuildContext {
  DisplayLanguage get displayLanguage => DisplayLanguageScope.of(this);

  String tr(String vietnamese, String simplifiedChinese) =>
      displayLanguage.choose(vietnamese, simplifiedChinese);

  String trKnown(String value) => displayLanguage.translateKnown(value);
}

const Map<String, String> _simplifiedChinese = <String, String>{
  'Ở nhà': '在家',
  'Ở trường': '在学校',
  'Ra ngoài': '外出',
  'Android streaming': 'Android 流式识别',
  'OpenAI Realtime': 'OpenAI 实时识别',
  'BLE offline intent': 'BLE 离线意图',
  'Batch Chunks dự phòng': '分块批处理备用',
  'BLE streaming': 'BLE 流式识别',
  'ASR Android trực tiếp': 'Android 实时识别',
  'Mic điện thoại': '手机麦克风',
  'Mic INNOTRIK': 'INNOTRIK 麦克风',
  'Tất cả': '全部',
  'Đúng ý': '符合原意',
  'Sai ý': '不符合原意',
  'Chưa đánh giá': '未评价',
  'Hôm nay': '今天',
  'Hôm qua': '昨天',
  'Rule': '规则',
  'AI': 'AI',
  'Cache': '缓存',
  'Không rõ nguồn': '来源未知',
  'ASR trực tiếp': '实时识别',
  'BLE offline': 'BLE 离线',
  'Batch ASR': '批量识别',
  'BLE ASR': 'BLE 识别',
  'ASR cũ': '旧版识别',
  'Đã tối ưu': '已优化',
  'Đang học': '学习中',
  'Không học': '不学习',
  'Cần kiểm tra': '需要检查',
  'Chưa tối ưu': '未优化',
  'Nguồn âm thanh hiện chưa sẵn sàng.': '当前音频输入尚未就绪。',
  'Android streaming chưa sẵn sàng; đã chuyển sang OpenAI Realtime.':
      'Android 流式识别不可用，已切换到 OpenAI 实时识别。',
  'ASR offline BLE chưa có mô hình native; đang dùng OpenAI Realtime.':
      'BLE 离线识别尚无原生模型，正在使用 OpenAI 实时识别。',
  'BLE offline fast path đang nghe; câu lạ sẽ tự chuyển Realtime.':
      'BLE 离线快速路径正在聆听；陌生句子将自动切换到实时识别。',
  'ASR offline BLE chưa sẵn sàng; đang dùng OpenAI Realtime.':
      'BLE 离线识别尚未就绪，正在使用 OpenAI 实时识别。',
  'Câu chưa đủ chắc chắn; đã chuyển sớm sang OpenAI Realtime.':
      '句子置信度不足，已提前切换到 OpenAI 实时识别。',
  'Realtime chưa sẵn sàng; sẽ dùng Batch Chunks khi dừng.':
      '实时识别尚未就绪，停止后将使用分块批处理。',
  'OpenAI Realtime chưa khả dụng; đang dùng Batch Chunks dự phòng.':
      'OpenAI 实时识别不可用，正在使用分块批处理备用。',
  'OpenAI Realtime chưa sẵn sàng; đang dùng Batch Chunks dự phòng.':
      'OpenAI 实时识别尚未就绪，正在使用分块批处理备用。',
  'Batch Chunks chưa sẵn sàng; đang dùng upload file dự phòng.':
      '分块批处理尚未就绪，正在使用文件上传备用。',
  'Hãy nói lâu hơn một chút nhé.': '请再多说一会儿。',
  'Chưa nghe thấy giọng nói nên chưa gửi lên OpenAI.': '未检测到语音，因此没有发送到 OpenAI。',
  'Realtime chưa kết nối; âm thanh vẫn được giữ để dùng Batch Chunks.':
      '实时连接尚未建立，音频已保留用于分块批处理。',
  'Realtime không ổn định; đã chuyển sang gửi WAV dự phòng.':
      '实时连接不稳定，已切换到 WAV 备用上传。',
  'Realtime không ổn định; đã chuyển sang Batch Chunks dự phòng.':
      '实时连接不稳定，已切换到分块批处理。',
  'Realtime chưa kết nối kịp; đã chuyển sang Batch Chunks dự phòng.':
      '实时连接未及时建立，已切换到分块批处理。',
  'Mạng chunk không ổn định; đã chuyển sang gửi file WAV dự phòng.':
      '分块上传不稳定，已切换到 WAV 文件备用上传。',
  'Bản demo không tải âm thanh. Phiên bản đầy đủ sẽ phát câu tiếng Anh tại đây.':
      '演示模式不加载音频；完整版本会在这里播放英语句子。',
  'Đã ghi nhận: đúng ý.': '已记录：符合原意。',
  'Đã ghi nhận để cải thiện câu trả lời.': '已记录，用于改进回答。',
  'Câu này đã có rule nên không cần học lại.': '这句话已有规则，无需重复学习。',
  'Câu này không đủ điều kiện để học thành rule.': '这句话不符合学习为规则的条件。',
  'Câu này đã được ứng dụng học trước đó.': '应用之前已经学习过这句话。',
  'Câu này trùng ý định nhưng khác bản dịch nên chưa tự ghi đè rule.':
      '这句话与已有意图相同，但译文不同，因此不会自动覆盖规则。',
  'Ứng dụng đã học câu này để phản hồi nhanh hơn lần sau.':
      '应用已学习这句话，以便下次更快响应。',
  'Đã ghi nhận Sai ý. Đây là rule có sẵn nên cần quản trị viên kiểm tra lại.':
      '已记录“不符合原意”。这是现有规则，需要管理员复核。',
  'Đã ghi nhận Sai ý và bỏ câu này khỏi phần học tự động.':
      '已记录“不符合原意”，并将这句话从自动学习中移除。',
  'Đã ghi nhận Sai ý; câu này sẽ không được tự học.': '已记录“不符合原意”；这句话不会被自动学习。',
  'Câu này được lặp lại nhiều lần và đang chờ admin xác nhận trước khi học thành rule.':
      '这句话已重复多次，正在等待管理员确认后再学习为规则。',
  'Kết nối backend quá chậm. Vui lòng thử lại.': '服务连接过慢，请重试。',
  'Dữ liệu xem trước không hợp lệ.': '预览数据无效。',
  'Thiếu conversationId.': '缺少会话编号。',
  'Không tìm thấy lượt nói.': '未找到该次对话。',
  'Nội dung phát âm không hợp lệ.': '语音内容无效。',
  'Backend chưa được cấu hình dịch vụ phát âm.': '语音服务尚未配置。',
  'Dịch vụ phát âm phản hồi quá chậm.': '语音服务响应过慢。',
  'Không thể truyền luồng âm thanh.': '无法传输音频流。',
  'BLE streaming sẽ bật sau khi hoàn tất native Opus decoder.':
      '完成原生 Opus 解码器后即可启用 BLE 流式识别。',
  'Đang quét thiết bị INNOTRIK ở gần…': '正在扫描附近的 INNOTRIK 设备…',
  'Không tìm thấy INNOTRIK. Hãy bật thiết bị và đặt gần điện thoại.':
      '未找到 INNOTRIK。请打开设备并放在手机附近。',
  'Đã kết nối Mic INNOTRIK. BLE streaming đã sẵn sàng để thử.':
      'INNOTRIK 麦克风已连接，BLE 流式识别可以测试。',
  'Đã ngắt Mic INNOTRIK; ứng dụng sẽ dùng mic điện thoại.':
      'INNOTRIK 麦克风已断开，应用将使用手机麦克风。',
  'Hãy quét và kết nối Mic INNOTRIK trước khi chọn BLE streaming.':
      '选择 BLE 流式识别前，请先扫描并连接 INNOTRIK 麦克风。',
  'Batch Chunks chỉ chạy tự động khi OpenAI Realtime gặp lỗi.':
      '仅当 OpenAI 实时识别失败时才会自动使用分块批处理。',
  'Android streaming không khả dụng trên nền tảng này.': '此平台不支持 Android 流式识别。',
};
