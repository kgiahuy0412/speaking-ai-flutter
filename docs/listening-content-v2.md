# Listening Content V2

Nguồn chuẩn hiện tại là `Bo_noi_dung_hoc_tieng_Anh_APP.docx`. Catalog chạy trong Flutter nằm tại `assets/data/listening_lessons.json` và được tạo lại bằng:

```powershell
C:\Users\Windows\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool\generate_listening_content.py `
  "C:\Users\Windows\Downloads\Bo_noi_dung_hoc_tieng_Anh_APP.docx" `
  assets\data\listening_lessons.json
```

## Ba loại nội dung

- `standard`: luyện từng câu cho bài thông thường.
- `dialogue`: luyện từng lượt thoại; UI hiển thị vai nói và trang ôn tập phát hội thoại tiếng Anh hoàn chỉnh khi có `fullAudioUrl`.
- `song`: luyện từng dòng; trang ôn tập phát bài hát tiếng Anh hoàn chỉnh khi có `fullAudioUrl`.

## Gắn audio Cloudinary

Mỗi câu có mã duy nhất và hai trường audio độc lập:

```json
{
  "id": "A035_T01_L01_S01",
  "englishAudioId": "A035_T01_L01_S01_EN",
  "vietnameseAudioId": "A035_T01_L01_S01_VI",
  "audioUrl": "https://res.cloudinary.com/.../A035_T01_L01_S01_EN.mp3",
  "vietnameseAudioUrl": "https://res.cloudinary.com/.../A035_T01_L01_S01_VI.mp3"
}
```

`audioUrl` tự phát ở đầu câu và khi bấm **Nghe mẫu**. `vietnameseAudioUrl` chỉ phát khi bấm **Nghe tiếng Việt**. Bài hội thoại/bài hát có thể gắn thêm `fullAudioUrl`; lời mở đầu và kết bài dùng `introAudioUrl`/`outroAudioUrl`.

## Quy tắc trải nghiệm V1

- Không thao tác 5 giây: popup robot nhắc lần một trong khoảng 3 giây; thêm 5 giây: popup nhắc lần hai trong khoảng 3 giây và hiện **Bỏ qua câu này**. Ứng dụng không tự bỏ qua.
- Bản ghi thành công mới được đưa vào lịch sử. Mỗi câu giữ ba bản mới nhất; lần thứ tư xóa bản cũ nhất. Bản ghi lỗi không làm mất bản trước.
- Sau khi ghi thành công, popup robot chúc mừng xuất hiện khoảng 3 giây, bản ghi được giữ ở đúng câu hiện tại và không tự chuyển. Trẻ chủ động chọn nghe mẫu, nghe bản ghi, ghi lại hoặc sang câu/ôn tập.
- Trường `autoAdvanceMs` vẫn được giữ trong catalog để tương thích dữ liệu cũ nhưng giao diện V2 không sử dụng tự chuyển câu.
- Trang ôn tập chỉ hiển thị tiếng Anh, phát từng câu cách nhau 2 giây và cho thử lại nhẹ nhàng các câu chưa ghi âm. Nút **Hoàn thành bài** bị khóa/mờ trong 6 giây đầu để trẻ không bỏ qua toàn bộ phần ôn tập.

## Phạm vi lưu trữ hiện tại

Tiến độ, trạng thái bỏ qua và ba bản ghi gần nhất được lưu cục bộ trên Android/iOS/desktop. Flutter Web dùng `localStorage` cho metadata và phát lại URL bản ghi trong phiên trình duyệt hiện tại. Để giữ file sau khi tải lại trang hoặc dùng chung nhiều thiết bị, cần nối API upload/Cloudinary hoặc IndexedDB; server vẫn phải áp dụng giới hạn ba bản/câu.
