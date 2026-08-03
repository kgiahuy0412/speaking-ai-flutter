# So sánh điểm vào Luyện nghe theo chủ đề

Ngày: 2026-07-31

## Bằng chứng

1. `01-innotrik-side-tabs-reference.png`: giao diện INNOTRIK dùng tab dọc ở hai cạnh màn hình.
2. `02-current-large-listening-card.png`: giao diện hiện tại dùng thẻ lớn, luôn hiển thị ngay dưới header.

## Nhận định

- Thẻ hiện tại cao tối thiểu 126 px, cộng khoảng cách sau thẻ khoảng 140 px. Nó dễ tìm, vùng chạm lớn và phù hợp trẻ nhỏ, nhưng cạnh tranh không gian với kết quả hội thoại.
- Tab cạnh tiết kiệm diện tích nhưng không có hover trên mobile; phải tap. Chữ dọc khó quét, trạng thái mở/đóng kém rõ và có nguy cơ xung đột với cử chỉ vuốt cạnh của hệ điều hành.
- Không nên thêm một bước “tap để phóng to rồi tap lần nữa để vào trang”. Bước trung gian không tạo thêm giá trị.

## Khuyến nghị

Dùng thẻ compact luôn hiển thị, cao khoảng 84–92 px:

- mascot 52–60 px;
- tiêu đề `Luyện nghe theo chủ đề`;
- một dòng metadata như `50 chủ đề • 6–7 tuổi` hoặc tiến độ gần nhất;
- mũi tên 40–44 px;
- chạm toàn bộ thẻ để vào thẳng catalog hoặc tiếp tục bài gần nhất theo quy tắc đã chốt.

Nếu Luyện nghe trở thành chức năng ngang hàng với Trợ lý giao tiếp, nâng nó thành điều hướng cấp cao có nhãn rõ ràng; không dùng tab dọc ở mép màn hình.

## Giới hạn

Ảnh tĩnh không xác nhận animation, TalkBack, kích thước vùng chạm thực tế, font lớn hoặc xung đột cử chỉ. Cần test trên bản chạy sau khi chọn hướng.
