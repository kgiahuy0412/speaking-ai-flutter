# AIV0 Batch Audio Reviewer

Ứng dụng Windows độc lập dùng PySide6 để quản lý bảng metadata, ghép audio chính thức, theo dõi phiên bản và cập nhật `audio_id`. Project này không phụ thuộc Flutter và không cần back-end riêng.

## Chức năng V0.2

- Mở `.xlsx`, `.csv` và `.tsv`.
- Tạo bảng mẫu 207 bản ghi từ `CV26-TEEN-001` đến `CV26-TEEN-207`.
- Quét cả thư mục con để tìm `.mp3`, `.wav`, `.m4a`, `.aac`, `.ogg`, `.flac`.
- Ghép file bằng `record_id`, `sentence_code`, `draft_filename` hoặc `official_filename`.
- Tạo SHA-256, ID cục bộ và tăng `audio_version` khi nội dung audio thay đổi.
- Cảnh báo file thiếu, không khớp, khớp mơ hồ và file có nội dung trùng.
- Upload các dòng đã chọn tới API multipart và lấy ID từ phản hồi JSON.
- Xuất workbook mới gồm `Samples`, `Upload Log` và `Instructions`.
- Phát, tạm dừng và tua audio ngay trong ứng dụng.
- Đánh dấu `Đạt`, `Không đạt` hoặc `Kiểm thử lại`.
- Chọn nhiều loại lỗi cho một audio, gồm phát âm, vùng miền, độ rõ, tạp âm, ASR và dịch.
- Ghi kết quả thực tế, đề xuất sửa, người kiểm thử và trạng thái sửa.
- Lọc bảng theo kết quả hoặc loại lỗi.
- Sửa hàng loạt các mẫu Không đạt có cùng loại lỗi và chuyển cả nhóm sang Kiểm thử lại.

## Quy tắc dữ liệu

`record_id` là mã cố định của ca kiểm thử. Khi thay audio, chỉ cập nhật `audio_id`, `audio_hash` và `audio_version`; không đổi `record_id`.

Mẫu `Không đạt` phải có ít nhất một loại lỗi. Trường `error_categories` lưu nhiều loại lỗi bằng dấu chấm phẩy. Thao tác **Sửa hàng loạt** chỉ chọn các mẫu đang `Không đạt` và có loại lỗi tương ứng; mỗi thay đổi đều được ghi vào `Upload Log`.

API upload mặc định gửi các trường:

- `file`: nội dung audio;
- `record_id`;
- `batch_id`;
- `sentence_code`.

Trong cửa sổ **Cấu hình API**, có thể đổi tên trường file và JSON path chứa ID, ví dụ `data.audio.id`. Bearer token chỉ được giữ trong bộ nhớ trong phiên chạy và không được ghi vào Excel.

## Chạy kiểm thử

```powershell
& "C:\Users\Windows\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" -m unittest discover -s tests -v
```

## Đóng gói EXE

```powershell
.\build.ps1
```

File hoàn chỉnh nằm tại:

```text
dist\AIV0-Batch-Audio-Reviewer-v0.2.exe
```
