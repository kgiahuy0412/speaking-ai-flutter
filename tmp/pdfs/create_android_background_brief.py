from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output" / "pdf" / "bao-cao-kha-nang-chay-nen-h20-android-vi-zh.pdf"

FONT_REGULAR = r"C:\Windows\Fonts\msyh.ttc"
FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_VI_REGULAR = r"C:\Windows\Fonts\arial.ttf"
FONT_VI_BOLD = r"C:\Windows\Fonts\arialbd.ttf"

pdfmetrics.registerFont(TTFont("ReportSans", FONT_REGULAR, subfontIndex=0))
pdfmetrics.registerFont(TTFont("ReportSans-Bold", FONT_BOLD, subfontIndex=0))
pdfmetrics.registerFont(TTFont("ReportVi", FONT_VI_REGULAR))
pdfmetrics.registerFont(TTFont("ReportVi-Bold", FONT_VI_BOLD))

NAVY = colors.HexColor("#10233F")
BLUE = colors.HexColor("#2563EB")
PALE_BLUE = colors.HexColor("#EFF6FF")
GREEN = colors.HexColor("#0F9D68")
PALE_GREEN = colors.HexColor("#ECFDF5")
AMBER = colors.HexColor("#B7791F")
PALE_AMBER = colors.HexColor("#FFF8E6")
RED = colors.HexColor("#B42318")
PALE_RED = colors.HexColor("#FEF3F2")
INK = colors.HexColor("#172033")
MUTED = colors.HexColor("#5F6B7A")
LINE = colors.HexColor("#D8E0EA")
WHITE = colors.white
LIGHT = colors.HexColor("#F6F8FB")


class NumberedCanvasMixin:
    pass


def page_background(canvas, doc):
    canvas.saveState()
    width, height = A4
    canvas.setFillColor(NAVY)
    canvas.rect(0, height - 20 * mm, width, 20 * mm, fill=1, stroke=0)

    canvas.setFillColor(WHITE)
    if doc.page == 1:
        canvas.setFont("ReportVi-Bold", 9)
        header = "H20  •  ANDROID APK  •  BÁO CÁO NỘI BỘ"
        footer = "14/08/2026  •  Phạm vi V1: BLE Control + HFP hai chiều"
    else:
        canvas.setFont("ReportSans-Bold", 9)
        header = "H20  •  ANDROID APK  •  内部简报"
        footer = "14/08/2026  •  V1范围：BLE控制 + 双向HFP"
    canvas.drawString(16 * mm, height - 12.5 * mm, header)

    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(16 * mm, 14 * mm, width - 16 * mm, 14 * mm)
    canvas.setFillColor(MUTED)
    canvas.setFont("ReportVi" if doc.page == 1 else "ReportSans", 7.5)
    canvas.drawString(16 * mm, 9 * mm, footer)
    canvas.drawRightString(width - 16 * mm, 9 * mm, f"{doc.page}")
    canvas.restoreState()


def make_styles(regular="ReportSans", bold="ReportSans-Bold"):
    styles = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=styles["Title"],
            fontName=bold,
            fontSize=19,
            leading=24,
            textColor=NAVY,
            alignment=TA_LEFT,
            spaceAfter=3 * mm,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=styles["Normal"],
            fontName=regular,
            fontSize=9.5,
            leading=14,
            textColor=MUTED,
            spaceAfter=4 * mm,
        ),
        "section": ParagraphStyle(
            "Section",
            parent=styles["Heading2"],
            fontName=bold,
            fontSize=11.2,
            leading=14,
            textColor=NAVY,
            spaceBefore=2.8 * mm,
            spaceAfter=1.8 * mm,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=styles["BodyText"],
            fontName=regular,
            fontSize=8.8,
            leading=12.7,
            textColor=INK,
            spaceAfter=1.3 * mm,
        ),
        "small": ParagraphStyle(
            "Small",
            parent=styles["BodyText"],
            fontName=regular,
            fontSize=7.2,
            leading=10,
            textColor=MUTED,
        ),
        "card_title": ParagraphStyle(
            "CardTitle",
            parent=styles["Heading3"],
            fontName=bold,
            fontSize=10,
            leading=13,
            textColor=NAVY,
            spaceAfter=1 * mm,
        ),
        "card_body": ParagraphStyle(
            "CardBody",
            parent=styles["BodyText"],
            fontName=regular,
            fontSize=8.2,
            leading=11.5,
            textColor=INK,
        ),
        "status": ParagraphStyle(
            "Status",
            parent=styles["BodyText"],
            fontName=bold,
            fontSize=9.5,
            leading=13,
            textColor=GREEN,
            alignment=TA_CENTER,
        ),
        "recommend": ParagraphStyle(
            "Recommend",
            parent=styles["BodyText"],
            fontName=bold,
            fontSize=9.2,
            leading=13,
            textColor=WHITE,
        ),
        "table_header": ParagraphStyle(
            "TableHeader",
            parent=styles["BodyText"],
            fontName=bold,
            fontSize=9.2,
            leading=12,
            textColor=WHITE,
        ),
    }


S_VI = make_styles("ReportVi", "ReportVi-Bold")
S_ZH = make_styles("ReportSans", "ReportSans-Bold")
S = S_VI


def p(text, style="body"):
    return Paragraph(text, S[style])


def bullet(text):
    return p(f"<font color='#2563EB'>●</font>&nbsp;&nbsp;{text}", "body")


def card(title, body, background=LIGHT, border=LINE):
    content = [p(title, "card_title"), p(body, "card_body")]
    table = Table([[content]], colWidths=[174 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.7, border),
                ("LEFTPADDING", (0, 0), (-1, -1), 4 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 3 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3 * mm),
            ]
        )
    )
    return table


def scenario_table(rows, headers):
    data = [[p(headers[0], "table_header"), p(headers[1], "table_header")]]
    for left, right, tone in rows:
        right_color = {"green": GREEN, "amber": AMBER, "red": RED}[tone]
        right_style = ParagraphStyle(
            f"Result-{tone}",
            parent=S["card_body"],
            fontName=S["card_title"].fontName,
            textColor=right_color,
        )
        data.append([p(left, "card_body"), Paragraph(right, right_style)])
    table = Table(data, colWidths=[120 * mm, 54 * mm], repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
        ("GRID", (0, 0), (-1, -1), 0.5, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 2.1 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.1 * mm),
    ]
    for row in range(1, len(data)):
        style.append(("BACKGROUND", (0, row), (-1, row), WHITE if row % 2 else LIGHT))
    table.setStyle(TableStyle(style))
    return table


def recommendation(text):
    table = Table([[p(text, "recommend")]], colWidths=[174 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY),
                ("LEFTPADDING", (0, 0), (-1, -1), 4 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 3.2 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3.2 * mm),
            ]
        )
    )
    return table


def vietnamese_page():
    global S
    S = S_VI
    story = [
        Spacer(1, 4 * mm),
        p("BÁO CÁO KHẢ NĂNG CHẠY NỀN H20 TRÊN ANDROID APK", "title"),
        p("Bản ngắn gọn trình ban lãnh đạo • Kiến trúc đã chốt với ODM: BLE chỉ điều khiển, HFP truyền âm thanh hai chiều", "subtitle"),
        card(
            "KẾT LUẬN: KHẢ THI CAO",
            "Android có thể cho H20 tiếp tục hoạt động khi phụ huynh chuyển sang Facebook/ứng dụng khác hoặc khóa màn hình, với điều kiện người dùng đã mở app và bật <b>Chế độ học nền H20</b> trước. Cơ chế tương tự Be/Grab: một Foreground Service chạy kèm thông báo thường trực.",
            PALE_GREEN,
            colors.HexColor("#A7E7CF"),
        ),
        p("Khả năng theo trạng thái", "section"),
        scenario_table(
            [
                ("Đã mở app, bật học nền, sau đó sang Facebook hoặc khóa màn hình", "Hỗ trợ", "green"),
                ("Vuốt giao diện khỏi Recent Apps nhưng service vẫn hoạt động", "Có điều kiện", "amber"),
                ("Chưa bật học nền, vừa khởi động lại máy hoặc đã Force Stop", "Không cam kết", "red"),
            ],
            ("Tình huống", "Đánh giá"),
        ),
        p("Luồng vận hành V1", "section"),
        bullet("<b>BLE Control:</b> nhận MAIN, pin, firmware và trạng thái."),
        bullet("<b>HFP hai chiều:</b> micro H20 → APP/backend; audio tiếng Anh → loa H20."),
        bullet("<b>Foreground Service:</b> giữ BLE, HFP, trạng thái phiên học, mạng và tự kết nối lại trong nền."),
        p("Điều kiện triển khai", "section"),
        card(
            "APP cần bổ sung",
            "Service loại <b>connectedDevice + microphone</b> (và mediaPlayback nếu cần); thông báo “H20 đã sẵn sàng”; chuyển BLE/HFP khỏi vòng đời MainActivity; quản lý audio focus, reconnect và trạng thái MAIN khi Flutter UI không hiển thị.",
            PALE_BLUE,
            colors.HexColor("#B8D3FF"),
        ),
        p("Giới hạn cần báo trước", "section"),
        bullet("Nếu Facebook phát clip có âm thanh, Android có thể giảm âm/tạm dừng Facebook hoặc làm thay đổi audio route HFP; cần kiểm thử trên H20 thật."),
        bullet("Force Stop hoặc nút Stop trong “Ứng dụng đang hoạt động” sẽ dừng toàn bộ dịch vụ; người dùng phải mở app lại."),
        bullet("Cloud cần Internet; Diagnostic APK offline vẫn phải kiểm tra BLE, HFP, MAIN, micro và loa tại chỗ."),
        bullet("Không yêu cầu ODM bổ sung chức năng trước khi mẫu về Việt Nam; phần thay đổi hiện tại thuộc APP."),
        Spacer(1, 2 * mm),
        recommendation("ĐỀ XUẤT: Phê duyệt triển khai. Giai đoạn 1 kiểm chứng nền offline (MAIN + HFP thu/phát); giai đoạn 2 ghép backend AI; giai đoạn 3 kiểm thử khóa màn hình, Facebook và nhiều hãng điện thoại."),
        Spacer(1, 2.5 * mm),
        p(
            "Cơ sở kỹ thuật: Android Developers - BLE background communication; Foreground service background-start restrictions; Google Play - Foreground Service requirements.",
            "small",
        ),
    ]
    return story


def chinese_page():
    global S
    S = S_ZH
    story = [
        Spacer(1, 4 * mm),
        p("H20 在 ANDROID APK 后台运行的可行性简报", "title"),
        p("管理层简版 • ODM 已确认的架构：BLE 仅用于控制，双向 HFP 用于音频", "subtitle"),
        card(
            "结论：可行性高",
            "在用户先打开 APP 并启用<b>“H20 后台学习模式”</b>的前提下，即使家长切换到 Facebook/其他应用或锁屏，H20 仍可继续工作。实现方式类似 Be/Grab：通过带常驻通知的 Android Foreground Service 维持后台运行。",
            PALE_GREEN,
            colors.HexColor("#A7E7CF"),
        ),
        p("不同状态下的可行性", "section"),
        scenario_table(
            [
                ("已打开 APP 并启用后台学习，然后切换应用或锁屏", "支持", "green"),
                ("从最近任务中划掉界面，但后台 Service 仍在运行", "有条件支持", "amber"),
                ("未启用后台学习、手机刚重启或用户已 Force Stop", "不保证", "red"),
            ],
            ("使用场景", "评估"),
        ),
        p("V1 工作流程", "section"),
        bullet("<b>BLE Control：</b>接收 MAIN、读取电量、固件和状态。"),
        bullet("<b>双向 HFP：</b>H20 麦克风 → APP/云端；英文音频 → H20 扬声器。"),
        bullet("<b>Foreground Service：</b>在后台保持 BLE、HFP、学习会话、网络及自动重连。"),
        p("APP 侧实施条件", "section"),
        card(
            "需要新增或调整",
            "新增 <b>connectedDevice + microphone</b> 类型的 Foreground Service（必要时增加 mediaPlayback）；显示“H20 已就绪”常驻通知；将 BLE/HFP 从 MainActivity 生命周期迁移到 Service；处理音频焦点、重连及无界面时的 MAIN 状态机。",
            PALE_BLUE,
            colors.HexColor("#B8D3FF"),
        ),
        p("需要提前说明的限制", "section"),
        bullet("如果 Facebook 播放有声视频，Android 可能降低/暂停 Facebook 音量，或改变 HFP 音频路由；必须使用 H20 实机验证。"),
        bullet("Force Stop 或 Android“正在运行的应用”中的 Stop 会终止整个 Service，之后必须重新打开 APP。"),
        bullet("云端功能需要网络；离线 Diagnostic APK 仍应本地验证 BLE、HFP、MAIN、麦克风和扬声器。"),
        bullet("样机到达越南前无需 ODM 增加新功能；当前改动范围属于 APP 端。"),
        Spacer(1, 2 * mm),
        recommendation("建议：批准实施。第一阶段验证离线后台链路（MAIN + HFP 录放音）；第二阶段接入 AI 后端；第三阶段测试锁屏、Facebook 及不同品牌 Android 手机。"),
        Spacer(1, 2.5 * mm),
        p(
            "技术依据：Android Developers - BLE 后台通信、Foreground Service 后台启动限制；Google Play - Foreground Service 申报要求。",
            "small",
        ),
    ]
    return story


def build():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=24 * mm,
        bottomMargin=18 * mm,
        title="Báo cáo khả năng chạy nền H20 trên Android APK",
        author="AI Speaking Project",
        subject="Báo cáo song ngữ Việt - Trung giản thể",
    )
    frame = Frame(
        doc.leftMargin,
        doc.bottomMargin,
        doc.width,
        doc.height,
        id="normal",
        leftPadding=0,
        rightPadding=0,
        topPadding=0,
        bottomPadding=0,
    )
    doc.addPageTemplates([PageTemplate(id="brief", frames=[frame], onPage=page_background)])
    story = vietnamese_page() + [PageBreak()] + chinese_page()
    doc.build(story)
    print(OUTPUT)


if __name__ == "__main__":
    build()
