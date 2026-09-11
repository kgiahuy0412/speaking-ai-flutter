# Hồ sơ đối chiếu pháp lý của APK HOMI

Ngày kiểm tra: 11/09/2026. Cấu hình: `output/apk/install-production-defines.json`.

## Tài liệu và liên hệ công khai

Đã mở và đọc cả ba trang trong trình duyệt, không cần đăng nhập:

| Tài liệu | Đường dẫn | Phiên bản trên trang |
| --- | --- | --- |
| Chính sách quyền riêng tư | https://homi-app-privacy.lixiang22.chatgpt.site/privacy | 03/09/2026 |
| Điều khoản sử dụng | https://homi-app-privacy.lixiang22.chatgpt.site/terms | 25/08/2026 |
| Hỗ trợ và yêu cầu xóa dữ liệu | https://homi-app-privacy.lixiang22.chatgpt.site/support | 25/08/2026 |

Nhà phát hành ghi trên các trang: Trần Nguyễn Gia Huy. Email hỗ trợ công khai: huameizhongxin@gmail.com.

HTTP client tự động nhận 403 do Cloudflare managed challenge; trình duyệt mở được nội dung tiếng Việt và tiếng Anh. Xem `url-checks.json` để phân biệt kết quả kiểm tra tự động và trình duyệt.

## Nội dung trong ứng dụng

- Cấu hình đủ ba URL HTTPS, danh sách nhà cung cấp và thời hạn lưu dữ liệu; dùng backend production, không dùng demo.
- Màn hình dành cho phụ huynh yêu cầu xác nhận vai trò người lớn, đọc hết thông báo và chủ động chấp thuận trước khi bật tính năng giọng nói. Có lựa chọn tiếp tục không dùng giọng nói.
- Quyền micro của Android là bước riêng. Quyền này không thay thế chấp thuận xử lý dữ liệu.
- Công bố Railway, Cloudflare Workers AI, Cloudinary và Google ML Kit. ML Kit được mô tả là tải model và dịch trên thiết bị.
- Thời hạn hiển thị: tối đa 3 audio gần nhất; lưu audio tối đa 30 ngày, transcript/lịch sử 180 ngày, chẩn đoán 30 ngày, theo cấu hình production hiện có.
- Cài đặt có liên kết tài liệu, quản lý chấp thuận, yêu cầu xóa dữ liệu và mục Giấy phép thư viện.
- Thông báo thư viện native/model và nguyên văn Apache 2.0 được đóng gói cùng asset; các giấy phép Flutter/Dart nằm trong bundle giấy phép do Flutter tạo.

## Các điểm chưa thể xác nhận là đã hoàn tất

1. Trang quyền riêng tư công khai chưa có phần Google ML Kit, dù thông báo trong APK đã có. Cần đồng bộ trang công khai với phần bổ sung dự thảo bên dưới.
2. Điều khoản/hỗ trợ và một số hướng dẫn quyền micro vẫn chỉ nhắc iOS/iPhone. Cần bổ sung Android và thiết bị Android vào những hướng dẫn tương ứng.
3. Lần build này không kiểm toán máy chủ để chứng minh cơ chế tự động xóa đúng 30/180/30 ngày, hợp đồng nhà xử lý dữ liệu hoặc các cam kết về việc không sử dụng dữ liệu để huấn luyện mô hình.
4. Chưa được cung cấp giấy tờ chứng minh quyền thương mại của toàn bộ bộ audio/nội dung, giấy tờ chủ thể phát hành hoặc hồ sơ đã nộp tại cơ quan/cửa hàng ứng dụng. Không thể coi các liên kết chính sách và APK là bằng chứng thay thế các giấy tờ đó.
5. Hồ sơ này ghi nhận cấu hình và kết quả kỹ thuật; không phải chứng nhận đáp ứng toàn bộ nghĩa vụ pháp luật hay kết quả phê duyệt của Google Play.

## Dự thảo bổ sung cho trang công khai

Chưa đăng lên website. Nội dung dựa trên luồng offline hiện có và thông báo production:

> Google ML Kit: sau khi phụ huynh cho phép tải model ngôn ngữ, HOMI có thể sử dụng model tiếng Việt và tiếng Anh để dịch văn bản trực tiếp trên thiết bị khi backend không sẵn sàng. Trong luồng dịch offline này, HOMI không gửi audio hoặc transcript tới Google để dịch. Hoạt động tải model cần kết nối Internet. Bản dịch tự động có thể không chính xác; xem thông báo Google Translate tại mục Giấy phép thư viện trong ứng dụng.

> Khi cần hỗ trợ, phụ huynh cung cấp mẫu điện thoại Android hoặc iPhone/iPad, phiên bản Android hoặc iOS và phiên bản HOMI. Có thể thu hồi quyền micro trong phần quản lý quyền của HOMI ở Cài đặt hệ điều hành; lựa chọn không dùng giọng nói và chức năng yêu cầu xóa dữ liệu vẫn được cung cấp trong HOMI.

## Tệp kèm theo

- `THIRD_PARTY_NOTICES.md`: thông báo Vosk, model ngôn ngữ, ML Kit, JNA.
- `APACHE-2.0.txt`: nguyên văn giấy phép Apache 2.0 từ https://www.apache.org/licenses/LICENSE-2.0.txt.
- `url-checks.json`: kết quả kiểm tra truy cập các trang pháp lý.

