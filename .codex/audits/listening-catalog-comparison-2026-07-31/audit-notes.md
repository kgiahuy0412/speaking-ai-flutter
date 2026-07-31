# So sánh catalog Luyện nghe và Scene Learning

Ngày: 2026-07-31

## Bằng chứng

1. `01-innotrik-scene-learning.png`: trang Scene Learning của app tham chiếu.
2. `02-current-topic-catalog.png`: trang 50 chủ đề hiện tại của ứng dụng.

## Kết luận

Luyện nghe gần ngang hàng với Trợ lý giao tiếp nên phải là một khu vực điều hướng cấp cao, không phải thẻ quảng bá nằm bên trong trang Giao tiếp.

Trang hiện tại đã có đúng cấu trúc bottom navigation gồm `Giao tiếp`, `Luyện nghe`, `Lịch sử`. Nên dùng thanh này thống nhất trên màn hình Giao tiếp, rồi bỏ thẻ Luyện nghe lớn. Chạm `Luyện nghe` mở thẳng danh sách 50 chủ đề.

## So sánh catalog

- Scene Learning có Featured, AI Picks, Favorites, số câu/từ vựng/thời lượng. Nó giàu metadata nhưng tốn nhiều chiều cao; trên một màn hình chỉ thấy rõ khoảng một scene.
- Catalog hiện tại hiển thị tuổi, tiếp tục học, bốn chủ đề đầu tiên và tiến độ ngay trên một màn hình. Cấu trúc phù hợp trẻ nhỏ và chương trình 50 chủ đề hơn.
- Không nên thêm một trang Featured trung gian trước catalog. Nó làm tăng số thao tác và làm chậm việc chọn bài.

## Có thể học từ ảnh tham chiếu

- Thêm thời lượng dự kiến hoặc số câu vào card chủ đề nếu dữ liệu có sẵn.
- Có thể thêm vùng `Gợi ý cho con` nhỏ, không lấn át catalog.
- Không cần refresh, pin hoặc Favorites ở giai đoạn đầu nếu nội dung là chương trình cố định.

## Hướng đề xuất

1. Bottom navigation dùng chung toàn app: `Giao tiếp`, `Luyện nghe`, `Lịch sử`.
2. Trang Giao tiếp bỏ thẻ Luyện nghe lớn và dành không gian cho kết quả/nút nói.
3. Tab Luyện nghe mở thẳng catalog 50 chủ đề hiện tại.
4. Giữ card `Tiếp tục học` trong catalog nhưng không tự chuyển thẳng vào bài.
5. Mỗi tab giữ trạng thái cuộn và nội dung khi người dùng đổi qua lại.

## Giới hạn

Ảnh tĩnh không xác nhận animation, TalkBack, font lớn hoặc trạng thái back navigation. Cần kiểm tra trên bản chạy sau khi triển khai.
