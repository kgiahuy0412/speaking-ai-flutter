# Hướng dẫn kiểm thử điều hướng giọng nói “Hey Pico”

> Luồng mặc định hiện đã chuyển sang nút **Main** và câu phản hồi **“Bi cô đây”**. Xem `docs/main-voice-assistant-test-guide.md`. Tài liệu này chỉ áp dụng khi bật lại chế độ nghe liên tục bằng `AUTO_START_VOICE_NAVIGATION=true`.

## 1. Phạm vi kiểm thử

Tài liệu này dùng để kiểm thử luồng điều hướng giọng nói hai bước trên ứng dụng Flutter Android:

1. Người dùng nói **“Hey Pico”**.
2. Ứng dụng dừng nghe và phát **“Pipo nghe đây”**.
3. Sau khi phát xong, ứng dụng bật lại micro.
4. Người dùng nói hành động mong muốn trong vòng **8 giây**.
5. Ứng dụng chuyển đến chức năng tương ứng rồi quay lại trạng thái chờ từ đánh thức.

Tên đánh thức là **Pico**, còn câu phản hồi **“Pipo nghe đây”** là chủ ý theo yêu cầu sản phẩm.

## 2. Bản APK cần kiểm thử

- Loại bản build: Release, kết nối backend production.
- Application ID: `com.innotrik.aispeaking`.
- Phiên bản ứng dụng: `1.0.4+6`.
- Backend: `https://speaking-ai-nextjs-backend-production.up.railway.app`.
- File APK: `build/app/outputs/flutter-apk/app-release.apk`.
- SHA-256 của bản tại thời điểm viết tài liệu:
  `10E056DF5BAD81BB0A175B508393FDA6F846868CDD8017F9D56CEFAE545B4EAA`.

> Lưu ý: máy build hiện chưa có production keystore nên APK release đang được ký bằng Android Debug certificate. APK có thể dùng để QA/cài thử, nhưng chưa phải gói ký chính thức để phát hành Play Store.

## 3. Điều kiện kiểm thử

- Điện thoại Android 7.0 trở lên.
- Có dịch vụ nhận diện giọng nói Android, khuyến nghị Google Speech Services.
- Có giọng đọc tiếng Việt trong Text-to-Speech của Android.
- Có kết nối Internet để dùng backend production.
- Ứng dụng đang mở ở foreground và màn hình điện thoại đang bật.
- Cho phép quyền Micro khi ứng dụng yêu cầu.
- Thực hiện trong phòng tương đối yên tĩnh, giữ điện thoại cách miệng khoảng 30–70 cm.

Tính năng này không được thiết kế để tiếp tục nghe khi ứng dụng chạy nền hoặc màn hình điện thoại đã tắt.

## 4. Cài APK

### Cài trực tiếp

Chép `app-release.apk` vào điện thoại, mở file và cho phép cài ứng dụng từ nguồn này nếu Android yêu cầu.

### Cài bằng ADB

```powershell
adb install -r "D:\Code\HuaMei\App_noi\flutter\9_12th8\speaking-ai-flutter\build\app\outputs\flutter-apk\app-release.apk"
```

Nếu Android báo xung đột chữ ký với bản đã cài, cần gỡ bản cũ trước. Thao tác này xóa dữ liệu ứng dụng trên máy:

```powershell
adb uninstall com.innotrik.aispeaking
adb install "D:\Code\HuaMei\App_noi\flutter\9_12th8\speaking-ai-flutter\build\app\outputs\flutter-apk\app-release.apk"
```

## 5. Kiểm thử nhanh bắt buộc

### TC-01: Đánh thức và mở Từ vựng

1. Mở ứng dụng và đứng tại màn hình Giao tiếp.
2. Nói rõ: **“Hey Pico”**.
3. Chờ ứng dụng nói xong: **“Pipo nghe đây”**.
4. Nói: **“Con muốn học từ vựng”**.

Kết quả mong đợi:

- Ứng dụng chỉ phản hồi một lần.
- Micro không tự nhận câu “Pipo nghe đây”.
- Ứng dụng chuyển đến màn hình Từ vựng.
- Không bắt đầu luồng dịch câu của nút “Nói”.

### TC-02: Mở Chủ đề

1. Nói: **“Hey Pico”**.
2. Chờ câu **“Pipo nghe đây”** kết thúc.
3. Nói: **“Con muốn học chủ đề”**.

Kết quả mong đợi: màn hình Chủ đề được mở.

### TC-03: Chuyển trang khi đang ở Chủ đề

1. Đang ở màn hình danh sách Chủ đề hoặc danh sách bài học.
2. Nói: **“Hey Pico”**.
3. Sau lời đáp, nói: **“Con muốn học từ vựng”**.

Kết quả mong đợi:

- Màn hình Chủ đề được đóng.
- Màn hình Từ vựng hiển thị.
- Không có hai màn hình hoặc hai hộp thoại mở chồng lên nhau.

### TC-04: Trở về Giao tiếp

1. Đang ở Từ vựng hoặc Chủ đề.
2. Nói: **“Hey Pico”**.
3. Sau lời đáp, nói: **“Mở giao tiếp”** hoặc **“Con muốn luyện giao tiếp”**.

Kết quả mong đợi: ứng dụng trở về màn hình Giao tiếp.

### TC-05: Mở Lịch sử

1. Nói: **“Hey Pico”**.
2. Sau lời đáp, nói: **“Mở lịch sử”**.

Kết quả mong đợi:

- Hộp Lịch sử được mở.
- Luồng nghe điều hướng tạm dừng trong khi hộp Lịch sử đang mở.
- Sau khi đóng Lịch sử, ứng dụng quay lại chờ “Hey Pico”.

### TC-06: Mở Cài đặt

1. Nói: **“Hey Pico”**.
2. Sau lời đáp, nói: **“Mở cài đặt”**.

Kết quả mong đợi:

- Hộp Cài đặt được mở.
- Luồng nghe điều hướng tạm dừng khi Cài đặt đang mở.
- Sau khi đóng Cài đặt, ứng dụng quay lại chờ “Hey Pico”.

## 6. Các câu có thể dùng để test

| Chức năng | Câu thử nghiệm |
|---|---|
| Từ vựng | “Con muốn học từ vựng” |
| Từ vựng | “Mở kho từ vựng cho con” |
| Từ vựng | “Học từ mới” |
| Chủ đề | “Con muốn học chủ đề” |
| Chủ đề | “Con muốn luyện nghe theo chủ đề” |
| Chủ đề | “Mở chủ đề” |
| Vào bài theo tên chủ đề | “Mở bài 1 trong chủ đề Gia đình và ngôi nhà” |
| Vào bài theo số chủ đề | “Mở bài đầu tiên trong chủ đề số 3” |
| Vào bài trong chủ đề hiện tại | “Mở bài 2” |
| Giao tiếp | “Mở giao tiếp” |
| Giao tiếp | “Con muốn luyện giao tiếp” |
| Giao tiếp | “Con muốn nói chuyện” |
| Lịch sử | “Mở lịch sử” |
| Lịch sử | “Xem lịch sử gần đây” |
| Lịch sử | “Cho con xem câu đã học” |
| Cài đặt | “Mở cài đặt” |
| Cài đặt | “Mở thiết lập” |
| Cài đặt | “Con muốn đổi giao diện” |

Trước mỗi câu hành động trong bảng, phải nói **“Hey Pico”** và chờ lời đáp kết thúc.

Với lệnh vào bài học:

- Nếu nói đủ tên hoặc số chủ đề, ứng dụng mở đúng chủ đề rồi đi thẳng vào bài.
- Nếu đang ở danh sách bài của một chủ đề, có thể chỉ nói “Mở bài 1”, “Mở bài 2”, v.v.
- Nếu chỉ nói số bài khi chưa chọn chủ đề, ứng dụng dùng chủ đề “Tiếp tục học”.
- Nếu chủ đề không có số bài được yêu cầu, ứng dụng giữ danh sách bài và hiện thông báo thay vì mở nhầm bài.

Các biến thể từ đánh thức hiện được hỗ trợ để chịu lỗi ASR:

- “Hey Pico”
- “Hay Pico”
- “Hey Piko”
- “Hey Pipo”
- “Hey Pi Cô”
- “Hay Pi Cô”
- “Hey Bi Cô”
- “Hay Bi Cô”
- “Ê Pi Cô”
- “Hey Bigo”

Ứng dụng kiểm tra tối đa ba phương án phiên âm do Android trả về. Vì vậy, nếu
phương án đầu nghe sai “Hey Pico” nhưng phương án sau nhận đúng hoặc gần đúng,
luồng đánh thức vẫn có thể phản hồi.

## 7. Kiểm thử chống nhận sai

### TC-07: Nói hành động khi chưa đánh thức

Nói trực tiếp **“Con muốn học từ vựng”** mà không nói “Hey Pico”.

Kết quả mong đợi: ứng dụng không chuyển trang và không đưa câu này vào tính năng “Nói”.

### TC-08: Nói cả hai bước trong một câu

Nói liền: **“Hey Pico, con muốn học từ vựng”**.

Kết quả mong đợi:

- Ứng dụng phản hồi “Pipo nghe đây”.
- Phần hành động trong cùng lượt nói không được thực hiện.
- Người dùng phải nói lại hành động sau khi lời đáp kết thúc.

Đây là hành vi có chủ ý để tránh micro nhận lẫn lời đáp và câu hành động.

### TC-09: Hết thời gian chờ hành động

1. Nói “Hey Pico”.
2. Sau lời đáp, không nói gì trong hơn 8 giây.
3. Nói “Con muốn học từ vựng”.

Kết quả mong đợi: ứng dụng không chuyển trang vì cửa sổ nhận lệnh đã hết; cần nói lại “Hey Pico”.

### TC-10: Từ đánh thức không đầy đủ

Lần lượt nói: **“Pico”**, **“Hey”**, hoặc một câu hội thoại bình thường có từ gần giống.

Kết quả mong đợi: ứng dụng không phát “Pipo nghe đây”.

## 8. Kiểm thử không chồng chéo với nút “Nói”

### TC-11: Bấm Nói khi ứng dụng đang chờ Hey Pico

1. Đứng ở màn hình Giao tiếp.
2. Bấm nút **Nói** ngay khi luồng nghe nền đang hoạt động.
3. Nói một câu tiếng Việt và kết thúc lượt ghi âm.

Kết quả mong đợi:

- Luồng Hey Pico giải phóng micro trước khi luồng Nói bắt đầu.
- Chỉ một luồng sử dụng micro tại một thời điểm.
- Câu nói được xử lý bởi tính năng Giao tiếp, không bị hiểu là lệnh điều hướng.
- Sau khi xử lý/phát âm thanh hoàn tất, ứng dụng quay lại chờ “Hey Pico”.

### TC-12: Bấm Nói trong lúc Pipo đang phản hồi

1. Nói “Hey Pico”.
2. Trong lúc đang nghe “Pipo nghe đây”, bấm nút Nói.

Kết quả mong đợi:

- Âm thanh phản hồi được dừng hoặc hoàn tất an toàn.
- Không treo ứng dụng, không xuất hiện lỗi micro đang được sử dụng.
- Luồng Nói được ưu tiên và có thể ghi âm bình thường.

### TC-13: Phát âm thanh bài học

1. Mở Chủ đề, chọn một bài học có phát âm thanh hoặc ghi âm.
2. Trong lúc bài học đang phát/thu âm, nói “Hey Pico”.

Kết quả mong đợi: điều hướng giọng nói tạm dừng trong luồng bài học, không chen vào audio hoặc giành micro.

Sau khi thoát toàn bộ luồng bài học về danh sách Chủ đề, nói lại “Hey Pico”. Kết quả mong đợi: tính năng hoạt động trở lại.

## 9. Kiểm thử vòng đời ứng dụng

### TC-14: Đưa ứng dụng xuống nền

1. Đang ở màn hình chính, bấm Home để đưa ứng dụng xuống nền.
2. Nói “Hey Pico”.

Kết quả mong đợi: ứng dụng không phản hồi khi chạy nền.

3. Mở lại ứng dụng.
4. Chờ khoảng một giây rồi nói “Hey Pico”.

Kết quả mong đợi: luồng nghe hoạt động trở lại.

### TC-15: Tắt màn hình

1. Khi ứng dụng đang mở, khóa/tắt màn hình điện thoại.
2. Nói “Hey Pico”.

Kết quả mong đợi: ứng dụng không phản hồi. Sau khi mở màn hình và đưa ứng dụng về foreground, tính năng hoạt động trở lại.

## 10. Tiêu chí đạt tổng thể

- Nhận “Hey Pico” ổn định ở khoảng cách kiểm thử thông thường.
- Chỉ phát “Pipo nghe đây” một lần cho mỗi lần đánh thức.
- Không bật micro nhận lệnh trước khi TTS phát xong.
- Câu hành động hợp lệ được thực hiện trong cửa sổ 8 giây.
- Câu hành động không có từ đánh thức bị bỏ qua.
- Không có hai phiên nhận diện/ghi âm hoạt động cùng lúc.
- Không tự điều hướng bởi tiếng phát ra từ loa ứng dụng.
- Điều hướng vẫn hoạt động ở Giao tiếp, Từ vựng, danh sách Chủ đề và danh sách bài học.
- Điều hướng tạm dừng đúng lúc có phát/thu âm, overlay, ứng dụng nền hoặc màn hình tắt.
- Không crash, treo hoặc xuất hiện lỗi quyền micro sau nhiều vòng lặp.

Khuyến nghị lặp lại TC-01 → TC-06 ít nhất 5 vòng liên tiếp trên mỗi thiết bị kiểm thử.

## 11. Ghi nhận lỗi

Với mỗi lỗi, ghi lại:

- Mã test case.
- Model điện thoại và phiên bản Android.
- Màn hình ứng dụng tại thời điểm xảy ra lỗi.
- Câu người dùng đã nói chính xác.
- Ứng dụng có phát “Pipo nghe đây” hay không.
- Khoảng thời gian chờ trước khi nói hành động.
- Kết quả thực tế.
- Video quay màn hình và logcat nếu có.

Thu log bằng ADB:

```powershell
adb logcat -c
adb logcat -v time > hey-pico-test.log
```

Sau khi tái hiện lỗi, nhấn `Ctrl+C` để dừng thu log.

Có thể lọc log của ứng dụng:

```powershell
adb logcat -v time | Select-String "aispeaking|SpeechRecognizer|TextToSpeech|AudioRecord"
```

## 12. Mẫu báo cáo nhanh

| Mã | Thiết bị | Kết quả | Thời gian phản hồi | Ghi chú |
|---|---|---|---|---|
| TC-01 |  | Pass/Fail |  |  |
| TC-02 |  | Pass/Fail |  |  |
| TC-03 |  | Pass/Fail |  |  |
| TC-04 |  | Pass/Fail |  |  |
| TC-05 |  | Pass/Fail |  |  |
| TC-06 |  | Pass/Fail |  |  |
| TC-07 |  | Pass/Fail |  |  |
| TC-08 |  | Pass/Fail |  |  |
| TC-09 |  | Pass/Fail |  |  |
| TC-10 |  | Pass/Fail |  |  |
| TC-11 |  | Pass/Fail |  |  |
| TC-12 |  | Pass/Fail |  |  |
| TC-13 |  | Pass/Fail |  |  |
| TC-14 |  | Pass/Fail |  |  |
| TC-15 |  | Pass/Fail |  |  |
