# APK release HOMI 1.0.5+7

Trạng thái: đã build và kiểm tra; chưa ký bằng khóa production.

- APK: `HOMI-1.0.5+7-release-pending-production-signing.apk`
- Kích thước: 358.884.559 byte (342,3 MiB).
- Package: `com.innotrik.aispeaking`; min SDK 24; target SDK 36.
- ABI: armeabi-v7a, arm64-v8a, x86_64.
- SHA-256: `3B77732E855215082EEE7AD4363A5A2ADC038838D3B94486ED503ECC09976586`.
- Build release, không bật debuggable; backend production, `USE_DEMO_BACKEND=false`.
- Đủ 4.916 MP3 mới, tổng 189.673.805 byte. Đã so sánh SHA-256 của từng MP3 trong APK với asset nguồn: 0 sai khác.
- 33 kiểm tra quyền riêng tư/onboarding/audio và 2 kiểm tra cấu hình/asset production đều đạt. Phân tích 3 tệp Dart vừa thay đổi không có lỗi.

## Chữ ký cần hoàn tất

`apksigner verify` xác nhận chữ ký v2 hợp lệ, nhưng chứng thư hiện tại là `C=US, O=Android, CN=Android Debug`. Dự án chưa có `android/key.properties`, nên lần biên dịch kiểm tra sử dụng cơ chế ký debug dự phòng hiện có. APK này dùng để kiểm tra trước khi ký chính thức; không phải bản production sẵn sàng phân phối.

Cần chọn dùng khóa ký production đã có hoặc tạo khóa production mới. Nếu ứng dụng đã phát hành, cần giữ đúng danh tính ký tương ứng để hỗ trợ cập nhật. Xem [hướng dẫn ký ứng dụng Android](https://developer.android.com/studio/publish/app-signing).

Sau khi có cấu hình ký production, chạy từ thư mục dự án:

```powershell
./tool/build_production_apk.ps1
```

Lệnh này kiểm tra cấu hình production/asset và đặt `requireProductionSigning=true` để Gradle từ chối thiếu cấu hình ký hoặc alias `androiddebugkey`. Sau build, đối chiếu chứng thư bằng `apksigner` trước khi phân phối.

## Hồ sơ pháp lý

`HOMI-ho-so-phap-ly-2026-09-11.zip` chứa tài liệu đối chiếu, các URL đã kiểm tra qua trình duyệt, thông báo thư viện, Apache 2.0 và toàn bộ giấy phép Flutter/Dart trích từ APK.

Đọc `legal/HO_SO_PHAP_LY.md` để xem các phần đã có trong ứng dụng và phần còn cần hoàn tất: bổ sung Google ML Kit/Android trên website, xác minh cam kết backend và giấy tờ quyền phát hành nội dung. Không có tài liệu nào trong gói này là chứng nhận đã được cửa hàng ứng dụng hoặc cơ quan pháp lý phê duyệt.

Chưa cài APK này lên thiết bị, chưa tải lên Google Play và chưa thay đổi các trang pháp lý công khai.
