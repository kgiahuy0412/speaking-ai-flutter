# Trợ lý giao tiếp — Flutter Android client

Ứng dụng Flutter này là mobile client mới cho backend Next.js hiện tại. Luồng
AI vẫn chạy hoàn toàn ở backend: ASR tiếng Việt → normalize/rule/cache →
Cloudflare AI → TTS streaming → history/telemetry. APK không chứa khóa API
của nhà cung cấp AI.

Thiết kế đang triển khai là hướng **Live Conversation**:

- một màn hình nói chính, dùng một tay;
- trạng thái ghi âm/VAD và nút Dừng luôn rõ;
- câu tiếng Việt, câu tiếng Anh, phát lại và đánh giá nằm trong cùng luồng;
- lịch sử mở trực tiếp từ màn hình chính; cài đặt kỹ thuật và ASR mode nằm
  trong bottom sheet riêng;
- `AudioInput` tách biệt để có thể thay mic điện thoại bằng mic BLE INNOTRIK.

## Chạy dự án

Yêu cầu:

- Flutter stable 3.44+;
- JDK 17;
- Android SDK 36;
- Android 7.0 (API 24) trở lên.

Workspace hiện chưa có Flutter SDK. Sau khi cài Flutter:

```powershell
flutter create --platforms=android --org com.innotrik .
flutter pub get
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
```

`10.0.2.2` là địa chỉ máy host từ Android Emulator. Khi chạy trên điện thoại
thật, dùng domain HTTPS hoặc địa chỉ LAN của máy backend. Release build chỉ cho
HTTPS; cleartext HTTP chỉ được bật trong debug manifest.

Chạy UI với backend demo:

```powershell
flutter run --dart-define=USE_DEMO_BACKEND=true
```

Chạy bằng file cấu hình:

```powershell
Copy-Item dart_defines.example.json dart_defines.local.json
flutter run --dart-define-from-file=dart_defines.local.json
```

Không commit `dart_defines.local.json` nếu sau này file có dữ liệu riêng.

Cấu hình audio mặc định đã chuẩn bị cho BLE-first nhưng vẫn an toàn khi chưa có
thiết bị:

- `PREFER_BLE_STREAMING=true`: ưu tiên mic BLE khi native adapter báo sẵn sàng;
  hiện tại tự dùng micro điện thoại vì adapter INNOTRIK chưa được kích hoạt.
- Trên web, câu nói ngắn hơn 8 giây được gửi bằng một request multipart trực
  tiếp; câu dài hơn mới tự chuyển sang audio-session/chunk upload để tải song
  song với lúc ghi âm.
- `REALTIME_BATCH_FALLBACK=true`: giữ PCM trong bộ đệm cục bộ cho các nguồn
  streaming của thiết bị và chuyển sang Cloudflare Batch Chunks khi cần.
- `REALTIME_FALLBACK_BUFFER_BYTES=15728640`: giới hạn bộ đệm 15 MiB, chừa phần
  dung lượng cho WAV header trong giới hạn session 16 MiB của backend.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=dart_defines.local.json
```

## Trạng thái tích hợp

Đã có:

- UI native Flutter theo thiết kế đã chọn;
- Android streaming nhận chữ trực tiếp như web, có partial/final và VAD;
- Cloudflare Batch Chunks cho web với fast path một request cho câu ngắn và
  chunk upload thích ứng cho câu dài;
- endpoint và client Realtime cũ đã bị vô hiệu hóa; không có đường gọi nhà cung
  cấp AI thứ hai cho ASR, dịch hoặc TTS;
- bộ chọn nguồn ưu tiên BLE và tự dùng micro điện thoại khi BLE/native decoder
  chưa sẵn sàng;
- manifest 34 ý định BLE thông dụng được tải khi mở app và audio tiếng Anh tương
  ứng được cache trên điện thoại; fast path chỉ nhận khi confidence ≥ 0,88,
  cách ứng viên thứ hai ≥ 0,15 và ổn định 3 cập nhật;
- cổng native cho ASR offline BLE và cơ chế chuyển sang Cloudflare Batch Chunks
  khi kết quả offline chưa chắc chắn; cổng hiện tự báo chưa sẵn sàng cho tới
  khi cài model tiếng Việt và Opus decoder thật;
- partial transcript chỉ dò rule/cache và chỉ preload audio đã có, không gọi
  thêm Cloudflare text/TTS trong lúc câu nói còn thay đổi;
- phát MP3/TTS qua Android media route, phù hợp A2DP;
- tự yêu cầu backend pre-cache audio rule ở background mỗi lần mở app; request
  trả ngay và backend chỉ tạo phần còn thiếu;
- lịch sử gần đây có giờ địa phương, tìm kiếm/lọc, nhóm theo ngày, phát lại,
  đánh giá lại, xóa và metadata rule/AI/ASR/latency;
- contract INNOTRIK, UUID, lệnh mic và parser gói 84 byte;
- Android MethodChannel/EventChannel theo namespace `ailingo_platform`.

Chưa thể xác nhận nếu không có phần cứng:

- scan/connect/reconnect BLE thật;
- xác thực thiết bị và OTA;
- ghép 80-byte raw Opus payload thành stream giải mã được;
- model ASR/intent offline tiếng Việt dành cho giọng trẻ em và triển khai engine
  native phía sau cổng `ailingo_offline_intent`;
- hành vi nút vật lý, khóa màn hình và foreground service;
- route A2DP/HFP trên đúng model thiết bị.

Xem [kiến trúc](docs/architecture.md),
[API contract](docs/api-contract.md) và
[kế hoạch INNOTRIK](docs/innotrik-integration.md).

## Release

`applicationId` tạm thời là `com.innotrik.aispeaking`. Release build hiện dùng
debug signing để unblock phát triển. Trước khi phát hành phải thay package ID
nếu cần và cấu hình keystore chính thức; tuyệt đối không commit keystore hoặc
mật khẩu ký APK.



Em gửi anh/chị một số thông tin về brand để mình tham khảo và tư vấn hướng phát triển giúp em nhé ạ.

**1. Tên brand:**
Himi Chinese (HiMi Chinese)

**2. Lĩnh vực:**
Giáo dục – đào tạo tiếng Trung, tập trung vào việc giúp người Việt học tiếng Trung theo hướng dễ hiểu, thực tế và thân thiện.

**3. Định hướng brand:**
Himi Chinese muốn xây dựng hình ảnh là một thương hiệu học tiếng Trung **thân thiện, hiện đại, dễ tiếp cận và tạo cảm giác học ngoại ngữ không quá áp lực**.

Brand không muốn đi theo hướng quá học thuật hoặc quá “trung tâm giáo dục” truyền thống, mà muốn tạo cảm giác gần gũi, trẻ trung và có tính cộng đồng.

**4. Đối tượng khách hàng:**

* Người Việt có nhu cầu học tiếng Trung.
* Người mới bắt đầu hoặc đang muốn xây dựng lại nền tảng tiếng Trung.
* Học sinh, sinh viên và người trẻ đi làm.
* Những người muốn học tiếng Trung để giao tiếp, công việc, du lịch hoặc phát triển bản thân.

**5. Tính cách thương hiệu:**

* Thân thiện
* Trẻ trung
* Tích cực
* Dễ hiểu
* Chuyên nghiệp nhưng không quá cứng nhắc
* Có tính giáo dục nhưng vẫn vui vẻ, gần gũi

**6. Hình ảnh nhận diện:**
Brand đang định hướng sử dụng hình ảnh **chim cánh cụt** làm mascot. Nhân vật có phong cách 3D dễ thương, thân thiện và có thể xuất hiện trong các nội dung giáo dục.

Logo hiện tại đang phát triển theo hướng chữ **HiMi / Himi Chinese**, sử dụng tone **xanh dương – xanh da trời**, kết hợp một chút màu vàng/cam làm điểm nhấn.

Mình muốn hình ảnh tổng thể mang cảm giác:
**Learning – Friendly – Modern – Positive – Chinese Education.**

7. Nội dung dự kiến:
Fanpage có thể tập trung vào:

* Từ vựng tiếng Trung
* Câu giao tiếp thực tế
* Ngữ pháp dễ hiểu
* Phát âm
* Mẹo học tiếng Trung
* Kiến thức văn hóa Trung Quốc
* Nội dung tương tác/quiz
* Các tình huống tiếng Trung trong đời sống
* Nội dung xây dựng hình ảnh mascot Himi

8. Định hướng marketing:
Hiện tại em muốn xây dựng Himi Chinese trước hết thành một **thương hiệu giáo dục tiếng Trung có nhận diện riêng**, sau đó phát triển cộng đồng và tạo niềm tin với người học.
