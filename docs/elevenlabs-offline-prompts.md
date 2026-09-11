# Giọng tiếng Việt tạo sẵn bằng ElevenLabs

Ngày tạo: 11/09/2026. Voice: `nbv4fVbfyLxvuHzyIeDo`.
Model: `eleven_flash_v2_5`, ngôn ngữ `vi`, MP3 44.1 kHz / 128 kbps.

## Phạm vi đã thống nhất

Thay các câu đang dùng giọng thiết bị trong MAIN, hướng dẫn học, phản hồi,
luyện từ vựng và các tình huống cố định. Giữ nguyên 4.916 audio của bộ HOMI
bài học hiện có, bao gồm tiếng Anh, tiếng Việt, nhạc và hiệu ứng.

- Rà AST toàn bộ `lib/`: 2.297 biểu thức chuỗi tiếng Việt.
- Chọn các hàm/hằng phát lời nói; bỏ nhãn giao diện và câu đầu vào nhận diện.
- Đối chiếu thêm dữ liệu curriculum, kịch bản MAIN/fallback và audio index.
- Tạo **700 file riêng biệt**, tương ứng **41.758 ký tự văn bản nguồn**.
- Tổng kích thước **52.424.195 byte**, khoảng **50 MiB**.
- 700/700 file khớp checksum và có cấu trúc MP3 hoàn chỉnh.
- Tổng trường `character-cost` từ các response ElevenLabs: **11.478**.
  Đây là số dịch vụ báo cho các request, không phải suy đoán từ độ dài văn bản.

Chi phí ElevenLabs chỉ phát sinh trong quá trình tạo file. App phát lại asset
offline và không chứa API key hoặc gọi ElevenLabs lúc người dùng sử dụng.

## Tích hợp

`BundledVoicePromptLibrary` tìm audio theo nội dung tiếng Việt chính xác, chỉ
chuẩn hóa khoảng trắng. Ưu tiên tái sử dụng bản thu system/core đã có, sau đó
dùng `assets/data/elevenlabs_prompt_index.json`. Không tra hook/SFX theo text
để tránh đưa hiệu ứng của tình huống này vào câu nói của tình huống khác.

Native `MethodChannelVoicePromptService` gửi `assetPath` cùng câu nói và
lựa chọn đầu ra hiện có. Android dùng `MediaPlayer` trên route communication;
iOS dùng `AVAudioPlayer` với cùng bộ quản lý `AVAudioSession`/H20/MAIN.
`speakAndWait` chỉ hoàn tất khi audio kết thúc. Stop, chuyển câu và dispose
hủy cả việc tra index đang chờ. Nếu thiếu/hỏng audio, native đọc lại bằng
TTS thiết bị. File MP3 không bị tăng tốc hoặc áp thêm mức boost +8 dB của TTS.

Các bài học vẫn đi qua `RecordedLessonVoicePromptService`. Khi không có clip
bài học phù hợp, fallback native tự tra bộ 700 câu mới trước khi dùng TTS.

## Nội dung tiếp tục dùng TTS

- Văn bản do phụ huynh thêm, bản dịch/câu trả lời sinh ra lúc chạy.
- Câu có tổng số Ngôi sao của người dùng (`VocabularyFlowV3.starScopeChoice`
  và `starSmallIntro`), vì số lượng không có giới hạn cố định trong code.
- Câu tiếng Anh thiếu bản thu: voice lần này chỉ dành cho tiếng Việt.
- Nội dung mới chưa có trong bộ asset hoặc file phát lỗi.

Các biến thể theo bài/chủ đề/Level được mở rộng theo curriculum đang đóng gói.
Template nhập bài V2 không được tạo hàng loạt khi toàn bộ curriculum hiện tại
đã dùng V4. Khi cập nhật curriculum hoặc mở lại luồng V2, cần chạy lại audit.

## Kiểm tra và cập nhật bộ audio

Danh sách văn bản/vị trí nguồn: `outputs/elevenlabs-voice-pack/generation-plan.json`.
Kết quả rà soát: `outputs/elevenlabs-voice-pack/audit-report.json`.
Lịch sử tạo, request ID, checksum: `outputs/elevenlabs-voice-pack/generation-state.json`.
Kết quả kiểm tra file: `outputs/elevenlabs-voice-pack/audio-validation.json`.

Từ `tool/voice_audit`, chạy `dart pub get --offline`, rồi
`dart run bin/audit.dart ../..`. Công cụ phân tích dùng package riêng và không
thêm analyzer vào dependencies của ứng dụng.

Từ thư mục gốc dự án:

```powershell
node tool/plan_elevenlabs_prompts.mjs
node tool/generate_elevenlabs_prompts.mjs --key-file C:/Users/DELL/Documents/api_key_elevanlabs.txt
node tool/verify_elevenlabs_prompts.mjs
```

Generator xác thực checksum và dùng lại mọi file hoàn tất. Request lỗi hoặc
mất kết nối được ghi vào state và không tự gửi lại để tránh tính phí trùng.
Chỉ dùng `--retry-failed` sau khi đối chiếu request lỗi với ElevenLabs.
Không thay voice/model/settings trong cùng một state; tạo phiên bản bộ mới.

## Kiểm thử

Các test Flutter kiểm tra bundle, tra đúng câu/ngôn ngữ, giữ bản thu cũ,
chờ native phát xong, stop trong khi đọc index, thiếu pack và luồng MAIN.
Bộ regression gồm voice prompt, HOMI recorded audio và MAIN: 63 test qua.
Phân tích tĩnh phần Dart thay đổi: không có lỗi/cảnh báo.

Android đã biên dịch thành công bản debug và APK release ARM64 với cấu hình
`output/apk/install-production-defines.json` hiện có. APK bàn giao tại
`outputs/elevenlabs-voice-pack/HOMI-elevenlabs-vi-arm64.apk` (372.413.354 byte).
Đã mở APK kiểm tra đủ 700 MP3 và đối chiếu checksum từng file với state.
SHA-256 APK: `EDBC4BA3D65C6532B1D35370B4ECF9EC42C7E0DC05670F598394EEFCE4E85C78`.

iOS đã tích hợp mã nguồn nhưng máy Windows hiện tại không có Xcode để build
hoặc kiểm thử iPhone. Chưa kiểm thử phát âm thanh trên thiết bị thật. Cần thử
thực tế phát/dừng/chuyển sang micro với loa điện thoại và H20 trên cả hai
nền tảng, đặc biệt khi Bluetooth mất kết nối hoặc app chuyển nền.
