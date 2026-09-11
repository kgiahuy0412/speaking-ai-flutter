# Kiểm tra audio mới trên Android chạy từ Flutter

Bộ MP3 mới được lưu ở `assets/audio/homi_v4/`, không ghi đè các file audio cũ. Mã luồng học theo chủ đề V4 đã được nối để ưu tiên bộ này. Việc APK có đủ file không tự chứng minh điện thoại đã phát được file đó.

## Lỗi phát được xác nhận khi chạy debug

Trong lượt build/chạy bằng Flutter debug theo yêu cầu tiếp theo, log emulator ghi `MP3_ERROR` cho Core, feedback và cue: `PathNotFoundException` khi liệt kê `/data/user/0/com.innotrik.aispeaking/cache/just_audio_cache/`. Vì vậy việc cập nhật APK có đủ asset mới chưa xử lý hết vấn đề phát audio.

Nguyên nhân: `AudioPlayer.clearAssetCache()` của just_audio 0.10.6 liệt kê thư mục trước khi thư mục được tạo. Ứng dụng chờ Future này trước `setAsset` và dùng lại Future đã lỗi cho các file sau, khiến MP3 liên tục rơi về TTS.

Đã sửa `lib/core/audio/audio_playback_service.dart`: dọn cache là thao tác phụ; nếu không dọn được, vẫn cho `setAsset` nạp MP3 từ bundle. Cache cũ vẫn được dọn khi tồn tại. Thêm test tái hiện lỗi thật bằng thư mục tạm, kiểm tra cache cũ được xóa và bản ghi ngoài cache không bị ảnh hưởng. Tổng 22 test audio/cache/completion liên quan đạt. Bằng chứng: `just-audio-cache-fix-tests.log`, log trước sửa `flutter-android-studio-run.log`, log phiên mới `flutter-android-studio-run-fixed.log`.

Đã build, cài và chạy lại bản debug sau sửa lúc 10:36:45 ngày 11/09 trên Pixel 8 (`emulator-5554`), PID 7993. Kiểm tra runtime ghi nhận 9 yêu cầu MP3, 0 `MP3_ERROR`, 113 dòng sự kiện bộ giải mã MP3 native và 8 file MP3 mới đã được trích xuất trong cache. Core, Challenge, cue hệ thống và feedback đều xuất hiện trong các file thực tế. Bằng chứng: `just-audio-cache-fixed-runtime.log` và `just-audio-cache-fixed-runtime-verification.json`. Đây là xác nhận nạp/giải mã trên emulator; chưa đo hoặc nghe đầu ra loa/Bluetooth của điện thoại thật.

## Kết quả kiểm tra emulator

- Khi `emulator-5554` kết nối, package `com.innotrik.aispeaking` có `lastUpdateTime=2026-09-10 21:19:46`, không có `homi_audio_index.json` và có 0 MP3 dưới `homi_v4`. Đây là bằng chứng bản cũ chưa chứa bộ audio mới.
- Đã cài APK debug mới bằng `adb install -r` thành công lúc 10:10:01 ngày 11/09, giữ dữ liệu ứng dụng. Kiểm tra gói đã cài: đủ 4.916 MP3 và chỉ mục.
- Phiên Flutter Run của người dùng chạy với `--release` và cài tiếp lúc 10:10:39. Đã kiểm tra lại APK release đang cài: vẫn đủ 4.916 MP3 và chỉ mục. Log `[HOMI_AUDIO]` chỉ có trong debug, không xuất hiện ở release.
- Đã mở ứng dụng vào luồng Chủ đề và bài Bảng chữ cái. Chưa xác nhận âm thanh thực tế ở loa hoặc Bluetooth; không coi việc đóng gói hay thao tác nút là bằng chứng nghe thành công.
- Sau sửa: 66 test liên quan đạt; sau điều chỉnh cache AssetBundle cuối cùng, 14 test audio chạy lại đạt. Phân tích mã không báo lỗi, APK debug build thành công.

## Điểm sửa sau phản hồi

1. Dịch vụ TTS mặc định của Android được truyền từ màn hình cha nay được dùng làm dự phòng của bộ phát MP3, thay vì trở thành dịch vụ ghi đè toàn bộ đầu ra. Các dịch vụ tùy biến được tiêm riêng vẫn được tôn trọng.
2. Khi chỉ mục audio đọc lỗi, lần gọi sau được đọc lại. Tắt cache chuỗi của AssetBundle vì Flutter có thể giữ cả Future đọc lỗi; thư viện vẫn cache chỉ mục đã đọc thành công.
3. Console debug ghi rõ ID và đường dẫn MP3 được chọn, lỗi đọc/phát, và lý do chuyển sang TTS. Không ghi nội dung thu âm hoặc thông tin nhận dạng trẻ.

Đã kiểm tra hồi quy với dịch vụ TTS nền tảng được truyền từ bên ngoài và AssetBundle đọc lỗi lần đầu. Kiểm tra tự động và đối chiếu gói cài trong emulator đã hoàn tất; kiểm tra nghe trên thiết bị thật vẫn còn.

## Thử lại

1. Mở đúng repository `D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter`.
2. Stop phiên Flutter rồi Run lại hoàn toàn với cấu hình đang sử dụng. Các dịch vụ và dữ liệu được tạo/cache từ đầu phiên; hot reload có thể giữ các đối tượng cũ.
3. Vào luồng học theo chủ đề, nhóm 3–5 tuổi, bài `A to I Letters`, nghe Core `A. Apple.`. Câu này có MP3 mới; phần giới thiệu Topic 1 có những đoạn thiếu bản thu nên vẫn dùng TTS.
4. Khi cần chẩn đoán, chạy debug (không dùng `--release`) và lọc Debug Console bằng `[HOMI_AUDIO]`.

Ví dụ chọn đúng file mới:

```text
[HOMI_AUDIO] MP3 id=C35-L1-T01-B01-T01_EN asset=/assets/audio/homi_v4/core/C35-L1-T01-B01-T01_EN.mp3
```

`MP3` xác nhận lựa chọn và bắt đầu yêu cầu phát, không phải bằng chứng đã nghe được trên loa. Nếu tiếp theo có `MP3_ERROR`, kiểm tra lỗi phát/route. `INDEX_ERROR` là lỗi đọc chỉ mục. `TTS reason=no_matching_clip` là không tìm được bản thu khớp câu hiện tại; `index_unavailable` hoặc `playback_error` cho biết lỗi phải xử lý. Không xuất hiện log mới thì cần kiểm tra lại phiên chạy, repository hoặc luồng/màn hình đang thử.

Các log kiểm tra sau sửa được lưu cùng thư mục với tên `android-audio-fix-*`.
