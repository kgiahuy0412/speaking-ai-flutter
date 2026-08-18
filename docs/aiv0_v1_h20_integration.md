# AIV0 V1 – H20 HFP + BLE Control

## Kiến trúc đã áp dụng

- Âm thanh hai chiều dùng Bluetooth Classic HFP/SCO:
  - Micro H20 → APK.
  - APK → loa H20.
- BLE chỉ dùng cho MAIN, pin, firmware và trạng thái APP.
- APK V1 không truyền PCM/Opus qua BLE và không dùng FF12/FF13/FF14.
- Web không bị thay đổi. BLE Control AIV0 chỉ được bật trên APK Android.
- V1 không có REPLAY vật lý. Phát lại câu tiếng Anh gần nhất nằm trên APP.
- Nút nguồn và âm lượng là chức năng cục bộ của H20.

## GATT hiện tại

| Chức năng | UUID | Yêu cầu |
|---|---|---|
| Control Service | `9E3B0001-4A7C-4D6F-8B21-5C17A2D94010` | Bắt buộc |
| Button Event | `9E3B0002-4A7C-4D6F-8B21-5C17A2D94010` | Indicate + CCCD 2902 |
| APP State | `9E3B0003-4A7C-4D6F-8B21-5C17A2D94010` | ODM đã xác nhận Write with response |
| Battery | `180F / 2A19` | Đọc mức pin |
| Firmware Revision | `180A / 2A26` | Đọc chuỗi phiên bản firmware |

## Packet MAIN thực tế của H20 firmware 1.0.0

Packet đã quan sát trên characteristic `9E3B0002`:

```text
01 01 10 01 01 04 3E 00 3A F2 0B 00
```

- `byte[1]` là mã MAIN (`01`).
- `byte[2]` là sequence 8 bit, tăng một đơn vị sau mỗi lần bấm.
- `byte[3]` là thao tác (`01` nhấn ngắn, `02` nhấn giữ, `03` thả nút).
- `byte[4..5]` là flags little-endian.
- `byte[6..7]` là pin little-endian.
- `byte[8..11]` là uptime millisecond little-endian.

MAIN Raw Hex được giải mã và chuyển vào cùng `MainButtonCoordinator` với nút
MAIN trên APK. Nút âm lượng tiếp tục do Android/HFP xử lý và không đi qua luồng
này.

## APP State chưa được xác nhận

Mặc định `AIV0_DRAFT_PROTOCOL_CONFIRMED=false`:

- APK kết nối GATT, đọc pin/firmware và nhận Indication.
- APK hiển thị thời gian và raw hex MAIN trên màn hình Cài đặt.
- APK diễn giải packet MAIN thực tế nhưng chưa gửi APP State 8 byte.
- Packet khác định dạng MAIN ở trên vẫn chỉ được ghi raw và bỏ qua.

Có thể lấy log raw khi cắm điện thoại Android vào máy tính:

```powershell
adb logcat -v time Aiv0BleControl:I *:S
```

Chỉ sau khi ODM xác nhận riêng định dạng APP State 8 byte mới build với:

```powershell
flutter build apk --release `
  --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app `
  --dart-define=AIV0_DRAFT_PROTOCOL_CONFIRMED=true
```

Không bật `ENABLE_LEGACY_BLE_AUDIO` hoặc `PREFER_BLE_STREAMING` cho mẫu V1.

## Luồng nút MAIN

- MAIN giả lập trên APP và MAIN BLE cùng đi qua `MainButtonCoordinator` và có
  cùng ngữ nghĩa trong chế độ sử dụng bình thường.
- MAIN nhấn ngắn ở màn hình chính mở trợ lý với ba lựa chọn:
  - Học theo chủ đề.
  - Học từ mới.
  - Dịch sang tiếng Anh theo một câu hoặc liên tục.
- MAIN nhấn ngắn khi đang học chỉ tạm dừng câu hiện tại, giữ nguyên route, bài,
  câu và tiến độ. Trợ lý hỏi `Con cần mình giúp gì không?`, rồi chuyển lệnh cho
  adapter của mô-đun đang mở (`tiếp tục`, `nghe lại`, `câu/bài tiếp theo`,
  `câu/bài trước`, `luyện lại từ đầu`, `dừng lại`).
- Không có phản hồi sau khoảng 6 giây: hỏi lại đúng một lần `Con muốn làm gì?`.
  Lần hai vẫn im lặng thì đóng phiên lệnh và trở về đúng trạng thái bài học.
- MAIN nhấn giữ dừng hành động hiện tại nhưng không tự đóng màn hình bài học:
  - Trợ lý/ASR đang nghe → đóng phiên nghe.
  - RECORDING của bài học → hủy lượt đang thu và giữ nguyên câu.
  - PLAYING của bài học → dừng phát và giữ nguyên câu.
  - PROCESSING backend → trả BUSY, không hủy request đang xử lý.
  - RELEASE sau LONG_PRESS chỉ kết thúc gesture, không dừng lần hai.
- Packet trùng bị bỏ qua và trả DUPLICATE.
- Trong màn hình kiểm tra offline, nút `Thu thử tối đa 5 giây` bắt đầu bản ghi
  cục bộ và phát lại qua H20; không gọi backend. MAIN BLE vẫn gọi trợ lý giống
  MAIN ảo, kể cả khi chế độ kiểm tra đang bật.

## Kiểm tra phần cứng offline

Màn hình Cài đặt có chế độ `Kiểm tra phần cứng H20 offline`:

- Mở HFP/SCO và chỉ công nhận H20 khi Android báo route đang hoạt động cùng tên thiết bị input/output.
- Thu tối đa 5 giây vào file cục bộ rồi phát lại file đó qua H20.
- Phát một file được đóng gói sẵn trong APK để kiểm tra riêng loa H20.
- Không gọi repository/backend và không tải âm thanh lên cloud.
- Người kiểm tra phải xác nhận có thật sự nghe âm thanh từ loa H20; route hệ thống và xác nhận bằng tai được lưu riêng.
- Khi HFP đã kết nối nhưng SCO chưa mở, APP hiển thị `Chưa xác nhận`, không khẳng định đang dùng micro/loa H20.
- APP chỉ hiển thị phần trăm pin. Trạng thái đang sạc/đã đầy không được suy diễn khi firmware chưa cung cấp qua BLE.

## Dữ liệu còn cần ODM cung cấp

1. GATT dump đầy đủ của firmware H20 hiện tại.
2. Raw hex thực tế của một lần bấm MAIN.
3. Xác nhận mỗi lần bấm chỉ tạo đúng một Indication.
4. Xác nhận MAIN có short press/long press/press/release hay không và gửi raw riêng cho từng loại nếu có.
5. Xác nhận Button Event là 12 byte và APP State là 8 byte, kèm ý nghĩa từng byte.
6. Tên BLE advertise và phiên bản firmware dùng để kiểm thử.
7. Trước sản xuất hàng loạt: xác nhận MCU có thể đọc và gửi trạng thái đang sạc/đã đầy qua BLE hay không.

## Checklist trước khi đóng băng firmware

- Màn hình kiểm tra hiển thị đúng micro HFP và loa HFP đang dùng.
- H20 thu được giọng nói thật, không phải micro điện thoại.
- Câu tiếng Anh phát ra loa H20 và route không đổi giữa câu.
- MAIN: đúng một sự kiện cho mỗi lần bấm và điều khiển đúng ghi/dừng.
- Pin và firmware đọc được.
- BLE tự reconnect, discover lại service và đăng ký lại Indicate.
- Không có request/packet âm thanh FF12/FF13/FF14 trong log.
- Khi không có Internet, quét BLE, HFP, log MAIN, thu/phát offline vẫn hoạt động.
