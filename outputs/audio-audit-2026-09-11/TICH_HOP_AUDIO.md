# Audio HOMI đã tích hợp vào ứng dụng

Ngày: 11/09/2026. Nguồn: `D:/Code/HuaMei/App_noi/Tao_audio_11th9`.

Sau phản hồi audio mới chưa phát trên Android chạy từ Flutter, đã sửa ưu tiên MP3 khi truyền dịch vụ TTS nền tảng, khôi phục sau lỗi đọc chỉ mục và bổ sung log chẩn đoán. Xem [KIEM_TRA_AUDIO_ANDROID.md](KIEM_TRA_AUDIO_ANDROID.md). Emulator ban đầu đang cài bản ngày 10/09 thiếu toàn bộ bộ audio mới; đã cập nhật và xác nhận cả bản debug mới lẫn bản release do Flutter cài tiếp có đủ 4.916 MP3. Chưa xác nhận đầu ra loa/thiết bị thật.

Lượt chạy debug tiếp theo đã xác nhận thêm lỗi dọn cache `just_audio_cache` khiến MP3 rơi về TTS. Đã sửa và chạy lại: runtime trên emulator ghi nhận 9 yêu cầu MP3, 0 lỗi phát MP3 và các sự kiện giải mã MP3 native. Chi tiết trong báo cáo Android liên kết ở trên.

## Kết quả

Đã đưa 4.916 MP3 vào `assets/audio/homi_v4/`, tổng cộng 189.673.805 byte (khoảng 190 MB). Năm file SFX trùng giữa các gói được dùng chung. Audio đi kèm ứng dụng và không phụ thuộc đường dẫn ổ D: trên máy phát triển.

| Nhóm | Số file | Cách dùng |
|---|---:|---|
| Cue hệ thống | 387 | Điều hướng, giới thiệu, học tiếp, mời nói và chuyển bước |
| Feedback | 53 | Chọn đúng nhóm tuổi và trạng thái; luân phiên biến thể |
| Hook | 97 | Phát bản đã ghép SFX trong phần giới thiệu bài |
| Core | 1.200 | 600 câu tiếng Anh và tiếng Việt |
| Challenge | 2.616 | 872 câu hỏi, mỗi câu có prompt và hai lựa chọn |
| Mission | 540 | 180 câu hỏi, mỗi câu có prompt và hai lựa chọn |
| SFX riêng | 23 | Đóng gói tài nguyên; Hook/prompt đã ghép hiệu ứng không phát lặp thêm |

Mã tra cứu dùng ID khi có ID câu hỏi/target và đối chiếu nội dung để tránh phát nhầm câu. Câu hệ thống và đáp án dùng lại audio phù hợp theo nội dung. Role-play dùng lại câu Core trùng nội dung; phần tình huống/hướng dẫn mở đầu được đọc trước hội thoại. Năm bài hát vẫn dùng nguồn audio đã có.

Luồng Core giữ thứ tự EN → nghỉ 2 giây → VI → mời nói → mở mic. Audio chạy ở tốc độ 1.0 vì file nguồn đã được xử lý tốc độ. Challenge và Mission chờ phát xong prompt trước khi mở mic; dừng/chuyển màn hình hủy cả những đoạn lời nhắc đang chờ.

Nếu không có file phù hợp hoặc phát file lỗi, ứng dụng chuyển sang TTS theo văn bản hiện tại. TTS vẫn cần cho 12 Hook Topic 1, câu “Taxi.” (EN/VI), một số cue chứa tên bài/số sao và phần milestone chưa có bản thu riêng. Bộ nguồn cũng thiếu SFX STAR và CLOCK_CHIME_SINGLE; chưa bổ sung hiệu ứng thay thế.

## Các điểm tích hợp chính

- `assets/data/homi_audio_index.json`: chỉ mục audio, 112 chuỗi lời nhắc và danh sách Hook/Core chưa có file.
- `assets/data/listening_lessons.json`: gắn URI asset cho 600 cặp Core EN/VI.
- `assets/data/listening_audio_manifest_v4.json`: cập nhật các audio ID đã có file tương ứng.
- `lib/features/listening/application/homi_audio_library.dart`: tra ID, nội dung, chuỗi giới thiệu và feedback theo tuổi.
- `lib/features/listening/application/recorded_lesson_voice_prompt_service.dart`: phát MP3, chờ hoàn tất, hủy phát và TTS dự phòng.
- Các màn hình Intro, Practice, Challenge, Mission, Song, Topic và Voice Navigation đã nối dịch vụ mới; dịch vụ giọng nói được tiêm riêng vẫn được tôn trọng.
- `pubspec.yaml`: khai báo chỉ mục và các thư mục audio.
- `tool/import_homi_audio.mjs`: nhập lại bộ nguồn có kiểm tra ID/nội dung trước khi ghi dữ liệu.

Chạy importer từ thư mục gốc repository:

```powershell
node tool/import_homi_audio.mjs 'D:/Code/HuaMei/App_noi/Tao_audio_11th9'
```

## Kiểm tra

- Dart/Flutter analyze cho mã nguồn và hai file test mới: không phát hiện vấn đề.
- 266 test Listening và Voice Navigation đạt trong lượt cuối, loại trừ đúng bảy test đã xác minh cũng lỗi trên mã HEAD trước thay đổi.
- Bảy lỗi có sẵn gồm sáu test ảnh giao diện và một test bài hát bị timeout; không cập nhật golden hoặc sửa các luồng ngoài phạm vi để che lỗi.
- Test mới kiểm tra đủ 4.916 asset trong Flutter bundle; ánh xạ Core; chuỗi Hook; feedback; TTS khi thiếu/hỏng file; hủy lời nhắc; và Challenge/Mission chỉ mở mic sau prompt dài hơn 10 giây.
- Android APK debug build thành công tại `build/app/outputs/flutter-apk/app-debug.apk`. Sau lượt sửa Android, bản debug hiện tại có dung lượng 486.763.374 byte (khoảng 487 MB). Đây là bản debug để kiểm tra, chưa phải bản phát hành tối ưu dung lượng.
- Đã đọc nội dung APK: đủ 4.916 MP3 và chỉ mục audio, tổng byte audio khớp 189.673.805; không có file thiếu, rỗng hoặc lệch kích thước. Chi tiết trong `apk-audio-verification.json`.
- Bằng chứng: `integration-analyze-final.log`, `integration-final-tests.log`, `baseline-tests.log`, `integration-build-android.log` và `apk-audio-verification.json` trong cùng thư mục.

Chưa nghe thử hoặc kiểm tra Bluetooth/microphone trên điện thoại thật. Dung lượng audio bổ sung khoảng 190 MB làm tăng kích thước gói cài đặt.
