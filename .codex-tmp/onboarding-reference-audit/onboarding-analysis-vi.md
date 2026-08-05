# Phân tích hướng dẫn người dùng lần đầu cho INNOTRIK

## Phạm vi

- Nguồn tham khảo: video `2aOboQpKdCYKhRNlRjyEscYxOUz25rK9Mz1iEiem.mp4` (33 giây) và hai ảnh màn hình quyền người dùng cung cấp.
- Mục tiêu: đề xuất onboarding cho app INNOTRIK hiện tại, hỗ trợ Android/APK và Web, trong đó HFP là tùy chọn và micro điện thoại vẫn dùng được.

## Những bước thấy trong video tham khảo

1. Spotlight trạng thái kết nối và thiết bị trên thanh đầu trang — tốt, dễ hiểu đúng ngữ cảnh.
2. Spotlight nút Cài đặt — tốt nhưng không nên đưa quá sớm hơn chức năng chính.
3. Spotlight nút bắt đầu/dừng giao tiếp — rất tốt, đây là hành động chính.
4. Spotlight lối mở Scene/Chủ đề — hữu ích nhưng tab dọc ở sát mép hơi khó chạm và khó đọc.
5. Tự chuyển sang Từ vựng, hướng dẫn tìm kiếm và thêm từ — rõ chức năng nhưng làm tour dài hơn.
6. Tự chuyển sang Scene Learning — người dùng có thể mất phương hướng nếu không thấy tiến độ và nút quay lại.
7. Hiện hộp tối ưu pin rồi mở Cài đặt hệ thống — không nên nằm trong tour lần đầu; đây là yêu cầu kỹ thuật chỉ nên hỏi khi thật sự cần chạy nền.
8. Xin quyền Bluetooth/Location trước khi người dùng thực hiện hành động liên quan — tạo ma sát và không phù hợp với INNOTRIK hiện dùng HFP, không dùng BLE.

## Kết luận từ mẫu tham khảo

Nên học cách làm spotlight trực tiếp trên giao diện thật, tooltip ngắn, có tiến độ và cho phép bỏ qua. Không nên sao chép việc xin nhiều quyền khi mở app, bắt buộc kết nối thiết bị, tự đưa người dùng qua quá nhiều màn hình, hoặc mở Cài đặt tối ưu pin trong lần đầu.

## Luồng đề xuất cho INNOTRIK

### Mỗi lần mở app

1. Màn hình splash hiện tại chỉ làm nhiệm vụ tải dữ liệu, tối đa khoảng 2–3 giây.
2. Không xin quyền và không bắt buộc HFP trên splash.

### Lần mở đầu tiên

1. Sau splash, hiển thị hộp chào mừng trên màn hình chính: `Mình sẽ chỉ con cách dùng trong khoảng 20 giây` với `Bắt đầu` và `Bỏ qua`.
2. Bước 1/6 — spotlight nút `Bắt đầu nói`: giải thích trẻ nói tiếng Việt và app giúp tạo câu tiếng Anh.
3. Bước 2/6 — spotlight vùng kết quả: giải thích nơi hiển thị câu tiếng Việt và câu tiếng Anh.
4. Bước 3/6 — spotlight `Từ vựng`: giải thích lưu, nghe lại và thêm từ.
5. Bước 4/6 — spotlight `Chủ đề`: giải thích 50 chủ đề, bài nghe và bài hát theo độ tuổi.
6. Bước 5/6 — spotlight `Lịch sử`: giải thích xem lại các lượt nói và bài đã học.
7. Bước 6/6 — spotlight trạng thái mic/HFP hoặc Cài đặt: giải thích micro điện thoại dùng được ngay; INNOTRIK là lựa chọn nâng cao.
8. Kết thúc bằng `Con đã sẵn sàng!` và nút `Thử nói ngay`.

### Luồng HFP

1. Khi chưa kết nối, hiển thị trạng thái cố định không chặn: `Đang dùng micro điện thoại` và hành động `Kết nối INNOTRIK`.
2. Lần đầu bấm kết nối mới giải thích và xin quyền Bluetooth cần thiết.
3. Nếu chọn `Để sau`, tiếp tục dùng micro điện thoại. Trạng thái kết nối vẫn luôn nhìn thấy, thay cho popup lặp lại gây khó chịu.
4. Chỉ hướng dẫn ghép đôi trong Cài đặt Bluetooth hệ thống vì thiết bị hiện dùng HFP; không mô tả quét BLE.
5. Không xin quyền vị trí nếu luồng HFP và phiên bản Android mục tiêu không yêu cầu quyền đó.

### Xin quyền theo ngữ cảnh

- Micro: xin khi người dùng bấm `Bắt đầu nói` lần đầu.
- Bluetooth/HFP: xin khi người dùng bấm `Kết nối INNOTRIK`.
- Thông báo: xin khi người dùng bật nhắc học.
- Camera: chỉ xin khi có chức năng thực sự dùng camera.
- Tối ưu pin: để trong phần trợ giúp/kết nối và chỉ hiện khi tính năng chạy nền thật sự cần nó.

## Mục trong Cài đặt

Thêm nhóm `Hỗ trợ`:

- `Hướng dẫn sử dụng` — đóng Setting và chạy lại tour 6 bước trên màn hình chính.
- `Kết nối INNOTRIK` — checklist ghép đôi HFP, chọn thiết bị, thử micro và xử lý lỗi.
- `Quyền ứng dụng` — hiển thị trạng thái từng quyền và nút mở Cài đặt hệ thống.
- `Gửi phản hồi` — có thể bổ sung ở giai đoạn sau.

## Quy tắc giao diện và khả năng tiếp cận

- Lớp phủ tối khoảng 55–65%, khoét sáng đúng một mục mỗi bước.
- Tooltip tối đa hai câu, chữ lớn, nút `Tiếp`, `Quay lại`, `Bỏ qua`, cùng chỉ báo `2/6`.
- Không tự phát âm thanh; có nút loa nếu muốn nghe hướng dẫn.
- Mục tiêu chạm tối thiểu 48dp, hỗ trợ chữ lớn, TalkBack/VoiceOver và chế độ giảm chuyển động.
- Khi đổi Dark/Light Mode, tooltip phải dùng màu từ theme thay vì màu chữ cố định.

## Gợi ý kỹ thuật Flutter

- Dùng `OverlayEntry`, `GlobalKey` và `CustomPainter` để vẽ spotlight, tránh thêm phụ thuộc nếu muốn kiểm soát giao diện Android và Web giống nhau.
- Lưu `onboardingVersion` thay cho một biến boolean. Khi tour được thay đổi lớn, tăng version để người dùng thấy phần mới đúng một lần.
- Lưu riêng trạng thái `completed`/`skipped`; cả hai đều không tự hiện lại, nhưng luôn có thể mở từ Setting.
- Kiểm thử: lần cài đầu, bỏ qua, hoàn tất, chạy lại từ Setting, Dark/Light Mode, chữ 200%, màn hình nhỏ, Android/Web và trường hợp target chưa render.

## Đề xuất ưu tiên

1. Làm tour 6 bước và mục `Hướng dẫn sử dụng` trong Setting.
2. Tách HFP thành luồng tùy chọn, không chặn micro điện thoại.
3. Xin quyền đúng thời điểm sử dụng.
4. Sau khi ổn định mới thêm hướng dẫn tối ưu pin, video ngắn hoặc giọng đọc cho tooltip.
