# Audit luồng lịch sử thu âm

Ngày kiểm tra: 2026-07-20  
Phạm vi: Flutter Android → backend Next.js → danh sách lịch sử gần đây.  
Thiết bị: Android emulator 1080 × 2400, backend `http://10.0.2.2:3000`.

## Trạng thái sau cải thiện

Đã xử lý các vấn đề có thể giải quyết an toàn trong MVP:

- đổi thời gian UTC sang giờ địa phương;
- tách rõ Đúng ý, Sai ý và Chưa đánh giá;
- đưa Lịch sử ra màn hình chính;
- thêm phát lại, đánh giá lại, tìm kiếm, lọc, nhóm theo ngày, làm mới và xóa;
- hiển thị ngữ cảnh, rule/AI, ASR mode và độ trễ;
- Flutter yêu cầu tối đa 100 bản ghi; backend giới hạn phản hồi hợp lệ và giữ
  tối đa 500 bản ghi trong file local;
- bổ sung unit, repository và widget test cho luồng lịch sử.

Việc chuyển sang database và tách dữ liệu theo tài khoản/thiết bị chưa thực hiện
vì cần quyết định kiến trúc đăng nhập và môi trường triển khai production.

## Mục tiêu người dùng

Sau khi thu âm và nhận câu tiếng Anh, người dùng cần tìm lại đúng lượt nói, biết kết quả đã được đánh giá thế nào và có thể tiếp tục sử dụng dữ liệu đó.

## Các bước đã kiểm tra

### 1. Hoàn tất một lượt nói — tốt

Ảnh: `build/audit-history/01-result-after-recording.png`

- Flutter hiển thị đầy đủ câu tiếng Việt, câu tiếng Anh, nút phát lại và Đúng ý/Sai ý.
- Lượt nói `Ngày mai mình đi công viên nhé.` xuất hiện đúng trong dữ liệu backend.

### 2. Tìm lối vào lịch sử — cần cải thiện

Ảnh: `build/audit-history/03-settings-history-entry.png`

- Có nút `Xem lịch sử gần đây` và nhãn dễ hiểu.
- Tuy nhiên nút nằm cuối trang Cài đặt, phải mở bánh răng rồi cuộn xuống mới thấy.
- Lịch sử là chức năng sử dụng thường xuyên nhưng đang bị đặt chung với cấu hình kỹ thuật.

### 3. Xem danh sách lịch sử — hoạt động, nhưng còn thiếu chức năng

Ảnh: `build/audit-history/04-history-list.png`

- Bản ghi mới nhất xuất hiện đầu danh sách và khớp với kết quả vừa thu.
- API trả về 50 lượt gần nhất; dữ liệu thực có cả lượt dùng audio Flutter, batch ASR, Android streaming, rule, cache và AI.
- Danh sách dễ đọc, phân biệt rõ câu Việt và câu Anh.

## Phần đã cải thiện

- Flutter đã kết nối đúng `GET /api/history`, không dùng dữ liệu demo khi chạy backend thật.
- Backend lưu lại câu Việt, câu Anh, thời gian, input mode, ASR mode, rule/AI, nguồn audio, latency và đánh giá.
- Đánh giá và latency được cập nhật lại bằng `PATCH /api/history`.
- Backend ghi file theo kiểu tệp tạm rồi đổi tên, đồng thời xếp hàng mutation trong một process để giảm nguy cơ ghi đè.
- Dòng JSON lỗi được bỏ qua và cảnh báo thay vì làm hỏng toàn bộ lịch sử.
- Lịch sử được sắp mới nhất trước và tải mới mỗi lần mở sheet.
- Trạng thái rỗng, tải và lỗi đều có giao diện riêng.

## Phần chưa cải thiện

### Ưu tiên cao

1. **Giờ hiển thị sai múi giờ.** Backend lưu `13:35Z`, thiết bị ở Bangkok phải hiển thị khoảng `20:35`, nhưng Flutter vẫn hiện `13:35`. Model đang dùng `DateTime.parse` nhưng giao diện chưa gọi `toLocal()`.
2. **Sai ý và chưa đánh giá đang dùng cùng một biểu tượng.** Chỉ `qualityApproved == true` hiện dấu kiểm; `false` và `null` đều hiện bong bóng chat. Người dùng không biết lượt nào đã bị đánh giá Sai ý.
3. **Khó tìm lịch sử.** Cần mở Cài đặt, cuộn gần hết trang rồi mới mở được lịch sử.
4. **Không thể phát lại từ lịch sử.** Model Flutter không giữ `audioUrl`, và mỗi hàng lịch sử không có nút nghe lại.

### Ưu tiên vừa

5. Không thể đánh giá lại Đúng ý/Sai ý ngay trong lịch sử.
6. Không hiển thị ngày, chỉ hiển thị giờ; lịch sử nhiều ngày sẽ khó phân biệt.
7. Không có tìm kiếm, lọc theo ngày/ngữ cảnh/ASR mode hoặc nhóm theo ngày.
8. Không có nút tải lại, xóa một lượt hoặc xóa lịch sử trong Flutter.
9. Không hiển thị ngữ cảnh, rule/AI, cache/TTS hoặc độ trễ; các dữ liệu này đã có ở backend nhưng Flutter bỏ qua.
10. Backend API chỉ trả 50 lượt mới nhất nhưng file hiện có 94 dòng và vẫn tiếp tục tăng. Giới hạn 50 chỉ áp dụng lúc đọc, không cắt bớt file lúc ghi.
11. Backend lưu vào một file local dùng chung, chưa tách theo người dùng/thiết bị. Khi triển khai serverless hoặc nhiều instance, local filesystem và mutation queue trong bộ nhớ không đủ để bảo đảm lưu bền vững.
12. Test hiện chỉ kiểm tra warm-up và lỗi JSON; chưa có test parse danh sách lịch sử, thứ tự mới nhất, múi giờ, trạng thái `false`, tải lại hoặc widget history.

## Rủi ro accessibility

- Màu chữ và kích thước vùng chạm hiện khá tốt.
- Trạng thái đánh giá chỉ dựa vào icon/màu và còn gộp `false` với `null`; nên có nhãn chữ `Đúng ý`, `Sai ý`, `Chưa đánh giá`.
- Chưa kiểm tra thực tế với TalkBack, cỡ chữ lớn hoặc tương phản tăng cường.
- Danh sách chưa có mô tả semantics gộp cho từng lượt nói; trình đọc màn hình có thể phải đọc nhiều phần rời rạc.

## Khuyến nghị theo thứ tự

1. Sửa giờ địa phương và tách rõ ba trạng thái đánh giá.
2. Đưa nút Lịch sử ra màn hình chính hoặc thanh điều hướng.
3. Thêm phát lại audio và đánh giá trực tiếp trong từng bản ghi.
4. Thêm ngày/nhóm theo ngày, làm mới và bộ lọc cơ bản.
5. Bổ sung metadata kỹ thuật trong màn hình chi tiết, không nhồi vào danh sách chính.
6. Chuyển lịch sử production sang database có user/device ID và phân trang; đặt chính sách retention.
7. Bổ sung unit/widget/integration test cho toàn bộ luồng lịch sử.

## Giới hạn bằng chứng

- Đã kiểm tra dữ liệu backend thật và giao diện emulator thật.
- Chưa kiểm tra TalkBack, điện thoại thật, nhiều tài khoản, nhiều server instance hoặc lịch sử sau khi triển khai production.
