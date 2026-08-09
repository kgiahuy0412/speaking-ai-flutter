# AIV0 V1 – H20 HFP + BLE Control

## Kiến trúc đã áp dụng

- Âm thanh hai chiều dùng Bluetooth Classic HFP/SCO:
  - Micro H20 → APK.
  - APK → loa H20.
- BLE chỉ dùng cho MAIN, REPLAY, pin, firmware và trạng thái APP.
- APK V1 không truyền PCM/Opus qua BLE và không dùng FF12/FF13/FF14.
- Web không bị thay đổi. BLE Control AIV0 chỉ được bật trên APK Android.

## GATT hiện tại

| Chức năng | UUID | Yêu cầu |
|---|---|---|
| Control Service | `9E3B0001-4A7C-4D6F-8B21-5C17A2D94010` | Bắt buộc |
| Button Event | `9E3B0002-4A7C-4D6F-8B21-5C17A2D94010` | Indicate + CCCD 2902 |
| APP State | `9E3B0003-4A7C-4D6F-8B21-5C17A2D94010` | Ưu tiên Write with response; fallback WRITE_NO_RESPONSE |
| Battery | `180F / 2A19` | Đọc mức pin |
| Firmware Revision | `180A / 2A26` | Đọc chuỗi phiên bản firmware |

## Chế độ an toàn trước khi ODM xác nhận raw hex

Mặc định `AIV0_DRAFT_PROTOCOL_CONFIRMED=false`:

- APK kết nối GATT, đọc pin/firmware và nhận Indication.
- APK hiển thị raw hex MAIN/REPLAY trên màn hình Cài đặt.
- APK chưa diễn giải packet và chưa gửi APP State 8 byte.
- Nút vật lý chưa điều khiển ghi âm/phát lại, tránh cố định sai giao thức firmware.

Có thể lấy log raw khi cắm điện thoại Android vào máy tính:

```powershell
adb logcat -v time Aiv0BleControl:I *:S
```

Sau khi ODM gửi raw hex MAIN/REPLAY và xác nhận đúng byte layout, cập nhật codec nếu cần, chạy test rồi build với:

```powershell
flutter build apk --release `
  --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app `
  --dart-define=AIV0_DRAFT_PROTOCOL_CONFIRMED=true
```

Không bật `ENABLE_LEGACY_BLE_AUDIO` hoặc `PREFER_BLE_STREAMING` cho mẫu V1.

## Luồng nút khi giao thức đã được xác nhận

- MAIN:
  - IDLE/READY → bắt đầu ghi âm.
  - RECORDING → dừng và xử lý.
  - PROCESSING → trả BUSY.
  - PLAYING → dừng phát và bắt đầu lượt ghi mới.
- REPLAY:
  - READY/IDLE có kết quả → phát lại câu tiếng Anh gần nhất qua HFP/SCO.
  - Chưa có kết quả → trả NO_RESULT.
  - RECORDING/PROCESSING → trả BUSY.
- Packet trùng bị bỏ qua và trả DUPLICATE.

## Dữ liệu còn cần ODM cung cấp

1. GATT dump đầy đủ của firmware H20 hiện tại.
2. Raw hex thực tế của một lần bấm MAIN và một lần bấm REPLAY.
3. Xác nhận mỗi lần bấm chỉ tạo đúng một Indication.
4. Xác nhận Button Event là 12 byte và APP State là 8 byte, kèm ý nghĩa từng byte.
5. Xác nhận `9E3B0003` có thể bổ sung Write with response hoặc hỗ trợ đồng thời hai kiểu ghi.
6. Tên BLE advertise và phiên bản firmware dùng để kiểm thử.

## Checklist trước khi đóng băng firmware

- Màn hình kiểm tra hiển thị đúng micro HFP và loa HFP đang dùng.
- H20 thu được giọng nói thật, không phải micro điện thoại.
- Câu tiếng Anh phát ra loa H20 và route không đổi giữa câu.
- MAIN/REPLAY: đúng một sự kiện cho mỗi lần bấm.
- Pin và firmware đọc được.
- BLE tự reconnect, discover lại service và đăng ký lại Indicate.
- Không có request/packet âm thanh FF12/FF13/FF14 trong log.
