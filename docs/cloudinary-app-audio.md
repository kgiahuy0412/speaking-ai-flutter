# Audio ứng dụng trên Cloudinary

Ngày chuyển đổi: 11/09/2026. Cloud Name: `ysc2jlrt`.

Toàn bộ 5.833 MP3 trong `assets/audio` được đưa lên Cloudinary, tổng
255.767.977 byte (khoảng 244 MiB). Mỗi URL là HTTPS, có version và public ID
chứa hash nội dung. Công cụ tải lại từng file từ URL và so sánh SHA-256 với
bản gốc trước khi cập nhật dữ liệu ứng dụng.

## Dữ liệu và bộ cài

- `assets/data/cloudinary_audio_manifest.json`: ánh xạ đầy đủ từ đường dẫn
  audio gốc sang URL, dung lượng, SHA-256, public ID và version.
- Hai index HOMI/ElevenLabs giữ `asset` làm định danh nguồn, thêm `audioUrl`
  để phát. Trường `asset` không có nghĩa file vẫn được đóng gói trong app.
- Các trường URL trong `listening_lessons.json` và
  `listening_audio_manifest_v4.json` được đổi sang URL Cloudinary tương ứng.
- `pubspec.yaml` chỉ đóng gói JSON; không đóng gói các thư mục MP3.
  File MP3 gốc vẫn giữ trong repository để phục hồi, kiểm tra và cập nhật.
- Các audio chưa có bản thu từ trước vẫn giữ trạng thái thiếu và luồng TTS
  dự phòng; quá trình chuyển đổi không tự tạo thêm nội dung.

## Phát audio

Bài học và nhạc dùng `JustAudioPlaybackService`, ưu tiên file đã tải trong
`DeviceAudioCache`, nếu thiếu thì phát URL và lưu nền. Các câu trợ lý native
tải hoàn chỉnh bằng cùng cơ chế cache rồi truyền `filePath` cho
`VoicePromptBridge`. Android giữ MediaPlayer/communication route, iOS giữ
AVAudioPlayer/AVAudioSession và H20. Cơ chế chờ audio kết thúc trước khi mở
micro vẫn được giữ. Hủy lời thoại cũng hủy quyền phát của lượt đang tải.

Web tra cùng index và phát URL bằng HTMLAudioElement; khi lỗi sẽ dùng giọng
trình duyệt nếu có. Native chuyển sang TTS thiết bị nếu không tải được file.
Giọng dự phòng phụ thuộc giọng/ngôn ngữ đã cài trên máy.

Cài app xong chưa có MP3: lần phát đầu cần mạng. Audio đã tải thành công có
thể dùng offline khi còn trong cache. Cache hiện giữ tối đa 256 file, không
phải chức năng tải và giữ toàn bộ thư viện offline. Chưa bổ sung màn hình tải
gói offline. Bài kiểm tra loa H20 dùng audio mẫu từ Cloudinary/cache; bài thu
và phát lại giọng người dùng vẫn xử lý local.

## Cập nhật thư viện

Không chép API Key/Secret vào mã Flutter, JSON, tài liệu hay bộ cài.
Công cụ đọc file thông tin tài khoản ở ngoài repository khi chạy upload.

```powershell
node tool/migrate_app_audio_to_cloudinary.mjs
node tool/migrate_app_audio_to_cloudinary.mjs --upload --verify --link --cloud-name ysc2jlrt --credentials C:/path/to/cloudinary-credentials.txt --concurrency 6
```

Lệnh đầu chỉ kiểm kê. Lệnh thứ hai upload, kiểm chứng và cập nhật link/bộ cài
sau khi tất cả file thành công. Checkpoint tại
`build/cloudinary/app-audio-uploads.jsonl` cho phép chạy tiếp. Public ID chứa
hash và `overwrite=false`, nên không ghi đè audio đã có. Nội dung file gốc
thay đổi sẽ sinh public ID mới.

Sau khi chạy các công cụ import/tạo lại dữ liệu audio, chạy lại migration
để cập nhật link trước khi build. Không đưa checkpoint chứa trạng thái dở
dang vào manifest dùng cho phát hành.

## Kết quả kiểm tra

- 5.833/5.833 URL tải được toàn bộ nội dung, khớp SHA-256 và dung lượng gốc.
- 9.187 tham chiếu URL trong bốn bộ dữ liệu đều thuộc manifest đầy đủ.
- 58 kiểm thử Flutter và 3 kiểm thử JavaScript cho luồng phát/hủy/dự phòng đạt.
- `flutter analyze --no-pub`: không có lỗi/cảnh báo.
- Android debug build thành công; kiểm tra ZIP của APK: 0 file audio,
  manifest chứa đúng 5.833 clip của cloud `ysc2jlrt`.
- Web release build thành công; thư mục build cũng không chứa file audio.
- Chưa build iOS hoặc kiểm thử phát trên iPhone thật: môi trường thực hiện
  là Windows. Các kiểm thử Flutter dùng player/channel giả để xác nhận luồng,
  không thay thế kiểm tra loa/H20 trên thiết bị thật.

Báo cáo lần chạy được lưu ở `build/cloudinary/`: `link-verification.json`,
`apk-verification.json`, `flutter-tests.log` và `android-build.log`.
