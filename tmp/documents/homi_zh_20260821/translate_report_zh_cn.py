from __future__ import annotations

import html
import re
import sys
import zipfile
from pathlib import Path


SOURCE = Path(sys.argv[1])
OUTPUT = Path(sys.argv[2])


TRANSLATIONS = {
    "KẾ HOẠCH PHÁT HÀNH HOMI APP": "HOMI APP 发布计划",
    "TRÊN APP STORE": "上架 APP STORE",
    "GỬI": "呈送",
    "Ban lãnh đạo / Người phê duyệt sản phẩm": "管理层 / 产品审批人",
    "NGƯỜI BÁO CÁO": "报告人",
    "NGÀY": "日期",
    "TRẠNG THÁI": "状态",
    "Có thể chuẩn bị TestFlight; chưa đủ điều kiện gửi App Review": "可准备 TestFlight；目前尚不具备提交 App Review 的条件",
    "KHUYẾN NGHỊ ĐIỀU HÀNH: ": "管理层建议：",
    "Nếu ưu tiên có bản TestFlight sớm, đăng ký Apple Developer Program theo loại Individual dưới tên pháp lý Gia Huy Trần Nguyễn ngay, kèm phê duyệt nội bộ về quyền sở hữu ứng dụng. Tên ứng dụng vẫn là HOMI App. Sau khi có pháp nhân, có thể yêu cầu Apple chuyển sang Organization.": "如优先尽快获得 TestFlight 版本，建议立即以法定姓名 Gia Huy Trần Nguyễn 注册个人类型的 Apple Developer Program，并同步取得内部对应用所有权的批准。应用名称仍为 HOMI App。待具备法人主体后，可向 Apple 申请转为组织账户。",
    "1. Kết luận nhanh": "1. 快速结论",
    "Phần mã nguồn iOS và workflow Codemagic đã được chuẩn bị, kiểm thử và đẩy lên GitHub.": "iOS 源代码和 Codemagic 工作流已完成准备、测试并推送至 GitHub。",
    "Nút thắt hiện tại là tài khoản Apple Developer trả phí, chưa phải vấn đề thiếu máy Mac; Windows + GitHub + Codemagic + iPhone thật là đủ cho quy trình này.": "当前瓶颈是尚未开通付费 Apple Developer 账户，而不是缺少 Mac；Windows + GitHub + Codemagic + 真机 iPhone 已足够完成该流程。",
    "Mục tiêu thực tế trong 7 ngày là tạo IPA ký số và đưa lên TestFlight nếu Apple kích hoạt tài khoản kịp. Thời điểm được duyệt công khai trên App Store không thể cam kết.": "未来 7 天内的现实目标是：若 Apple 能及时激活账户，则生成已签名 IPA 并上传至 TestFlight。无法承诺 App Store 公开审核通过的具体时间。",
    "Không nên gửi App Review trước khi chốt nhóm tuổi, chính sách trẻ em/AI, retention và các kiểm soát backend.": "在确定主要年龄组、儿童与 AI 政策、数据保留期限及后端控制措施之前，不应提交 App Review。",
    "LƯU Ý QUYỀN SỞ HỮU: ": "所有权提示：",
    "Tài khoản Individual đứng tên cá nhân. Nếu HOMI App là tài sản doanh nghiệp, cần email/văn bản nội bộ xác nhận cá nhân quản trị tài khoản thay doanh nghiệp và kế hoạch chuyển sang Organization sau này.": "个人账户登记在个人名下。若 HOMI App 属于企业资产，应通过内部邮件或书面文件确认该个人代表企业管理账户，并制定后续转为组织账户的计划。",
    "Những phần đã hoàn thành trong ứng dụng": "应用内已完成的工作",
    "Đổi tên hiển thị iOS thành HOMI App và thay icon Flutter mặc định bằng icon thương hiệu.": "已将 iOS 显示名称改为 HOMI App，并以品牌图标替换 Flutter 默认图标。",
    "Nâng iOS deployment target lên 15.0; bổ sung PrivacyInfo.xcprivacy; cấu hình automatic signing trong project.": "已将 iOS 部署目标提升至 15.0；添加 PrivacyInfo.xcprivacy；并在项目中配置自动签名。",
    "Thêm màn hình phụ huynh đồng ý trước khi gọi quyền micro; cho phép dùng nội dung không cần giọng nói khi từ chối.": "已在请求麦克风权限前增加家长同意页面；拒绝授权时仍可使用无需语音的内容。",
    "Bổ sung rút lại đồng ý, reset định danh iOS Keychain và yêu cầu server xóa history/transcript/audio liên quan.": "已增加撤回同意、重置 iOS Keychain 标识符，以及请求服务器删除相关历史记录、转录文本和音频的功能。",
    "Tách nội dung Settings theo nền tảng; iOS không còn hiển thị chẩn đoán BLE/HFP/Android không phù hợp.": "已按平台拆分设置内容；iOS 不再显示不适用的 BLE/HFP/Android 诊断信息。",
    "Workflow Codemagic dùng Xcode 26.6, build IPA release và upload App Store Connect/TestFlight.": "Codemagic 工作流使用 Xcode 26.6，构建发布版 IPA，并上传至 App Store Connect/TestFlight。",
    "3. Lựa chọn tài khoản Apple": "3. Apple 账户选择",
    "Apple Account hiện tại đã đăng nhập Apple Developer nhưng vẫn hiển thị “Join the Apple Developer Program”; vì vậy chưa được dùng App Store Connect, TestFlight hoặc API key Codemagic.": "当前 Apple Account 已登录 Apple Developer，但仍显示“Join the Apple Developer Program”；因此尚不能使用 App Store Connect、TestFlight 或 Codemagic API 密钥。",
    "Tiêu chí": "标准",
    "Individual": "个人（Individual）",
    "Organization": "组织（Organization）",
    "Điều kiện": "条件",
    "Apple ID, xác minh danh tính, phí thành viên.": "Apple ID、身份验证及会员费。",
    "Pháp nhân, D-U-N-S, website, email tên miền, thẩm quyền ký.": "法人主体、D-U-N-S、网站、域名邮箱及签署权限。",
    "Tên app": "应用名称",
    "Seller ban đầu": "初始卖方名称",
    "Gia Huy Trần Nguyễn (theo hồ sơ pháp lý Apple).": "Gia Huy Trần Nguyễn（按 Apple 法律资料）。",
    "Tên pháp lý của doanh nghiệp.": "企业法定名称。",
    "Tốc độ": "速度",
    "Nhanh nhất cho mục tiêu TestFlight, nếu Apple kích hoạt kịp.": "若 Apple 及时激活，这是实现 TestFlight 目标最快的方式。",
    "Thường lâu hơn do xác minh doanh nghiệp.": "因企业验证，通常耗时更长。",
    "Rủi ro": "风险",
    "Tài khoản và quyền sở hữu vận hành gắn với cá nhân.": "账户及运营控制权与个人绑定。",
    "Cần bộ hồ sơ đầy đủ; HOMI App không được dùng thay tên pháp nhân.": "需要完整企业资料；HOMI App 不能替代法人名称。",
    "Chuyển đổi": "转换",
    "Có thể yêu cầu Apple chuyển sang Organization sau này.": "后续可向 Apple 申请转为组织账户。",
    "Không áp dụng.": "不适用。",
    "PHƯƠNG ÁN ĐỀ XUẤT: ": "建议方案：",
    "Đăng ký Individual trước để rút ngắn đường tới TestFlight. Tên ứng dụng giữ HOMI App; tên nhà phát triển/người bán ban đầu là Gia Huy Trần Nguyễn. Khi doanh nghiệp HOMI có pháp nhân, D-U-N-S, website và email tên miền, gửi yêu cầu Apple chuyển tài khoản sang Organization.": "先注册个人账户，以缩短上线 TestFlight 的时间。应用名称保持 HOMI App；初始开发者/卖方名称为 Gia Huy Trần Nguyễn。待 HOMI 企业具备法人主体、D-U-N-S、网站和域名邮箱后，再向 Apple 申请将账户转为组织账户。",
    "Các điều kiện thực hiện ngay": "需立即满足的条件",
    "Apple Account có xác thực hai yếu tố và thông tin cá nhân khớp giấy tờ.": "Apple Account 已启用双重认证，且个人信息与证件一致。",
    "Đăng ký trên web vì Apple Developer app báo tài khoản này không hỗ trợ enrollment trong ứng dụng.": "由于 Apple Developer App 提示该账户不支持在 App 内注册，因此应通过网页申请。",
    "Phí thành viên Apple Developer Program: 99 USD/năm hoặc giá nội tệ Apple hiển thị.": "Apple Developer Program 会员费：每年 99 美元，或以 Apple 显示的当地货币价格为准。",
    "Nếu thanh toán Individual bằng thẻ tín dụng trên web, nên dùng thẻ của chính người đăng ký để tránh chậm xác minh.": "若在网页上使用信用卡支付个人账户费用，建议使用申请人本人的银行卡，以避免验证延迟。",
    "Nếu sau 24 giờ chưa có email kích hoạt, liên hệ Apple Developer Support kèm Enrollment ID.": "若 24 小时后仍未收到激活邮件，请携带 Enrollment ID 联系 Apple Developer Support。",
    "Đặt tên và định danh kỹ thuật": "命名与技术标识",
    "Tên công khai vẫn là HOMI App khi chuyển từ Individual sang Organization, trừ khi chủ tài khoản chủ động đổi tên app.": "从个人账户转为组织账户后，公开应用名称仍为 HOMI App，除非账户持有人主动更改应用名称。",
    "Source hiện dùng com.innotrik.aispeaking. Bundle ID không hiển thị công khai nhưng là định danh lâu dài và không thể đổi cho cùng app sau khi upload build. Nếu muốn loại bỏ INNOTRIK hoàn toàn, nên đổi trước khi tạo App ID sang com.homiapp.aispeaking (nếu còn khả dụng) và đổi integration nội bộ sang homi_app_store_connect.": "当前 Bundle ID 为 com.innotrik.aispeaking；它不公开显示，且同一应用上传后无法更改。若要移除 INNOTRIK，请在创建 App ID 前改为 com.homiapp.aispeaking（如可用），并将集成名改为 homi_app_store_connect。",
    ". Blocker chính sách trẻ em và AI": ". 儿童与 AI 政策方面的主要阻碍",
    "HOMI App hướng trực tiếp tới trẻ em và truyền dữ liệu giọng nói tới backend/AI. Đây là nhóm rủi ro App Review cao nhất, không thể giải quyết chỉ bằng việc build IPA.": "HOMI App 直接面向儿童，并将语音数据传输至后端/AI。这是 App Review 中风险最高的一类问题，不能仅通过构建 IPA 来解决。",
    "CẢNH BÁO: ": "警告：",
    "Parental gate trong giao diện không mặc nhiên tương đương với sự chấp thuận của phụ huynh theo luật bảo vệ dữ liệu trẻ em. Cần rà soát pháp lý theo thị trường phát hành. Đây là đánh giá kỹ thuật/vận hành, không thay thế tư vấn pháp lý.": "界面中的家长门槛并不当然等同于儿童数据保护法律所要求的家长同意。必须根据目标发布市场进行法律审查。本报告仅为技术与运营评估，不能替代法律意见。",
    "Dữ liệu dự kiến phải khai báo": "预计需要申报的数据",
    "Audio Data: bản ghi giọng nói của trẻ.": "Audio Data：儿童语音录音。",
    "Other User Content: transcript/nội dung trẻ nói.": "Other User Content：儿童说话内容的转录文本。",
    "Age hoặc age group.": "Age 或年龄组。",
    "Device ID/User ID: clientId tồn tại lâu dài trên thiết bị.": "Device ID/User ID：在设备上长期存在的 clientId。",
    "Product Interaction, Performance và Diagnostics.": "Product Interaction、Performance 和 Diagnostics。",
    "Linked to user/device nếu backend gắn dữ liệu với clientId; chỉ chọn Tracking khi thực sự theo dõi chéo dịch vụ.": "若后端将数据与 clientId 关联，则应申报 Linked to user/device；仅在确实进行跨服务跟踪时选择 Tracking。",
    "Phần app đã giảm rủi ro": "应用端已完成的降风险措施",
    "Thông báo dữ liệu và bên nhận trước hộp thoại quyền micro.": "在麦克风权限弹窗前说明所收集的数据及数据接收方。",
    "Yêu cầu phụ huynh chủ động đồng ý; liên kết ngoài và thao tác riêng tư có parental gate.": "要求家长主动同意；外部链接及隐私相关操作均设置家长门槛。",
    "Chế độ không giọng nói nếu từ chối; không tạo ID/gọi backend trước khi đồng ý.": "拒绝授权时提供无语音模式；在获得同意前不创建 ID，也不调用后端。",
    "Cho phép rút đồng ý và reset ID; chỉ báo xóa thành công khi server trả HTTP thành công.": "允许撤回同意并重置 ID；仅在服务器返回成功 HTTP 状态时提示删除成功。",
    "Phần còn phải hoàn thành trước App Review": "提交 App Review 前仍需完成的事项",
    "Chọn Kids Category và một nhóm tuổi chính: 5 tuổi trở xuống, 6-8 hoặc 9-11. Dải 3-15 hiện không khớp một nhóm Kids Category.": "选择 Kids Category 及一个主要年龄组：5 岁及以下、6-8 岁或 9-11 岁。当前 3-15 岁范围不符合任何单一 Kids Category 年龄组。",
    "Công bố Privacy Policy, Terms và Support; nêu đúng backend/Cloudflare/OpenAI và mọi subprocessor thật sự nhận dữ liệu.": "发布 Privacy Policy、Terms 和 Support 页面；准确说明后端、Cloudflare、OpenAI 以及所有实际接收数据的子处理方。",
    "Định nghĩa retention/TTL riêng cho audio, transcript, history, telemetry, cache và backup.": "分别定义音频、转录文本、历史记录、遥测数据、缓存和备份的 retention/TTL。",
    "Backend phải có authentication/authorization theo phụ huynh hoặc installation; không chỉ dựa vào clientId.": "后端必须基于家长或安装实例进行 authentication/authorization，不能仅依赖 clientId。",
    "Xóa cascade thực sự history, transcript, audio và cache; ứng dụng hiện chỉ có thể yêu cầu, không chứng minh dữ liệu server đã bị xóa.": "必须真正级联删除历史记录、转录文本、音频和缓存；当前应用只能发出删除请求，无法证明服务器数据已被删除。",
    "Không log nội dung nhạy cảm của trẻ; bổ sung rate limit và chống lạm dụng.": "不得记录儿童敏感内容；应增加 rate limit 和防滥用措施。",
    "Kiểm tra archive bằng Xcode Privacy Report và đảm bảo App Privacy Label khớp runtime/backend.": "使用 Xcode Privacy Report 检查归档，并确保 App Privacy Label 与实际运行时及后端行为一致。",
    "5. Các quyết định cần sếp phản hồi": "5. 需要管理层确认的决策",
    "Quyết định cần phê duyệt": "待批准事项",
    "Khuyến nghị": "建议",
    "Hạn": "期限",
    "Đăng ký Individual dưới tên pháp lý Gia Huy Trần Nguyễn để mở TestFlight sớm?": "是否以法定姓名 Gia Huy Trần Nguyễn 注册个人账户，以尽快启用 TestFlight？",
    "Đồng ý, kèm xác nhận nội bộ về quyền sở hữu app.": "建议同意，并附内部应用所有权确认。",
    "Ngay": "立即",
    "Đổi Bundle ID từ com.innotrik.aispeaking sang định danh HOMI trước khi tạo App ID?": "是否在创建 App ID 前，将 Bundle ID 从 com.innotrik.aispeaking 改为 HOMI 标识？",
    "Đổi sang com.homiapp.aispeaking nếu khả dụng.": "如可用，改为 com.homiapp.aispeaking。",
    "Trước App ID": "创建 App ID 前",
    "Chọn Kids Category và nhóm tuổi chính nào?": "应选择哪个 Kids Category 主要年龄组？",
    "Chọn đúng thị trường lõi; không dùng dải 3-15 cho Kids Category.": "按核心目标市场选择；Kids Category 不应使用 3-15 岁范围。",
    "Trước metadata": "提交元数据前",
    "Phê duyệt Privacy Policy, Terms, Support, danh sách AI/subprocessors và retention?": "是否批准 Privacy Policy、Terms、Support、AI/子处理方清单及数据保留方案？",
    "Phải khớp hành vi backend thực tế.": "必须与后端实际行为一致。",
    "Trước build IPA": "构建 IPA 前",
    "Ai chịu trách nhiệm hoàn thiện auth, xóa cascade, TTL, log và rate limit?": "由谁负责完成 auth、级联删除、TTL、日志及 rate limit？",
    "Chỉ định chủ sở hữu backend và ngày nghiệm thu.": "指定后端负责人和验收日期。",
    "Trước review": "提交审核前",
    "Kế hoạch pháp nhân HOMI và chuyển Individual sang Organization?": "HOMI 法人主体及个人账户转组织账户的计划是什么？",
    "Lập sau khi TestFlight; không tạo tài khoản mới tùy tiện.": "可在 TestFlight 稳定后制定；不要随意创建新账户。",
    "Sau beta": "Beta 后",
    "THỨ TỰ ƯU TIÊN: ": "优先顺序：",
    "Phê duyệt 1-2 ngay để không mất thời gian chờ Apple. Song song, đội sản phẩm/pháp lý chốt 3-4 và đội backend chịu trách nhiệm 5. Quyết định 6 có thể thực hiện sau khi TestFlight ổn định.": "立即批准第 1-2 项，以免浪费等待 Apple 的时间。同时，由产品/法务团队确定第 3-4 项，后端团队负责第 5 项。第 6 项可在 TestFlight 稳定后执行。",
    "Trang ": "页码 ",
    "HOMI APP  |  BÁO CÁO PHÁT HÀNH iOS": "HOMI APP  |  iOS 发布报告",
}


ALLOWED_UNCHANGED = {
    "Gia Huy Trần Nguyễn",
    "21/08/2026",
    "HOMI App",
    "#",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "2. ",
    "4",
}


TARGET_PARTS = {"word/document.xml", "word/header1.xml", "word/footer1.xml"}


def replace_text_nodes(xml_text: str, part: str) -> tuple[str, dict[str, int]]:
    counts: dict[str, int] = {}
    for source, target in TRANSLATIONS.items():
        escaped_source = html.escape(source, quote=False)
        escaped_target = html.escape(target, quote=False)
        needle = f">{escaped_source}</w:t>"
        replacement = f">{escaped_target}</w:t>"
        count = xml_text.count(needle)
        if count:
            xml_text = xml_text.replace(needle, replacement)
            counts[source] = count

    remaining = re.findall(r"<w:t(?:\s[^>]*)?>(.*?)</w:t>", xml_text)
    unresolved = []
    for raw in remaining:
        text = html.unescape(raw)
        if not text.strip() or text in ALLOWED_UNCHANGED:
            continue
        if text in TRANSLATIONS.values():
            continue
        if text.startswith("HOMI APP") and "发布报告" in text:
            continue
        if any(ch in text for ch in "ăâđêôơưĂÂĐÊÔƠƯáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẤẦẨẪẬẮẰẲẴẶÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ"):
            unresolved.append(text)
    if unresolved:
        raise RuntimeError(f"Untranslated Vietnamese text remains in {part}: {unresolved}")
    return xml_text, counts


def main() -> None:
    if SOURCE.resolve() == OUTPUT.resolve():
        raise RuntimeError("Output must be different from source")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    applied: dict[str, int] = {}
    with zipfile.ZipFile(SOURCE, "r") as source_zip, zipfile.ZipFile(
        OUTPUT, "w", compression=zipfile.ZIP_DEFLATED
    ) as output_zip:
        for info in source_zip.infolist():
            data = source_zip.read(info.filename)
            if info.filename in TARGET_PARTS:
                xml_text = data.decode("utf-8")
                xml_text, counts = replace_text_nodes(xml_text, info.filename)
                if info.filename == "word/document.xml":
                    # Cached pagination markers from the Vietnamese layout can
                    # create blank pages after the Chinese text reflows.
                    xml_text = xml_text.replace("<w:lastRenderedPageBreak/>", "")
                    # A spacer paragraph immediately before a page-break heading
                    # can be pushed onto an otherwise empty page after reflow.
                    empty_before_break = re.compile(
                        r"<w:p\b[^>]*>(?:(?!<w:t\b|</w:p>).)*</w:p>"
                        r"(?=<w:p\b[^>]*>(?:(?!</w:p>).)*<w:pageBreakBefore/>)",
                        re.DOTALL,
                    )
                    xml_text = empty_before_break.sub("", xml_text)
                for key, value in counts.items():
                    applied[key] = applied.get(key, 0) + value
                data = xml_text.encode("utf-8")
            elif info.filename == "word/styles.xml":
                xml_text = data.decode("utf-8")
                source_font = '<w:rFonts w:ascii="Calibri" w:eastAsia="Calibri" w:hAnsi="Calibri"/>'
                target_font = (
                    '<w:rFonts w:ascii="Calibri" w:eastAsia="Microsoft YaHei" w:hAnsi="Calibri"/>'
                    '<w:sz w:val="20"/><w:szCs w:val="20"/>'
                    '<w:lang w:val="en-US" w:eastAsia="zh-CN"/>'
                )
                if xml_text.count(source_font) != 1:
                    raise RuntimeError("Expected one Normal-style Calibri East Asian font declaration")
                data = xml_text.replace(source_font, target_font).encode("utf-8")
            output_zip.writestr(info, data)

    unused = sorted(key for key in TRANSLATIONS if key not in applied)
    if unused:
        raise RuntimeError(f"Translation entries not found in source: {unused}")
    print(f"created={OUTPUT}")
    print(f"translated_source_nodes={sum(applied.values())}")


if __name__ == "__main__":
    main()
