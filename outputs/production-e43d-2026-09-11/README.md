# HOMI release — backend production-e43d

Bản build áp dụng địa chỉ backend người dùng cung cấp ngày 11/09/2026:

`https://speaking-ai-nextjs-backend-production-e43d.up.railway.app`

## Cấu hình được nạp

- `USE_DEMO_BACKEND=false`.
- Chính sách quyền riêng tư: https://homi-app-privacy.lixiang22.chatgpt.site/privacy
- Điều khoản: https://homi-app-privacy.lixiang22.chatgpt.site/terms
- Hỗ trợ: https://homi-app-privacy.lixiang22.chatgpt.site/support
- Thông tin nhà cung cấp và thời hạn lưu được lưu bằng UTF-8, sửa các ký tự `?` mất dấu trong lệnh đã dán.
- Giữ thông báo Google ML Kit đang dùng cho tính năng dịch trên thiết bị, cùng Railway, Cloudflare Workers AI và Cloudinary.
- Giữ cấu hình thiết bị/audio của bản production hiện có; bộ audio HOMI gồm 4.916 MP3.

`production-defines.json` là bản chụp chính xác đầu vào của lần build này. Không dùng các dấu gạch chéo escape hoặc liên kết Markdown trong giá trị URL.

## Lệnh chạy lại

Chạy từ thư mục gốc dự án:

```powershell
flutter run --release -d emulator-5554 --dart-define-from-file=outputs/production-e43d-2026-09-11/production-defines.json
```

Build lại APK với cùng cấu hình:

```powershell
flutter build apk --release --dart-define-from-file=outputs/production-e43d-2026-09-11/production-defines.json
```

## Xác minh

- Backend mới phản hồi HTTPS 200 tại thời điểm kiểm tra; việc này xác nhận địa chỉ truy cập được, chưa phải kiểm thử toàn bộ API giọng nói.
- 12 kiểm tra cấu hình, asset, onboarding và quyền riêng tư đạt. Xem `tests.log`.
- Kiểm tra nội dung APK, hash và chữ ký được ghi trong `verification.json` sau khi build xong.

APK dùng chế độ biên dịch release và backend production-e43d. Chữ ký dùng khóa Android Debug hiện có vì chưa được cung cấp khóa phát hành; chưa đổi danh tính ký của ứng dụng.

Các URL và nội dung công bố này là cấu hình pháp lý trong ứng dụng. Phần đối chiếu tài liệu công khai và giấy phép đã chuẩn bị tại `../production-2026-09-11/legal/HO_SO_PHAP_LY.md`; lần build này không thay đổi website hoặc nộp hồ sơ lên Google Play.
