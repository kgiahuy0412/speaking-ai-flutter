# Design QA — Nền tối giản và bỏ nút Đúng/Sai

## Evidence

- Source visual truth: `C:/Users/Windows/.codex/generated_images/019fac05-f74f-7952-9259-e708249b6185/exec-4d8df4a0-1f82-4c50-9978-8a536aa5e669.png` — 942 × 1672 px.
- Flutter mobile implementation: `test/goldens/conversation-ready-shortcut-450x1025.png` — 450 × 1025 logical px, DPR 1.
- Browser-rendered implementation: `.codex/design-qa/minimal-background/conversation-web.png` — 1280 × 720 px.
- Combined comparison input: `.codex/design-qa/minimal-background/source-vs-mobile.png` — 924 × 1077 px.
- State: màn giao tiếp đã có câu tiếng Anh; không hiển thị nút “Đúng ý” hoặc “Sai ý”.
- Density normalization: ảnh nguồn được crop trung tâm và chuẩn hóa về 450 × 1025 trước khi đặt cạnh ảnh Flutter mobile.

## Full-view comparison

- Nền giữ đúng bảng màu xanh trời, mint và blue-gray của nguồn nhưng giảm mạnh độ bão hòa và chi tiết.
- Vùng giữa có khoảng thở lớn; các thẻ trắng/lavender vẫn là điểm tập trung.
- Mây chỉ nằm ở mép trên, đồi chỉ nằm sát đáy nên không cạnh tranh với chữ hoặc CTA.
- Hai nút phản hồi đã được gỡ; bố cục kết quả tự khép lại tự nhiên, không để khoảng trống bất thường.

## Required fidelity surfaces

- Fonts and typography: Roboto, trọng lượng chữ, line-height và hierarchy không thay đổi; không có chữ bị cắt ngoài các quy tắc ellipsis sẵn có.
- Spacing and layout rhythm: khoảng cách giữa hero, result panel và CTA giữ nhịp cũ; vùng trước đây chứa feedback buttons được thu gọn.
- Colors and visual tokens: nền powder-blue/mint mới có độ tương phản thấp; indigo, lavender, success và surface token của UI giữ nguyên.
- Image quality and asset fidelity: nền raster 942 × 1672 rõ nét ở mobile lẫn Web, không có watermark, text, nhân vật hay chi tiết giả UI.
- Copy and content: nội dung giao tiếp không đổi; “Đúng ý” và “Sai ý” không còn trong DOM màn chính.
- Accessibility and responsiveness: 13 golden trạng thái mobile qua; không có overflow ở 450 × 1025.

## Interaction verification

- Topic shortcut mở được màn “Luyện nghe theo chủ đề” và quay lại màn giao tiếp.
- Browser DOM không chứa “Đúng ý” hoặc “Sai ý”.
- Web console không có error/warning; chỉ có log debug khởi tạo Flutter.

## Findings

- Không còn P0, P1 hoặc P2.
- Không cần focused crop riêng vì thay đổi chỉ liên quan nền toàn màn hình và việc loại bỏ hai control; cả hai đều đọc rõ ở full-view comparison.

## Comparison history

- Pass 1: nền nhiều chi tiết được thay bằng nền phẳng, ít bão hòa; hai nút feedback được gỡ. So sánh kết hợp xác nhận hierarchy, độ tương phản và nhịp dọc đều ổn, không cần vòng sửa P0/P1/P2.

final result: passed

