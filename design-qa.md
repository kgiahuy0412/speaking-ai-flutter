# Design QA — Luồng luyện nghe theo chủ đề

## Comparison target

- Mẫu danh sách bài và lời mở đầu: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-5db6e79d-c118-4910-9712-b611729ba379.png` — 863 × 860 px.
- Mẫu luyện từng câu: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-3b40f415-bea1-492a-979e-656aa40f5172.png` — 421 × 836 px.
- Màn hoàn thành trước khi cải thiện: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-e2481a72-d554-45fc-9783-2a49933bb4ce.png` — 508 × 511 px.
- Flutter render: 390 × 844 logical px cho mỗi màn hình, tiếng Việt, nhóm 3–5 tuổi, chủ đề “Xin chào và tạm biệt”, bài “Chào hỏi cơ bản”, chưa có tiến độ.
- Golden đầy đủ:
  - `test/features/listening/goldens/topic-lesson-journey-390x844.png`
  - `test/features/listening/goldens/lesson-intro-390x844.png`
  - `test/features/listening/goldens/lesson-practice-390x844.png`
  - `test/features/listening/goldens/lesson-completion-390x844.png`
- So sánh cùng khung, đã chuẩn hóa theo chiều rộng:
  - `artifacts/design-qa/lesson-flow/comparison-topic-journey-and-intro.png`
  - `artifacts/design-qa/lesson-flow/comparison-sentence-practice.png`
  - `artifacts/design-qa/lesson-flow/comparison-completion-celebration.png`

## Findings

Không còn khác biệt P0, P1 hoặc P2 cần xử lý.

- Bố cục và phân cấp: giữ đúng ba bước của mẫu đã chọn: hành trình bài nhỏ → lời mở đầu tự động → luyện từng câu. Nút hành động chính, số câu và tiến độ luôn ở vị trí dễ thấy.
- Hình ảnh và nhận diện: dùng đúng ảnh chủ đề trẻ em, mascot robot và sân khấu tím. Mascot ở màn mở đầu đã được tăng tỷ lệ để gần mẫu hơn nhưng không che nội dung.
- Nội dung: màn đầu hiển thị đúng 1 bài nhỏ/8 câu; màn luyện bắt đầu bằng “Hello!”/“Xin chào!”. Toàn bộ catalog Word đã được chuẩn hóa thành 5 nhóm tuổi, 50 chủ đề, 111 bài nhỏ và 836 câu.
- Audio: cấu trúc dữ liệu đã có URL intro, outro, audio tiếng Anh và audio tiếng Việt để nối Cloudinary sau này. Khi chưa có URL, giao diện báo trạng thái rõ ràng. Bản ghi của trẻ được lưu cục bộ và có thể phát lại.
- Tiến độ: tách riêng số câu đã hoàn thành và vị trí đang học. Vị trí hiện tại được ghi đè chính xác khi đi tới, quay lại, thoát hoặc chọn luyện lại; tiến độ hoàn thành cao nhất vẫn được giữ để tổng hợp chủ đề.
- Điều hướng trong bài: nút back trên cùng chỉ thoát khỏi bài; hàng hành động dưới có nút “Câu trước” độc lập và nút “Tiếp tục/Hoàn thành”. “Câu trước” tự vô hiệu hóa ở câu 1.
- Chúc mừng: màn hoàn thành dùng mascot lớn, chuyển động nảy nhẹ và các biểu tượng lễ hội chuyển động; hai hành động “Về chủ đề” và “Luyện lại từ đầu” rõ ràng hơn mẫu cũ.
- Responsive/accessibility: hành trình học và bài luyện cuộn được; lời mở đầu chuyển sang bố cục cuộn khi màn hình thấp. Kiểm tra 320 × 568 ở text scale 130% không có overflow; vùng bấm chính tối thiểu 48 px.
- Màu sắc/typography: giữ indigo–lavender của ứng dụng hiện tại, Roboto rõ nét, độ tương phản đủ mạnh cho tiêu đề, nút và nội dung song ngữ.

## Comparison history

### Iteration 1

- P2: ảnh trong golden ban đầu chưa kịp tải nên khung chủ đề và sân khấu bị trống.
- Fix: preload ảnh chủ đề, mascot và sân khấu trước khi chụp; bằng chứng sau sửa có đủ tài sản thật.

### Iteration 2

- P2: hàng “1 bài nhỏ / 8 câu” tràn ngang trên màn hình 390 px; metadata bài học tràn ở màn hình hẹp.
- Fix: chia hai nhóm thông tin bằng `Expanded`, rút gọn “Khoảng 3 phút” thành “3 phút”, và dùng tỷ lệ thẻ thích ứng.

### Iteration 3

- P2: màn lời mở đầu dùng `Column` cố định nên có thể tràn trên điện thoại 320 × 568 khi tăng cỡ chữ.
- Fix: dùng vùng cuộn có chiều cao tối thiểu và bố cục nội tại; kiểm tra compact flow đã qua.

### Iteration 4

- P2: nhãn “Tiếp tục” trong golden không lấy đúng font đậm và hiện ký tự khuyết.
- Fix: chỉ định Roboto cho nút hành động; golden sau sửa hiển thị đầy đủ tiếng Việt.

### Iteration 5

- P1: vị trí tiếp tục trước đây dùng chung với tiến độ hoàn thành dạng chỉ tăng, nên “Luyện lại từ đầu” không thể lưu lại câu 1.
- Fix: thêm khóa `current-sentence` riêng có thể tiến, lùi hoặc đặt lại 0; dữ liệu hoàn thành vẫn chỉ tăng và không bị mất.

### Iteration 6

- P2: bài luyện chỉ có nút tiến tới; nút back trên cùng vừa mang nghĩa thoát vừa dễ bị hiểu thành quay về câu trước.
- Fix: thêm nút “Câu trước” cạnh “Tiếp tục”, còn back trên cùng chỉ lưu vị trí rồi thoát.

### Iteration 7

- P2: màn chúc mừng cũ nhỏ và tĩnh, chưa tạo cảm giác hoàn thành rõ rệt cho trẻ.
- Fix: tăng đáng kể mascot và tiêu đề, thêm chuyển động pulse/bounce cùng icon lễ hội, đồng thời cho phép cuộn trên màn hình thấp. So sánh trước/sau đã được kiểm tra trong cùng một composite.

## Follow-up polish

- P3: khi Cloudinary có audio thật, có thể thay biểu tượng waveform tĩnh bằng waveform lấy từ biên độ file và hiển thị thời lượng chính xác. Đây không phải lỗi chặn luồng hiện tại.

## Verification

- `flutter analyze --no-pub`: passed, không có issue.
- Full Flutter test suite: 60 tests passed.
- Bốn golden cho hành trình, intro, luyện từng câu và hoàn thành: passed.
- Golden trang chủ đề tổng: passed với ảnh thật và số bài thật.
- Compact flow và màn hoàn thành 320 × 568, text scale 130%: passed.

final result: passed
