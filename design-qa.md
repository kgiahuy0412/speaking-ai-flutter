# Design QA — Listening Content V2

## Comparison target

- Sơ đồ nội dung mới: `C:\Users\Windows\Downloads\SO_DO_TONG_HOP_CHU_DE_BAI_HOC_BAI_HAT.png`.
- Mẫu hành trình và lời mở đầu đã được chọn: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-5db6e79d-c118-4910-9712-b611729ba379.png`.
- Mẫu luyện từng câu đã được chọn: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-3b40f415-bea1-492a-979e-656aa40f5172.png`.
- Màn hoàn thành cũ dùng để so sánh cải thiện: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-e2481a72-d554-45fc-9783-2a49933bb4ce.png`.
- Flutter render: 390 × 844 logical px, tiếng Việt, nhóm 3–5 tuổi, chủ đề “Xin chào và tạm biệt”.
- Golden:
  - `test/features/listening/goldens/topic-lesson-journey-390x844.png`
  - `test/features/listening/goldens/lesson-intro-390x844.png`
  - `test/features/listening/goldens/lesson-practice-390x844.png`
  - `test/features/listening/goldens/lesson-reminder-popup-390x844.png`
  - `test/features/listening/goldens/lesson-praise-popup-390x844.png`
  - `test/features/listening/goldens/lesson-review-390x844.png`
  - `test/features/listening/goldens/lesson-completion-390x844.png`
- Composite cùng khung:
  - `artifacts/design-qa/lesson-flow/comparison-topic-journey-and-intro.png`
  - `artifacts/design-qa/lesson-flow/comparison-sentence-practice.png`
  - `artifacts/design-qa/lesson-flow/comparison-content-structure-and-review.png`
  - `artifacts/design-qa/lesson-flow/comparison-completion-celebration.png`
  - `artifacts/design-qa/lesson-flow/comparison-practice-popups.png`
  - `artifacts/design-qa/lesson-flow/comparison-review-lock.png`

## Findings

Không còn khác biệt P0, P1 hoặc P2 cần xử lý.

- Phân cấp và nhận diện: giữ đúng indigo–lavender, Roboto, mascot robot và ảnh chủ đề đã được duyệt. Hành trình bài nhỏ, CTA, số câu và tiến độ có độ ưu tiên rõ.
- Catalog: Word mới đã được chuẩn hóa thành 5 nhóm tuổi, 50 chủ đề, 101 bài thông thường, 634 câu, 11 bài hát với 69 dòng lời. Mỗi câu có ID cùng audio ID EN/VI riêng.
- Ba luồng: bài thường dùng thẻ luyện câu; hội thoại thêm vai nói và phát bản đầy đủ ở ôn tập; bài hát có khu vực riêng, icon nhạc, luyện từng dòng và full-audio hook.
- Luyện câu: hai nút “Nghe mẫu”/“Nghe tiếng Việt” cân bằng, không lẫn chức năng. Sau ghi thành công, robot và icon trang trí chuyển động trong popup chúc mừng 3 giây; bản ghi mới nhất cùng bốn hành động vẫn nằm trong luồng cuộn.
- Chờ tương tác: sau 5 giây hiện popup robot nhắc lần một trong 3 giây; thêm 5 giây hiện popup lần hai và mới mở bỏ qua. Không tự bỏ qua và trạng thái “Chưa ghi âm” được giữ trong tiến độ.
- Điều hướng câu: ghi âm xong giữ nguyên câu hiện tại ở mọi nhóm tuổi, không còn tự chuyển. Trẻ chủ động bấm “Câu tiếp theo” hoặc “Ôn tập”; nút “Câu trước” vẫn độc lập với nút back thoát bài.
- Ôn tập: chỉ hiển thị tiếng Anh, đánh dấu nhẹ nhàng câu chưa ghi âm, có thử lại và tự phát tuần tự cách nhau 2 giây. Nút hoàn thành mờ và bị khóa đủ 6 giây; layout cuộn được trên màn hình thấp.
- Hoàn thành: mascot lớn, chuyển động nhẹ, CTA “Về chủ đề” và “Luyện lại từ đầu” rõ, phù hợp trẻ nhỏ.
- Lịch sử: UI chỉ hiện bản mới nhất trong bài; lịch sử gần đây cho phép nghe lại và giới hạn ba bản thành công/câu. Bản lỗi không thay thế bản cũ.
- Responsive: các màn hình chính và ôn tập dùng vùng cuộn, vùng bấm chính tối thiểu 48 px; kiểm tra 320 × 568 ở text scale 130% không overflow.

## Comparison history

### Iteration 1

- P1: catalog cũ không còn khớp Word mới và chưa có lesson type/audio ID.
- Fix: parser V2 đọc trực tiếp DOCX, xác thực tổng số, ID duy nhất và tách standard/dialogue/song.

### Iteration 2

- P1: bản ghi trước bị ghi đè ngay khi bắt đầu ghi lại.
- Fix: tạo file timestamp riêng, chỉ thêm lịch sử sau khi ghi thành công, rồi mới xóa bản thứ tư.

### Iteration 3

- P1: kết thúc bài đi thẳng tới chúc mừng, thiếu bước ôn tập.
- Fix: câu cuối dùng “Ôn tập”, mở danh sách English-only và chỉ hoàn thành sau CTA cuối danh sách.

### Iteration 4

- P2: trang ôn tập dùng cột cố định gây overflow trên 320 × 568 và timer 2 giây còn chạy sau khi thoát.
- Fix: chuyển toàn bộ trang sang vùng cuộn và dùng timer có thể hủy/complete khi dispose.

### Iteration 5

- P2: thông báo đếm ngược sau ghi bị tràn ngang.
- Fix: cho nội dung co giãn, căn giữa và hỗ trợ tối đa hai dòng.

### Iteration 6

- P2: Flutter Web không tìm lại URL bản ghi trong phiên.
- Fix: giữ URL hợp lệ cho lịch sử trong phiên và thu hồi blob URL khi bản cũ bị loại.

### Iteration 7

- P2: tự chuyển sau ghi khiến trẻ chưa kịp nghe lại; banner động viên còn nhỏ và nút hoàn thành ôn tập có thể bấm ngay.
- Fix: bỏ tự chuyển ở mọi nhóm tuổi, thay banner bằng popup robot chuyển động tự ẩn sau 3 giây, dùng popup tương tự cho hai lần nhắc và khóa CTA hoàn thành trong 6 giây đầu.

## Follow-up polish

- P3: audio Cloudinary chưa được cung cấp; các trường URL và nút đã sẵn sàng nhưng hiện hiển thị thông báo chờ audio.
- P3: Flutter Web cần API upload/Cloudinary hoặc IndexedDB nếu muốn giữ file bản ghi qua lần tải lại trang và đồng bộ nhiều thiết bị. Android/iOS/desktop đã giữ file cục bộ.
- P3: khi có audio thật, thay waveform tĩnh bằng biên độ thật và kiểm tra timing trên thiết bị trẻ em sử dụng.
- P3: bản web JavaScript release hoạt động; chế độ WebAssembly còn cảnh báo từ `just_audio_web`, nên chưa bật Wasm cho V1.

## Verification

- `flutter analyze --no-pub`: passed.
- Full Flutter suite: 80 tests passed, gồm popup 3 giây, timer nhắc 5+5 giây, không tự chuyển câu, khóa ôn tập 6 giây, skip, ba bản ghi/câu, resume, compact layout và catalog V2.
- Bảy golden của hành trình, intro, luyện câu, hai popup, ôn tập và hoàn thành: passed.
- Flutter Web release build: passed.
- Android debug APK build: passed.

final result: passed
