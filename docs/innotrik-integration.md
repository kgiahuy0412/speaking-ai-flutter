# Kế hoạch tích hợp INNOTRIK

> Cập nhật 28-07-2026: cầu nối Android thử nghiệm đã có quét/chọn thiết bị,
> quyền Bluetooth, GATT FF12/FF13/FF14, lệnh 59/58, bộ ghép packet 84 byte,
> MediaCodec Opus → PCM16 24 kHz, thống kê chẩn đoán, reconnect giới hạn và
> bài test mic 4 giây có phát lại. Trạng thái vẫn là **cần nghiệm thu thiết bị
> thật** vì APK tĩnh không xác nhận được tham số Opus/khâu auth của từng firmware.

Nguồn: báo cáo phân tích APK INNOTRIK, đặc biệt trang 9, 10, 18–21.

## Contract đã xác nhận

| Mục | Giá trị |
|---|---|
| GATT service | `0000ff12-0000-1000-8000-00805f9b34fb` |
| Data write | `0000ff13-0000-1000-8000-00805f9b34fb` |
| Data notify/input | `0000ff14-0000-1000-8000-00805f9b34fb` |
| OTA write | `0000ff15-0000-1000-8000-00805f9b34fb` |
| Auth service | `0000ff10-0000-1000-8000-00805f9b34fb` |
| Auth characteristic | `0000fff1-0000-1000-8000-00805f9b34fb` |
| Start mic | `55 AA A5 59` |
| Stop mic | `55 AA A5 58` |
| Audio packet | 84 byte |
| Packet header | 4 byte: `55 AA A5 59` |
| Payload | 80 byte raw Opus |
| MethodChannel | `ailingo_platform` |
| EventChannel | `ailingo_platform/events` |

Các hằng số được định nghĩa cả ở Dart và Kotlin. Parser từ chối packet sai chiều
dài hoặc header để lỗi BLE không đi lẫn vào audio.

## Vì sao chưa nối thẳng raw Opus vào backend

80 byte là payload Opus thô, không phải file Ogg/Opus hoàn chỉnh. Chỉ nối các
payload rồi đặt đuôi `.opus` có thể tạo file không hợp lệ vì còn thiếu thông tin
frame/container như TOC, granule/timestamp hoặc cấu hình encoder mà SDK hãng
đang giữ.

Giai đoạn phần cứng phải xác nhận một trong ba đường:

1. SDK hãng giải mã raw Opus → PCM 16 kHz mono;
2. SDK/native mux raw packet → container Ogg/Opus hợp lệ;
3. backend nhận đúng framing raw Opus và giải mã server-side.

Không chọn đường nào chỉ dựa trên suy đoán từ APK.

## Native plugin cần hoàn thiện

Flutter đã có sẵn bộ chọn nguồn BLE-first và đường Realtime → buffered Batch
Chunks. Khi adapter native báo `isAvailable=true` và phát PCM qua
`audioChunks`, controller sẽ ưu tiên BLE Realtime; lúc chưa có thiết bị, bộ
chọn tự giữ micro điện thoại nên không ảnh hưởng bản giả lập hiện tại.

1. Scan theo service FF12 và lọc đúng thiết bị.
2. Xin `BLUETOOTH_SCAN/CONNECT` theo Android version.
3. Connect GATT, discover service, bật notify FF14.
4. Thực hiện auth FF10/FFF1 nếu thiết bị yêu cầu.
5. Queue write ưu tiên cho lệnh 59/58 và chờ write acknowledgement.
6. Nhận packet 84 byte, validate, tách 80 byte payload.
7. Decode/mux Opus trong native layer.
8. Phát event `audio.startRecording`, `audio.chunk`, `audio.stopRecording`,
   `ble.connected`, `ble.disconnected`, `device.button`.
9. Reconnect có backoff, không loop vô hạn.
10. Foreground service + notification khi chạy nền/khóa màn hình.

## A2DP

TTS dùng Android media route. Nếu loa thiết bị đã ghép và được chọn làm media
output, `just_audio` sẽ phát qua A2DP. BLE GATT điều khiển mic và Bluetooth
Classic/A2DP phát loa là hai connection profile riêng.

Test bắt buộc trên thiết bị thật:

- A2DP đang kết nối trong lúc BLE reconnect;
- HFP không giành route và làm giảm chất lượng;
- rút/mất loa giữa lúc phát;
- khóa màn hình, cuộc gọi đến, app background;
- thiết bị có nhiều output Bluetooth cùng lúc.

## Gate nghiệm thu phần cứng

Chỉ đánh dấu mic BLE hoàn tất khi có:

- capture log write 59/58;
- ít nhất 100 packet liên tiếp đúng 84 byte;
- decode thành audio nghe được, đúng tốc độ;
- câu tiếng Việt qua ASR đúng trên bộ test thật;
- reconnect sau mất sóng;
- kiểm tra pin/nhiệt và foreground policy;
- so sánh latency Flutter với baseline web.
