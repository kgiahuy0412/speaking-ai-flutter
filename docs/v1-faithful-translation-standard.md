# TIÊU CHUẨN DỊCH TRUNG THÀNH V1

## 1. Mục tiêu

V1 phải chuyển câu tiếng Việt trẻ nói thành một câu tiếng Anh tự nhiên, đúng ngữ pháp và giữ nguyên nội dung có trong câu gốc.

Hệ thống không được chỉ hiểu ý tổng quát rồi viết lại thành một câu khác. Cùng một tiêu chuẩn này được áp dụng cho:

- Kết quả do AI tạo.
- Bản dịch được lưu trong rule.
- Kết quả do quản trị viên duyệt hoặc chỉnh sửa.
- Dữ liệu được đưa vào text cache và audio cache.

## 2. Định nghĩa “dịch trung thành”

Một bản dịch được chấp nhận khi giữ đầy đủ các thành phần có ý nghĩa trong câu tiếng Việt:

1. Người nói và người được nhắc đến: con, mình, chúng con, bố, mẹ, ông, bà, anh, chị và các chủ thể khác.
2. Người được gọi hoặc người nhận lời nói: “Mẹ ơi”, “Bố ơi”, “Cô ơi” và các cách xưng hô tương đương.
3. Loại câu: khẳng định, câu hỏi, yêu cầu, nhờ vả, xin phép, mong muốn, từ chối hoặc mệnh lệnh.
4. Phủ định và mức độ: không, chưa, đừng, không muốn, không thích, rất, hơi và các thành phần tương tự.
5. Hành động, đối tượng, số lượng, sở hữu, địa điểm và thời gian được nói rõ trong câu.
6. Nội dung thực sự có trong câu, kể cả khi câu nói ngắn, chưa hoàn chỉnh hoặc mang đặc điểm khẩu ngữ.

Bản dịch có thể diễn đạt tự nhiên theo ngữ pháp tiếng Anh nhưng không được làm thay đổi các thông tin trên.

## 3. Những hành vi không được chấp nhận

Hệ thống không được:

- Tóm tắt câu nói.
- Viết lại thành một ý gần giống.
- Bỏ lời gọi hoặc đổi người được gọi.
- Đổi chủ thể, ví dụ từ “con” thành “we”.
- Biến câu kể thành câu hỏi hoặc ngược lại.
- Làm mất hoặc tự thêm ý phủ định.
- Tự trả lời câu hỏi của trẻ.
- Tự thêm vật, người, số lượng, địa điểm, thời gian hoặc lý do không có trong câu gốc.
- Thêm lời khuyên, giải thích hoặc nhận xét.
- Tự làm câu “lịch sự hơn” nếu việc đó thay đổi loại câu hoặc ý của trẻ.
- Ép câu mới vào một câu mẫu chỉ vì có chung một vài từ hoặc gần giống về ngữ nghĩa.

Yêu cầu “câu tiếng Anh tự nhiên” chỉ cho phép điều chỉnh trật tự từ và cấu trúc ngữ pháp cần thiết trong tiếng Anh; không cho phép sửa ý của trẻ.

## 4. Ví dụ chuẩn bắt buộc

### Ví dụ 1 — Mong muốn

- Tiếng Việt: Mẹ ơi, con muốn mua cái này.
- Chấp nhận: Mom, I want to buy this.
- Không chấp nhận: Can we buy this?
- Lý do: Bản không chấp nhận bỏ lời gọi, đổi chủ thể và biến câu kể thành câu hỏi.

### Ví dụ 2 — Xin phép

- Tiếng Việt: Mẹ ơi, mình mua cái này được không?
- Chấp nhận: Mom, can we buy this?
- Không chấp nhận: I want to buy this.
- Lý do: Câu gốc là câu hỏi xin phép, không phải câu kể về mong muốn.

### Ví dụ 3 — Phủ định

- Tiếng Việt: Con không muốn mua cái này.
- Chấp nhận: I don't want to buy this.
- Không chấp nhận: I want to buy this.
- Lý do: Bản không chấp nhận làm mất phủ định.

### Ví dụ 4 — Nhờ vả

- Tiếng Việt: Bố mua cái này cho con nhé.
- Chấp nhận: Dad, please buy this for me.
- Không chấp nhận: Can we buy this?
- Lý do: Câu gốc nhờ bố thực hiện hành động, không phải câu hỏi về hành động chung.

### Ví dụ 5 — Hỏi thông tin

- Tiếng Việt: Mẹ ơi, hôm nay mình đi đâu vậy?
- Chấp nhận: Mom, where are we going today?
- Không chấp nhận: Let's go somewhere today.
- Lý do: Không được đổi câu hỏi thành lời đề nghị.

### Ví dụ 6 — Từ chối

- Tiếng Việt: Con không ăn món này đâu.
- Chấp nhận: I won't eat this dish.
- Không chấp nhận: I don't like this dish.
- Lý do: Câu gốc thể hiện việc không ăn, không khẳng định trẻ không thích món ăn.

### Ví dụ 7 — Chưa xảy ra

- Tiếng Việt: Con chưa làm bài tập xong.
- Chấp nhận: I haven't finished my homework yet.
- Không chấp nhận: I didn't do my homework.
- Lý do: “Chưa xong” khác với “không làm”.

### Ví dụ 8 — Số lượng

- Tiếng Việt: Con muốn hai cái bánh.
- Chấp nhận: I want two cakes.
- Không chấp nhận: I want a cake.
- Lý do: Phải giữ nguyên số lượng.

### Ví dụ 9 — Sở hữu

- Tiếng Việt: Đây là đồ chơi của em con.
- Chấp nhận: This is my younger sibling's toy.
- Không chấp nhận: This is my toy.
- Lý do: Không được thay đổi người sở hữu.

### Ví dụ 10 — Câu chưa hoàn chỉnh

- Tiếng Việt: Mẹ ơi, cái này...
- Chấp nhận: Mom, this...
- Không chấp nhận: Mom, I want this.
- Lý do: Không được tự suy luận mong muốn chưa được trẻ nói ra.

## 5. Quy tắc xử lý cách xưng hô

Tiếng Việt có cách xưng hô phụ thuộc quan hệ và ngữ cảnh. V1 áp dụng các nguyên tắc sau:

- Khi trẻ dùng “con” để tự xưng, ưu tiên dịch là “I”, không dịch máy móc thành “child”.
- Khi “mình” chỉ nhóm gồm trẻ và người đối thoại, có thể dịch là “we”.
- Khi “mình” dùng để tự xưng, phải dựa trên chính câu nói hoặc ngữ cảnh rõ ràng; không được tự đổi thành “we”.
- Lời gọi bố, mẹ, ông, bà, cô, chú phải được giữ lại khi xuất hiện rõ trong câu.
- Nếu không đủ dữ liệu để xác định quan hệ, không được tự tạo thêm quan hệ mới.

Trường hợp xưng hô còn mơ hồ phải được đưa vào bộ kiểm thử riêng trước khi chấp nhận làm rule.

## 6. Quy tắc đối với câu nói khẩu ngữ và nhận dạng giọng nói

- Có thể bỏ âm đệm không mang nghĩa như một tiếng “ừm” đứng riêng, nếu việc bỏ không làm thay đổi thái độ hoặc ý câu.
- Không được tự bỏ “ạ”, “nhé”, “với”, “đi”, “được không” nếu chúng ảnh hưởng đến sắc thái hoặc loại câu.
- Không được tự sửa một từ nhận dạng thành từ khác chỉ dựa trên phỏng đoán. Việc sửa lỗi nhận dạng phải thuộc tầng ASR hoặc có quy tắc đã được kiểm chứng riêng.
- Khi câu nói bị thiếu hoặc đứt đoạn, chỉ dịch phần nội dung nhận dạng được; không tự hoàn thành câu thay trẻ.

## 7. Tiêu chí nghiệm thu bắt buộc

Một bản dịch chỉ được phê duyệt khi trả lời “Đạt” cho toàn bộ câu hỏi sau:

- Chủ thể có được giữ đúng không?
- Người được gọi hoặc người nhận hành động có được giữ đúng không?
- Loại câu có được giữ đúng không?
- Phủ định và mức độ có được giữ đúng không?
- Hành động và đối tượng có được giữ đúng không?
- Số lượng, thời gian, địa điểm và sở hữu có được giữ đúng không?
- Hệ thống có tránh tự thêm thông tin không có trong câu gốc không?
- Câu tiếng Anh có tự nhiên và đúng ngữ pháp không?
- Kết quả có chỉ chứa bản dịch, không kèm giải thích hoặc câu trả lời không?

Chỉ một tiêu chí không đạt cũng khiến bản dịch không được đưa vào rule hoặc cache V1.

## 8. Chỉ số nghiệm thu cho V1

Trên bộ câu kiểm thử đại diện, V1 phải đạt:

- 100% giữ đúng chủ thể và người được gọi.
- 100% giữ đúng phủ định.
- 100% giữ đúng loại câu.
- 100% không tự trả lời hoặc tự thêm thông tin.
- Ít nhất 95% bản dịch được người kiểm duyệt chấp nhận ngay, không cần chỉnh sửa.

Các tiêu chí 100% là điều kiện chặn phát hành. Tỷ lệ trung bình cao không được dùng để bù cho lỗi đổi chủ thể, mất phủ định hoặc đổi loại câu.

## 9. Phạm vi áp dụng cho rule và cache

- Mọi câu tiếng Anh trong rule V1 phải vượt qua danh sách nghiệm thu tại Mục 7.
- Chỉ một câu tiếng Việt khớp toàn bộ rule đã duyệt mới được dùng kết quả có sẵn.
- Một keyword hoặc semantic intent gần giống không được tự động trả bản dịch cuối.
- Kết quả AI chỉ được đưa vào rule sau khi có người duyệt.
- Text cache và audio cache V1 không được tái sử dụng nội dung V0 nếu phiên bản prompt hoặc rule đã thay đổi.

## 10. Quyết định sản phẩm đã chốt

V1 ưu tiên độ chính xác nội dung hơn tỷ lệ cache hit. Khi không chắc chắn giữa việc dùng một rule gần giống và gọi AI dịch trung thành, hệ thống phải chọn dịch trung thành.

Tài liệu này là tiêu chuẩn đầu vào cho các bước tiếp theo: xây prompt V1, thay đổi cách so khớp rule, kiểm duyệt 300–500 câu và thiết kế bộ kiểm thử nghiệm thu.
