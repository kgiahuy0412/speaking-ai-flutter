# Phân tích luồng Settings — 2026-08-04

## Phạm vi

- Bề mặt: Settings hiện tại của INNOTRIK trên màn hình 390 × 844.
- Mục tiêu: bổ sung Giao diện sáng/tối, hướng dẫn tập trung từng chức năng và Feedback mà không làm Settings rối hơn.
- Bằng chứng: `goldens/01-settings-top-390x844.png` và `goldens/02-settings-bottom-390x844.png`.

## Luồng hiện tại

1. Mở biểu tượng bánh răng — trạng thái: tốt, dễ tìm.
2. Xem phần đầu Settings — trạng thái: cần tổ chức lại; ngôn ngữ, nguồn âm thanh, BLE và HFP đang trộn trong một trang.
3. Cuộn tới nhận diện/VAD/lịch sử — trạng thái: dùng được nhưng quá thiên về kỹ thuật và cuộn sâu.

## Kết luận

Ba mục mới đều phù hợp với Settings. Tuy nhiên, Settings nên đổi từ bottom sheet “Cài đặt lượt nói” thành trang “Cài đặt” toàn màn hình, chia bốn nhóm phẳng:

1. Cá nhân hóa: Giao diện, Ngôn ngữ.
2. Thiết bị & âm thanh: HFP, nguồn mic, tốc độ/giọng đọc.
3. Nâng cao: chế độ nhận diện và thời gian tự dừng; mặc định thu gọn.
4. Hướng dẫn & hỗ trợ: Xem lại hướng dẫn, Gửi phản hồi, Giới thiệu/phiên bản.

Vì sản phẩm hiện dùng HFP, các mục BLE không nên chiếm diện tích ở luồng phổ thông. Nếu vẫn cần để thử nghiệm, đưa chúng vào “Nâng cao” hoặc chỉ bật bằng cờ nội bộ.

## Luồng đề xuất

### Giao diện

- Mặc định: Theo hệ thống.
- Tùy chọn: Theo hệ thống / Sáng / Tối.
- Áp dụng tức thì, lưu trên thiết bị và không yêu cầu khởi động lại.
- Dark mode cần lớp phủ/tài nguyên nền tối riêng; không đảo màu ảnh phong cảnh.

### Hướng dẫn lần đầu

1. Hoàn tất điều khoản, quyền cần thiết và hộp nhắc HFP.
2. Vào trang chính, chờ giao diện ổn định rồi phủ lớp tối 72%.
3. Spotlight 1: nút Bắt đầu nói.
4. Spotlight 2: tab Từ vựng.
5. Spotlight 3: tab Chủ đề.
6. Spotlight 4: Lịch sử và Cài đặt.
7. Hoàn tất bằng “Bắt đầu thử”; lưu phiên bản onboarding đã xem.

Mỗi bước có tiêu đề ngắn, một câu mô tả, tiến độ 1/4, “Bỏ qua” và “Tiếp”. Trong Settings có “Xem lại hướng dẫn”; thao tác này không xóa dữ liệu hay tiến độ học.

### Feedback

1. Settings → Gửi phản hồi.
2. Chọn loại: Báo lỗi / Góp ý / Nội dung học / Khác.
3. Nhập nội dung bắt buộc; email liên hệ và ảnh chụp màn hình là tùy chọn.
4. “Đính kèm thông tin chẩn đoán” phải là opt-in và giải thích rõ dữ liệu gửi đi.
5. Gửi → trạng thái đang gửi → thành công hoặc lỗi có nút thử lại.

Không tự động gửi bản ghi âm, câu trẻ đã nói, lịch sử dịch hay mã thiết bị Bluetooth. Copy nên hướng tới phụ huynh/người chăm sóc.

## Rủi ro UX và accessibility

- Bottom sheet hiện tại sẽ quá dài nếu thêm ba nhóm mới.
- Dark mode phải đạt tương phản tối thiểu 4.5:1 cho chữ thường và 3:1 cho icon/đường viền quan trọng.
- Coach mark phải hỗ trợ Back/Escape, giảm chuyển động, thứ tự focus và thông báo cho screen reader.
- Không dùng màu đơn lẻ để biểu thị trạng thái kết nối hoặc lỗi.
- Form Feedback cần nhãn lỗi cụ thể và giữ nội dung nếu gửi thất bại.

## Thứ tự triển khai

1. Chuyển Settings thành trang đầy đủ và gom lại cấu trúc.
2. ThemeMode + lưu lựa chọn + hoàn thiện token dark.
3. Coach marks + cờ `onboardingVersion` + nút xem lại.
4. Feedback form sau khi xác định nơi nhận dữ liệu và chính sách đính kèm chẩn đoán.

## Giới hạn bằng chứng

- Hai ảnh chụp xác nhận bố cục, mật độ và độ sâu cuộn; chưa chứng minh đầy đủ hỗ trợ bàn phím, screen reader hoặc tương phản ở Dark Mode chưa được xây dựng.
- Font CJK fallback không được nạp trong môi trường golden; đánh giá trực quan chỉ dựa trên giao diện tiếng Việt.
