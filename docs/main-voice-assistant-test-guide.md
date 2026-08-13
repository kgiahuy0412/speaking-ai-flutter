# Hướng dẫn kiểm thử nút Main – trợ lý “Bi cô”

## 1. Luồng hoạt động mặc định

Nút **Main** được cố định ở góc dưới bên phải và xuất hiện trên toàn ứng dụng. Micro không tự nghe khi chỉ mở ứng dụng.

Khi nhấn **Main**, nếu đang ở màn hình con hoặc trong bài học, ứng dụng quay về màn hình chính để dừng an toàn âm thanh và micro đang dùng. Sau đó Bi cô bắt đầu một trong hai luồng dưới đây.

### Luyện nói

| Người nói | Nội dung |
|---|---|
| Bi cô | “Con muốn luyện nói hay học chủ đề nè” |
| Trẻ | “Con muốn luyện nói” |
| Bi cô | “Bắt đầu nói đi con” |

Kết quả mong đợi: ứng dụng chuyển về Giao tiếp và tự động chuẩn bị micro ngay sau khi Bi cô nói xong. Main hiển thị trạng thái của phiên nhưng không cần nhấn thêm.

Sau đó, mỗi lượt luyện nói hoạt động như sau:

1. Khi Main hiển thị **Đang nghe...**, trẻ nói câu cần luyện.
2. Khi trẻ nói xong, ứng dụng tự phát hiện khoảng lặng và dừng ghi âm.
3. Ứng dụng nhận diện giọng nói, dịch nội dung, hiển thị câu gốc và câu đã dịch, rồi phát âm kết quả.
4. Khi phát xong, ứng dụng tự động chuẩn bị micro và mở lượt nói tiếp theo.
5. Nếu trẻ không nói trong 10 giây của một lượt, Bi cô nói “tạm biệt con nhé”, kết thúc Luyện nói và đưa nút về **Main**.

Trong lúc micro đang chờ câu luyện nói, trẻ có thể nói “Còn cái gì khác để học không?”. Đây được xem là lệnh đổi tính năng, không phải câu cần dịch. Bi cô sẽ thoát Luyện nói và hỏi “Có chứ. Con muốn học chủ đề hay học từ vựng nè”.

### Học theo chủ đề

| Người nói | Nội dung |
|---|---|
| Bi cô | “Con muốn luyện nói hay học chủ đề nè” |
| Trẻ | “Con muốn học theo chủ đề” |
| Bi cô | “Con mấy tuổi” |
| Trẻ | “Con 6 tuổi” |
| Bi cô | “Có 10 chủ đề. Con muốn học chủ đề số mấy” |
| Trẻ | “Con muốn học chủ đề số 3” |
| Bi cô | “Có 2 bài học. Con muốn học bài số mấy” |
| Trẻ | “Con học bài số 1” |
| Bi cô | “Bắt đầu học thôi con” |

Với dữ liệu hiện tại, trẻ 6 tuổi thuộc nhóm **6–7 tuổi**; chủ đề số 3 là **Cặp sách và lớp học**, gồm hai bài **Đồ dùng học tập** và **Trong lớp học**. Chọn bài số 1 sẽ mở **Đồ dùng học tập**.

Số chủ đề và số bài học được đếm trực tiếp từ dữ liệu của ứng dụng, không mã hóa cứng. Nếu nội dung được thêm hoặc bớt, câu hỏi của Bi cô tự dùng số lượng mới.

## 2. Các cách nói được hỗ trợ

- Luyện nói: “Con muốn luyện nói”, “Cho con luyện giao tiếp”, “Con muốn nói chuyện”.
- Học chủ đề: “Con muốn học chủ đề”, “Con muốn học theo chủ đề”, “Học chủ đề”.
- Tuổi: có thể nói bằng số hoặc chữ, ví dụ “Con 6 tuổi”, “Con sáu tuổi”.
- Chọn chủ đề: “Chủ đề số 3”, “Con chọn chủ đề ba”, “Con muốn học chủ đề số ba”.
- Chọn bài: “Bài số 1”, “Con học bài một”, “Con chọn bài đầu tiên”.

Ứng dụng hỗ trợ các nhóm tuổi hiện có từ 3 đến 15 tuổi. Nếu tuổi hoặc số thứ tự nằm ngoài dữ liệu, Bi cô sẽ yêu cầu chọn lại trong phạm vi hợp lệ.

## 3. Các ca kiểm thử bắt buộc

### TC-01: Luyện nói

1. Nhấn **Main**.
2. Chờ Bi cô nói hết câu hỏi đầu tiên.
3. Nói “Con muốn luyện nói”.

Kết quả mong đợi: nghe “Bắt đầu nói đi con”, màn hình Giao tiếp được mở và Main tự chuyển qua **Đang chuẩn bị...** rồi **Đang nghe...**. Nói một câu và ngừng nói; ứng dụng phải tự dừng, hiển thị câu gốc, câu dịch và phát âm kết quả.

### TC-02: Lặp lại nhiều lượt Luyện nói

1. Hoàn thành TC-01.
2. Chờ ứng dụng phát xong câu kết quả.
3. Kiểm tra Main tự chuyển qua **Đang chuẩn bị...** rồi **Đang nghe...**.
4. Nói câu thứ hai và ngừng nói, không nhấn Main.

Kết quả mong đợi: lượt thứ hai dùng lại đúng luồng nhận diện, dịch, hiển thị và phát âm; không mở thêm một phiên micro song song.

### TC-03: Tự thoát Luyện nói sau 10 giây

Sau khi nghe “Bắt đầu nói đi con”, hoặc sau khi một kết quả đã phát xong và micro tự mở lại, không nói gì trong ít nhất 10 giây.

Kết quả mong đợi: micro tự dừng, Bi cô nói “tạm biệt con nhé” và Main trở về trạng thái **Main**. Lần nhấn tiếp theo mở lại menu “Con muốn luyện nói hay học chủ đề nè”.

### TC-04: Đổi sang nội dung học khác trong lúc Luyện nói

1. Vào Luyện nói và chờ Main hiển thị **Đang nghe...**.
2. Nói “Còn cái gì khác để học không?”.
3. Sau câu hỏi của Bi cô, thử lần lượt “Con muốn học từ vựng” và “Con muốn học chủ đề”.

Kết quả mong đợi: câu điều khiển không xuất hiện trong ô câu tiếng Việt/tiếng Anh và không phát bản dịch. Bi cô hỏi “Có chứ. Con muốn học chủ đề hay học từ vựng nè”. Chọn Từ vựng sẽ mở trang Từ vựng; chọn Chủ đề sẽ tiếp tục bằng câu hỏi “Con mấy tuổi”.

### TC-05: Đường đi mẫu 6 tuổi

Thực hiện chính xác hội thoại mẫu ở mục 1.

Kết quả mong đợi:

- Sau “Con 6 tuổi”, Bi cô nói có 10 chủ đề.
- Sau “Chủ đề số 3”, màn hình **Cặp sách và lớp học** được mở và Bi cô nói có 2 bài học.
- Sau “Bài số 1”, nghe “Bắt đầu học thôi con” rồi bài **Đồ dùng học tập** được mở.

### TC-06: Nhóm tuổi khác

Lặp lại với tuổi 4, 9, 11 và 14; chọn chủ đề và bài hợp lệ đang hiển thị.

Kết quả mong đợi: ứng dụng chọn lần lượt đúng nhóm 3–5, 8–10, 11–12 và 13–15 tuổi; số lượng được đọc đúng theo dữ liệu từng nhóm/chủ đề.

### TC-07: Số thứ tự không hợp lệ

Ở bước chọn chủ đề, nói “Chủ đề số 15” khi nhóm chỉ có 10 chủ đề. Làm tương tự với số bài lớn hơn số bài hiện có.

Kết quả mong đợi: không mở sai nội dung; Bi cô đọc lại phạm vi hợp lệ và tiếp tục chờ lựa chọn mới.

### TC-08: Không trả lời menu trợ lý

Ở bất kỳ câu hỏi nào, không nói gì trong ít nhất 8 giây.

Kết quả mong đợi: micro dừng, hội thoại Main kết thúc và nút trở lại trạng thái có thể nhấn.

### TC-09: Không chồng chéo

Trong lúc ứng dụng đang nghe, nhận diện, dịch hoặc phát câu trả lời, thử nhấn **Main** nhiều lần.

Kết quả mong đợi: Main bị khóa trong toàn bộ phiên Luyện nói tự động; không có hai phiên nhận diện, hai micro hoặc hai câu TTS chạy cùng lúc.

## 4. Điều kiện và giới hạn

- Cho phép quyền Micro cho ứng dụng.
- Thiết bị cần có dịch vụ nhận diện giọng nói và Text-to-Speech tiếng Việt.
- Chỉ nói câu trả lời khi Bi cô đã nói xong và nút hiển thị **“Đang nghe...”**.
- Mỗi câu hỏi có khoảng 8 giây để nhận câu trả lời.
- Tính năng hoạt động khi ứng dụng đang mở ở foreground và màn hình điện thoại đang bật.
- Khi ứng dụng chạy nền hoặc màn hình đã tắt, luồng này không tiếp tục nghe.
