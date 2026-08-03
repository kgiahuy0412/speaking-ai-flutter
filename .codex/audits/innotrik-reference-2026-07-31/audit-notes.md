# Audit tham chiếu Cài đặt INNOTRIK

Ngày: 2026-07-31

## Phạm vi

Đối chiếu bảy ảnh tham chiếu do người dùng cung cấp với mã Flutter/Android hiện tại. Đây là audit từ ảnh tĩnh và mã nguồn; chưa xác nhận hành vi của app Trung Quốc hoặc firmware trên thiết bị thật.

## Kết luận

1. Màn hình quyền và đồng ý lần đầu: làm được. Phải dùng liên kết Điều khoản/Chính sách thật, chặn các tác vụ gửi dữ liệu trước khi đồng ý, và tiếp tục xin quyền hệ thống đúng lúc sử dụng.
2. Nhắc kết nối INNOTRIK: làm được trên nền scan/connect BLE hiện có. Nên là nhắc tùy chọn vì app vẫn dùng được micro điện thoại và chức năng luyện nghe.
3. Cấu hình nút phần cứng/touch: giao diện làm được, hành vi chưa làm được an toàn vì bridge hiện chỉ nhận packet audio FF14; cần đặc tả packet `device.button`, firmware hoặc log thiết bị thật.
4. About: phiên bản app và kiểm tra cập nhật đã có hạ tầng; phiên bản firmware thiết bị chưa có giao thức đọc.
5. Chọn giọng: giao diện và lưu lựa chọn làm được. Hội thoại cần backend nhận voice ID; luyện nghe hiện chỉ có một URL MP3 mỗi câu nên cần nhiều bộ audio hoặc API TTS.
6. Cài đặt chung: ngôn ngữ Việt/Trung đã có và được lưu. Theme, trang quyền, tốc độ phát, chọn giọng chưa có. Tốc độ nên áp dụng cho câu mẫu/bản dịch, không áp dụng bài hát hay bản ghi của trẻ.
7. Splash giới thiệu: làm được bằng Android launch theme kết hợp Flutter branded loading screen. Không nên cố tình giữ lâu; chỉ hiển thị tới khi kiểm tra cập nhật/khởi tạo tối thiểu hoàn tất.

## Rủi ro UX và accessibility

- Ảnh quyền dồn nhiều nội dung pháp lý vào một màn hình; cần câu chữ ngắn, liên kết rõ và cho phép thoát nếu thiết bị không bắt buộc.
- Hộp thoại kết nối trong ảnh khiến người dùng hiểu thiết bị là bắt buộc. Với app hiện tại nên ghi rõ có thể dùng micro điện thoại.
- Danh sách giọng nên có tên mô tả thay cho chỉ ký hiệu giới tính; nút nghe thử cần trạng thái đang phát/dừng và nhãn cho trình đọc màn hình.
- Slider tốc độ cần đọc được giá trị và có nút trở về 1.0x.
- Ảnh splash có chữ xám trên nền đỏ tương phản thấp; bản triển khai nên dùng màu thương hiệu hiện có và chữ đủ tương phản.
- Ảnh không đủ để xác nhận focus, TalkBack, cỡ vùng chạm, xoay màn hình hay font lớn; các mục này cần test trên bản chạy.

## Bằng chứng

- `01-permission-consent.png`
- `02-device-connect-dialog.png`
- `03-hardware-key-configuration.png`
- `04-about-screen.png`
- `05-voice-selection.png`
- `06-app-settings.png`
- `07-launch-screen.png`
