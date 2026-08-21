import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "C:/Users/Windows/Documents/ai-speaking-flutter-app/outputs/assistant_prompt_inventory_20260821";
const outputFile = path.join(outputDir, "Danh_muc_cau_thoai_tro_ly_AI_va_fallback.xlsx");
const previewDir = path.join(outputDir, "previews");

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

const assistantRows = [
  ["AI-001", "MAIN / Điều hướng gốc", "Chọn chức năng", "Nhấn MAIN hoặc bắt đầu phiên trợ lý", "Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?", "Đang dùng trong code", "Loa/TTS", "Mở mic để chờ lựa chọn", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 69, "Câu gốc; cũng được lặp lại khi câu trả lời ngoài phạm vi ở bước chọn chức năng"],
  ["AI-002", "MAIN / Im lặng", "Không có tiếng nói lần 1", "Không phát hiện lời nói trong 6 giây", "Con muốn làm gì?", "Đang dùng trong code", "Loa/TTS", "Mở mic lại", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 71, "Bộ đếm im lặng do VoiceNavigationController quản lý"],
  ["AI-003", "MAIN / Im lặng", "Không có tiếng nói lần 2", "Tiếp tục không phát hiện lời nói", "Khi nào sẵn sàng, con nhấn MAIN gọi mình nhé.", "Đang dùng trong code", "Loa/TTS", "Kết thúc phiên MAIN", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 72, "Fallback im lặng cấp 2"],
  ["AI-004", "MAIN / Đổi hoạt động", "Rời bài học", "Trẻ yêu cầu học nội dung khác", "Có chứ. Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?", "Đang dùng trong code", "Loa/TTS", "Mở mic để chọn chức năng khác", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 74, "Dùng sau lệnh học cái khác/thoát luyện nói"],
  ["AI-005", "Luyện nghe / MAIN", "Điều hướng trong bài", "Nhấn MAIN khi đang học", "Con muốn học câu tiếp theo, nghe câu trước, dừng lại hay không học nữa?", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ lệnh trong bài", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 76, "Câu hỏi điều hướng chung trong bài học"],
  ["AI-006", "Luyện nghe / Rời bài", "Chọn hoạt động thay thế", "Trẻ nói không học nữa/học cái khác", "Con muốn dịch sang tiếng Anh hay học từ vựng?", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ lựa chọn", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 78, "Không đưa lựa chọn học chủ đề ở bước này"],
  ["AI-007", "Chủ đề", "Hỏi tuổi", "Chưa có nhóm tuổi cấu hình", "Con mấy tuổi", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ tuổi", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 250, "Bản ngắn"],
  ["AI-008", "Chủ đề", "Hỏi lại tuổi", "Không nhận được số tuổi", "Con mấy tuổi? Con hãy nói, ví dụ con 6 tuổi", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ tuổi", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 635, "Có ví dụ để trẻ trả lời"],
  ["AI-009", "Chủ đề", "Tuổi ngoài phạm vi", "Tuổi không thuộc catalog", "Bi cô có bài học cho các bạn từ {tuổi nhỏ nhất} đến {tuổi lớn nhất} tuổi. Con mấy tuổi", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ tuổi hợp lệ", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 645, "Khoảng tuổi ghép từ catalog"],
  ["AI-010", "Chủ đề", "Chọn chủ đề", "Đã biết nhóm tuổi", "Có {số chủ đề} chủ đề. Con muốn học chủ đề số mấy", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ số chủ đề", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 260, "Số chủ đề lấy từ catalog"],
  ["AI-011", "Chủ đề", "Chủ đề không hợp lệ", "Không nhận được số hoặc số ngoài phạm vi", "Có {số chủ đề} chủ đề. Con hãy chọn chủ đề từ số 1 đến số {số chủ đề}", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ chọn lại", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 682, "Fallback theo trạng thái chọn chủ đề"],
  ["AI-012", "Chủ đề", "Chủ đề trống", "Chủ đề không có bài", "Chủ đề này chưa có bài học. Con thử lại sau nhé", "Đang dùng trong code", "Loa/TTS", "Kết thúc phiên chọn", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 709, "Lỗi nội dung"],
  ["AI-013", "Chủ đề", "Chọn bài", "Mở được chủ đề", "Có {số bài} bài học. Con muốn học bài số mấy", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ số bài", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 717, "Số bài lấy từ nội dung chủ đề"],
  ["AI-014", "Chủ đề", "Bài không hợp lệ", "Không nhận được số hoặc số ngoài phạm vi", "Có {số bài} bài học. Con hãy chọn bài từ số 1 đến số {số bài}", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ chọn lại", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 836, "Fallback theo trạng thái chọn bài"],
  ["AI-015", "Chủ đề", "Xác nhận học lại", "Chọn chủ đề đã hoàn thành", "Chủ đề số {số chủ đề} con đã học rồi. Con có muốn học lại không?", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ Có/Không", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 765, "Xác nhận học lại chủ đề"],
  ["AI-016", "Chủ đề", "Xác nhận chưa hợp lệ", "Không nhận được Có/Không", "Con có muốn học lại chủ đề số {số chủ đề} không? Con hãy nói có hoặc không nhé", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ Có/Không", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 801, "Fallback xác nhận"],
  ["AI-017", "Chủ đề", "Bắt đầu bài", "Chọn được bài hợp lệ", "Bắt đầu học thôi con", "Đang dùng trong code", "Loa/TTS", "Điều hướng vào bài", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 843, "Phát trước khi mở bài"],
  ["AI-018", "Chủ đề / Lỗi", "Không tải được bài", "Loader nội dung lỗi", "Bi cô chưa tải được bài học. Con thử lại sau nhé", "Đang dùng trong code", "Loa/TTS", "Kết thúc phiên chọn", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 731, "Thông báo lỗi nội dung"],
  ["AI-019", "Chủ đề / Lỗi", "Mất trạng thái chủ đề", "Không còn chủ đề đã chọn", "Bi cô chưa chọn được chủ đề. Con thử lại nhé", "Đang dùng trong code", "Loa/TTS", "Kết thúc phiên chọn", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 828, "Thông báo lỗi trạng thái"],
  ["AI-020", "Dịch tiếng Anh", "Chọn chế độ dịch", "Trẻ chọn dịch tiếng Anh", "Con muốn dịch một câu hay dịch liên tục?", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ chế độ", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 297, "Lặp lại nếu câu trả lời ngoài hai lựa chọn"],
  ["AI-021", "Dịch từng câu", "Hướng dẫn thao tác", "Trẻ chọn một câu", "Con bấm nút MAIN để bắt đầu nói. Khi nói xong, con bấm nút MAIN lần nữa nhé. Muốn dừng và gọi mình, con nói dừng lại hoặc con muốn học cái khác.", "Đang dùng trong code", "Loa/TTS", "Điều hướng sang màn giao tiếp", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 351, "Hướng dẫn MAIN hai lần"],
  ["AI-022", "Dịch liên tục", "Hướng dẫn thao tác", "Trẻ chọn liên tục", "Con nói từng câu nhé. Muốn dừng thì nói dừng lại.", "Đang dùng trong code", "Loa/TTS", "Điều hướng và tự mở phiên ghi âm", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 364, "Vào main speaking mode"],
  ["AI-023", "Dịch liên tục / Im lặng", "Không có tiếng lần 1", "Không phát hiện lời nói trong 6 giây", "Cô chưa nghe thấy con nói. Con nói lại nhé.", "Đang dùng trong code", "Loa/TTS", "Mở lượt ghi âm mới", "Có", "APK + Web", "lib/app/ai_speaking_app.dart", 869, "Lần 1 retry"],
  ["AI-024", "Dịch liên tục / Im lặng", "Không có tiếng lần 2", "Tiếp tục không có tiếng", "Tạm biệt con nhé, khi nào con cần gì hãy nhấn MAIN nhé.", "Đang dùng trong code", "Loa/TTS", "Kết thúc nói liên tục", "Không", "APK + Web", "lib/app/ai_speaking_app.dart", 874, "Lần 2 kết thúc"],
  ["AI-025", "Dịch / Không rõ", "ASR không có kết quả", "Không nghe thấy hoặc câu quá ngắn", "Cô chưa nghe thấy con nói. Con nói lại nhé.", "Đang dùng trong code", "Loa/TTS", "Trả về sẵn sàng/ghi âm lại tùy luồng", "Tùy luồng", "APK + Web", "lib/features/conversation/presentation/conversation_controller.dart", 3019, "Thông báo chung của ConversationController"],
  ["AI-026", "Dịch / Tiếng ồn", "Môi trường ồn", "Bộ đo đánh dấu noisyRecording", "Môi trường đang khá ồn. Hãy đưa micro gần hơn, tránh hướng quạt hoặc chuyển sang chỗ yên hơn rồi thử lại.", "Đang dùng trong code", "Loa/TTS + UI", "Yêu cầu thử lại", "Tùy luồng", "APK + Web", "lib/features/conversation/presentation/conversation_controller.dart", 2542, "Câu dài; nên kiểm thử khả năng trẻ hiểu"],
  ["AI-027", "Dịch / Lỗi kỹ thuật", "Web Batch không có transcript", "Finalize trả chuỗi rỗng", "Mình chưa nghe rõ. Con thử nói lại nhé.", "Thông báo kỹ thuật", "Exception/UI", "Báo lỗi cho tầng trên", "Không trực tiếp", "Web", "lib/features/voice_navigation/data/web_batch_streaming_speech_input.dart", 229, "Không chắc luôn được phát bằng TTS; giữ để audit"],
  ["AI-028", "Từ vựng", "Không tải được dữ liệu", "Vocabulary loader lỗi", "Mình chưa tải được từ vựng. Con thử lại sau nhé.", "Đang dùng trong code", "Loa/TTS", "Kết thúc luồng từ vựng", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 422, "Thông báo lỗi dữ liệu"],
  ["AI-029", "Từ vựng", "Chọn bộ từ", "Không có từ mới trong gia đình", "Con muốn luyện lại hay nghe những ngôi sao của con?", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ lựa chọn", "Có", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 435, "Cũng lặp lại khi không hiểu lựa chọn"],
  ["AI-030", "Từ vựng", "Mở bộ từ mới", "Có từ phụ huynh mới thêm", "Ở đây đã có từ mới. Chúng mình cùng học nhé.", "Đang dùng trong code", "Loa/TTS", "Đọc lần lượt từ Anh và nghĩa Việt", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 443, "Mở đầu phần từ mới"],
  ["AI-031", "Từ vựng", "Đọc từng mục", "Có dữ liệu từ vựng", "{từ tiếng Anh} → {nghĩa tiếng Việt}", "Ghép động từ dữ liệu", "Loa/TTS", "Đọc mục tiếp theo", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 568, "Tiếng Anh dùng locale en-US; nghĩa dùng tiếng Việt"],
  ["AI-032", "Từ vựng", "Chuyển bộ từ", "Đọc xong từ mới", "Mình qua phần luyện lại và ngôi sao nhé.", "Đang dùng trong code", "Loa/TTS", "Đọc bộ luyện lại rồi ngôi sao", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 449, "Chuyển pha"],
  ["AI-033", "Từ vựng", "Tiêu đề bộ luyện lại", "Bộ luyện lại có dữ liệu", "Phần luyện lại.", "Đang dùng trong code", "Loa/TTS", "Đọc các từ trong bộ", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 454, "Tiêu đề được nói"],
  ["AI-034", "Từ vựng", "Bộ luyện lại trống", "Không có mục review", "Phần luyện lại chưa có từ nào.", "Đang dùng trong code", "Loa/TTS", "Chuyển sang bộ tiếp theo", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 455, "Thông báo rỗng"],
  ["AI-035", "Từ vựng", "Tiêu đề bộ ngôi sao", "Bộ ngôi sao có dữ liệu", "Phần ngôi sao.", "Đang dùng trong code", "Loa/TTS", "Đọc các từ trong bộ", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 460, "Tên thay thế ở luồng chọn trực tiếp: Những ngôi sao của con."],
  ["AI-036", "Từ vựng", "Bộ ngôi sao trống", "Không có mục star", "Phần ngôi sao chưa có từ nào.", "Đang dùng trong code", "Loa/TTS", "Chuyển sang kết thúc", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 461, "Luồng trực tiếp dùng câu Con chưa có từ ngôi sao nào."],
  ["AI-037", "Từ vựng", "Kết thúc", "Đọc xong các bộ", "Mình đã học xong từ vựng rồi.", "Đang dùng trong code", "Loa/TTS", "Kết thúc luồng", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 465, "Kết thúc từ vựng"],
  ["AI-038", "Luyện nghe / MAIN", "Tiếp tục", "Nhận intent tiếp tục", "Cùng học tiếp nhé", "Đang dùng trong code", "Loa/TTS", "Resume module", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 610, "Phản hồi trước hành động"],
  ["AI-039", "Luyện nghe / MAIN", "Nghe lại hiện tại", "Nhận intent nghe lại", "Mình nghe lại câu này nhé", "Đang dùng trong code", "Loa/TTS", "Replay câu hiện tại", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 611, "Phản hồi trước hành động"],
  ["AI-040", "Luyện nghe / MAIN", "Câu tiếp theo", "Nhận intent câu tiếp", "Mình học câu tiếp theo nhé", "Đang dùng trong code", "Loa/TTS", "Đi câu tiếp", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 612, "Phản hồi trước hành động"],
  ["AI-041", "Luyện nghe / MAIN", "Câu trước", "Nhận intent câu trước", "Mình nghe lại câu trước nhé", "Đang dùng trong code", "Loa/TTS", "Đi câu trước", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 613, "Phản hồi trước hành động"],
  ["AI-042", "Luyện nghe / MAIN", "Bài tiếp theo", "Nhận intent bài tiếp", "Mình chuyển sang bài tiếp theo nhé", "Đang dùng trong code", "Loa/TTS", "Mở bài tiếp", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 614, "Phản hồi trước hành động"],
  ["AI-043", "Luyện nghe / MAIN", "Bài trước", "Nhận intent bài trước", "Mình quay lại bài trước nhé", "Đang dùng trong code", "Loa/TTS", "Mở bài trước", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 615, "Phản hồi trước hành động"],
  ["AI-044", "Luyện nghe / MAIN", "Học lại từ đầu", "Nhận intent restart", "Mình học lại bài này từ đầu nhé", "Đang dùng trong code", "Loa/TTS", "Reset tiến độ bài và bắt đầu lại", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 616, "Cần QA việc xóa bản ghi/trạng thái cũ"],
  ["AI-045", "MAIN / Dừng", "Dừng hoạt động", "Nhận intent dừng", "Đã dừng.", "Đang dùng trong code", "Loa/TTS", "Pause/stop module", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 617, "Xuất hiện ở nhiều màn"],
  ["AI-046", "Luyện nghe / MAIN", "Kết thúc bài", "Nhận intent không học nữa", "Mình kết thúc bài học nhé", "Đang dùng trong code", "Loa/TTS", "Thoát về trang phù hợp", "Không", "APK + Web", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", 618, "Rời module"],
  ["AI-047", "Luyện nghe / Hướng dẫn", "Bắt đầu luyện câu", "Trước khi phát mẫu", "Nói theo cô nhé.", "Đang dùng trong code", "Loa/TTS", "Phát câu tiếng Anh", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 54, "Guide V2"],
  ["AI-048", "Luyện nghe / Hướng dẫn", "Mời trẻ nói", "Sau câu Anh và nghĩa Việt", "Bây giờ đến lượt con. Con nói lại nhé.", "Đang dùng trong code", "Loa/TTS", "Mở ghi âm tối đa theo cấu hình", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 59, "Guide V2"],
  ["AI-049", "Luyện nghe / Hoàn tất", "Chọn sau bài", "Học hết câu", "Con hãy nói “Luyện lại từ đầu” hoặc “Bài tiếp theo” nhé.", "Đang dùng trong code", "Loa/TTS", "Mở mic chờ lựa chọn", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 64, "Câu lựa chọn cuối bài"],
  ["AI-050", "Luyện nghe / Hoàn tất", "Không hiểu lựa chọn", "Câu nói không khớp hai lựa chọn", "Nói lại lựa chọn của con nhé", "Đang dùng trong code", "Loa/TTS", "Mở mic lại", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 69, "Fallback lựa chọn cuối bài"],
  ["AI-051", "Luyện nghe / Hoàn tất", "Hết chủ đề", "Không còn bài tiếp theo", "Con đã học xong chủ đề này rồi. Con chọn tiếp chủ đề mới nhé.", "Đang dùng trong code", "Loa/TTS", "Quay về chọn chủ đề", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 74, "Cũng dùng trong lesson_practice_screen"],
  ["AI-052", "Luyện nghe / Đánh giá", "Phát âm đạt", "Kết quả thành công", "Con làm tốt lắm", "Đang dùng trong code", "Loa/TTS", "Tự chuyển câu", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 79, "Khen ngắn"],
  ["AI-053", "Luyện nghe / Không rõ", "Không nghe rõ", "Ghi âm không đủ rõ", "Cô chưa nghe rõ. Con nói lại nhé.", "Đang dùng trong code", "Loa/TTS", "Mở ghi âm lại", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 84, "Fallback trong luyện phát âm"],
  ["AI-054", "Luyện nghe / Sai phạm vi", "Câu ngoài nội dung", "Trẻ nói nội dung không đúng bài", "Con tập trung học đi", "Đang dùng trong code", "Loa/TTS", "Giữ câu hiện tại", "Tùy luồng", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 89, "Giọng điệu khá cứng; nên xem xét thay bằng câu tích cực"],
  ["AI-055", "Luyện nghe / Chuyển câu", "Bỏ qua câu", "Quá số lần thử", "Mình cùng học câu khác nhé!", "Đang dùng trong code", "Loa/TTS", "Chuyển câu", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 94, "Guide V2"],
  ["AI-056", "Luyện nghe / Sửa phát âm", "Gần đạt", "Điểm gần ngưỡng", "Gần được rồi! Con nghe lại câu này nhé.", "Đang dùng trong code", "Loa/TTS", "Phát lại mẫu", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 99, "Khích lệ"],
  ["AI-057", "Luyện nghe / Sửa phát âm", "Thử lần nữa", "Sau khi nghe lại mẫu", "Bây giờ con thử nói lại lần nữa nhé.", "Đang dùng trong code", "Loa/TTS", "Mở ghi âm lại", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 104, "Guide V2"],
  ["AI-058", "Luyện nghe / Sửa phát âm", "Chuyển sau nhiều lần", "Vẫn chưa đạt", "Con đã cố gắng rồi! Mình sẽ luyện thêm sau. Cùng học câu tiếp nào.", "Đang dùng trong code", "Loa/TTS", "Chuyển câu", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 109, "Khích lệ rồi chuyển"],
  ["AI-059", "Luyện nghe / Mở bài", "Lần đầu", "Vào bài chưa từng học", "Chào con! Hôm nay mình bắt đầu với bài “{tên bài}”. Con nghe cô trước, rồi nói lại theo cô. Nếu muốn nghe lại hoặc dừng, con bấm nút Main nhé.", "Ghép động từ dữ liệu", "Loa/TTS", "Bắt đầu bài", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 121, "Tên bài ghép động"],
  ["AI-060", "Luyện nghe / Mở bài", "Bài mới", "Vào bài mới", "Hôm nay mình học bài “{tên bài}” nhé. Bắt đầu nào!", "Ghép động từ dữ liệu", "Loa/TTS", "Bắt đầu bài", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 127, "Tên bài ghép động"],
  ["AI-061", "Luyện nghe / Tiếp tục", "Resume", "Có tiến độ trước đó", "Mình học tiếp bài “{tên bài}” nhé. Bắt đầu từ chỗ lúc trước nào!", "Ghép động từ dữ liệu", "Loa/TTS", "Tiếp tục từ tiến độ", "Không", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 131, "Tên bài ghép động"],
  ["AI-062", "Luyện nghe / Kết bài", "Hoàn tất bài", "Học xong bài", "Giỏi lắm! Con đã học xong bài “{tên bài}” rồi. Con muốn luyện lại từ đầu hay học bài tiếp theo?", "Ghép động từ dữ liệu", "Loa/TTS", "Mở mic chờ lựa chọn", "Có", "APK + Web", "lib/features/listening/domain/lesson_guide_flow.dart", 143, "Tên bài ghép động"],
  ["AI-063", "Luyện nghe / Biên", "Đang ở câu đầu", "Yêu cầu câu trước tại câu 1", "Con đang ở câu đầu tiên rồi.", "Đang dùng trong code", "Loa/TTS", "Giữ câu hiện tại", "Không", "APK + Web", "lib/features/listening/presentation/lesson_practice_screen.dart", 342, "Thông báo biên"],
  ["AI-064", "Luyện nghe / Biên", "Đang ở bài đầu", "Yêu cầu bài trước tại bài 1", "Con đang ở bài đầu tiên rồi.", "Đang dùng trong code", "Loa/TTS", "Giữ bài hiện tại", "Không", "APK + Web", "lib/features/listening/presentation/lesson_practice_screen.dart", 363, "Thông báo biên"],
  ["AI-065", "Luyện nghe / Tổng kết", "Chưa đủ thời gian", "Yêu cầu đi tiếp khi tổng quan chưa mở khóa", "Con nghe tổng quan thêm một chút nhé.", "Đang dùng trong code", "Loa/TTS", "Tiếp tục tổng quan", "Không", "APK + Web", "lib/features/listening/presentation/lesson_review_screen.dart", 431, "Thông báo giới hạn"],
  ["AI-066", "Luyện nghe / Tổng kết", "Không có mục trước", "Yêu cầu quay lại trong tổng kết", "Đây là phần tổng kết của bài học rồi.", "Đang dùng trong code", "Loa/TTS", "Giữ màn tổng kết", "Không", "APK + Web", "lib/features/listening/presentation/lesson_review_screen.dart", 447, "Thông báo ngữ cảnh"],
  ["AI-067", "Luyện nghe / Tổng kết", "Không có bài tiếp", "Yêu cầu bài tiếp khi không có", "Chưa có bài tiếp theo.", "Đang dùng trong code", "Loa/TTS", "Giữ màn hiện tại", "Không", "APK + Web", "lib/features/listening/presentation/lesson_review_screen.dart", 452, "Thông báo biên"],
  ["AI-068", "Bài hát", "Lệnh không khả dụng", "Yêu cầu điều hướng khi bài hát chưa xong", "Con hãy học xong bài hát này trước nhé.", "Đang dùng trong code", "Loa/TTS", "Giữ màn bài hát", "Không", "APK + Web", "lib/features/listening/presentation/song_karaoke_screen.dart", 594, "Bài hát giữ ảnh nền riêng"],
  ["AI-069", "Wake-word cũ", "Xác nhận đánh thức", "Đường wake word dùng prompt mặc định", "Pipo nghe đây", "Đang dùng trong code", "Loa/TTS", "Mở cửa sổ lệnh", "Có", "APK + Web", "lib/features/voice_navigation/application/voice_navigation_controller.dart", 375, "Đường cũ/tuỳ cấu hình; cần xác nhận còn bật trong production"],
  ["AI-070", "Lỗi thao tác", "Module bận/lỗi", "Active learning module ném lỗi", "Bi cô chưa thực hiện được. Con thử lại nhé.", "Đang dùng trong code", "Loa/TTS", "Giữ trạng thái hiện tại", "Không", "APK + Web", "lib/app/ai_speaking_app.dart", 595, "Fallback kỹ thuật"],
];

const intentRows = [
  ["INT-001", "Dừng toàn cục", "Mọi module", "Dừng lại", "Dừng; Thôi; Không học nữa; Tạm dừng; Stop; Dừng đi; Thôi nha; Không muốn nữa; Con không thích; Im lặng", "Dừng/pause hoạt động hiện tại", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "74-88", "", "", "", "", ""],
  ["INT-002", "Học chủ đề", "Chọn chức năng", "Học theo chủ đề", "Bắt đầu học; Con muốn học; Học chủ đề; Học tình huống; Con muốn học theo Chủ đề; Học đi; Con học; Học cái này; Học bây giờ; Chủ đề", "Vào luồng chọn tuổi/chủ đề", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "90-104", "", "", "", "", ""],
  ["INT-003", "Học từ mới", "Chọn chức năng", "Học từ mới", "Con muốn học từ; Học từ vựng; Luyện từ mới; Từ mới; Học từ; Học mới; Con học từ này", "Vào luồng từ vựng", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "106-117", "", "", "", "", ""],
  ["INT-004", "Dịch tiếng Anh", "Chọn chức năng", "Dịch sang tiếng Anh", "Dịch; Con muốn dịch; Dịch giúp con; Dịch tiếng Anh; Dịch cho con; Dịch đi; Con muốn nói tiếng Anh; Dịch câu này; Dịch cái này; Dịch từ", "Hỏi chế độ dịch", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "119-133", "", "", "", "", ""],
  ["INT-005", "Dịch một câu", "Chọn chế độ dịch", "Dịch một câu", "Dịch câu này; Dịch chữ này; Phiên dịch; Dịch từng câu; Dịch cho con một câu; Dịch; Dịch câu; Dịch chữ; Câu này tiếng Anh sao; Dịch cái này; Dịch tiếng Anh; Làm sao để nói tiếng Anh; Nói tiếng Anh", "Vào chế độ MAIN bật/tắt ghi âm", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "135-152", "", "", "", "", ""],
  ["INT-006", "Dịch liên tục", "Chọn chế độ dịch", "Dịch liên tục", "Dịch nhiều; Dịch liên tiếp; Dịch tiếp đi; Con nói liên tục; Dịch hoài; Dịch nhiều câu; Dịch tiếp; Nói tiếp", "Vào chế độ ghi âm liên tục", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "154-166", "", "", "", "", ""],
  ["INT-007", "Tiếp tục bài", "Trong bài học", "Tiếp tục học", "Học tiếp; Tiếp tục bài này; Học tiếp đi; Con muốn học nữa", "Resume module", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "168-177", "", "", "", "", ""],
  ["INT-008", "Câu tiếp theo", "Trong bài học", "Câu tiếp theo", "Qua câu tiếp; Câu sau; Nói câu khác; Câu nữa; Tiếp đi; Câu tiếp", "Sang câu tiếp", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "179-190", "", "", "", "", ""],
  ["INT-009", "Câu trước", "Trong bài học", "Câu trước", "Quay lại câu trước; Lùi một câu; Câu hồi nãy; Quay lại; Về trước", "Quay về câu trước", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "192-202", "", "", "", "", ""],
  ["INT-010", "Nghe lại câu", "Trong bài học", "Nghe lại", "Nói lại; Đọc lại câu này; Cho con nghe lại; Nghe nữa; Nói lại đi; Lặp lại; Lần nữa", "Phát lại câu hiện tại", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "204-216", "", "", "", "", ""],
  ["INT-011", "Học lại từ đầu", "Trong bài học", "Học lại từ đầu", "Học từ đầu; Làm lại bài này; Học lại; Lại từ đầu", "Reset và học lại bài", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "218-227", "", "", "", "", ""],
  ["INT-012", "Bài tiếp theo", "Trong bài học", "Bài tiếp theo", "Qua bài mới; Bài sau; Bài tiếp; Bài nữa; Học bài khác; Bài mới", "Mở bài tiếp", "Trung bình", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "229-240", "", "", "", "", ""],
  ["INT-013", "Bài trước", "Trong bài học", "Bài trước", "Quay lại bài trước; Bài hồi nãy; Bài trước đó; Quay lại bài cũ; Bài lúc nãy", "Mở bài trước", "Trung bình", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "242-252", "", "", "", "", ""],
  ["INT-014", "Luyện lại từ vựng", "Từ vựng", "Luyện lại", "Học lại phần chưa thuộc; Luyện từ khó; Nói lại; Học lại; Mấy câu khó; Luyện nữa", "Đọc collection review", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "254-265", "", "", "", "", ""],
  ["INT-015", "Ngôi sao từ vựng", "Từ vựng", "Ngôi sao của con", "Xem ngôi sao; Học phần con đã thuộc; Ngôi sao; Con giỏi; Xem sao; Muốn ngôi sao; Nhìn ngôi sao", "Đọc collection star", "Cao", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "267-279", "", "", "", "", ""],
  ["INT-016", "Trợ giúp", "Toàn cục", "Giúp con với", "Con không biết; Phải làm gì?; Nói lại đi; Giúp; Giúp con; Không biết; Không hiểu; Sao đây?; Nói gì?", "Mở trợ giúp/nhắc lại theo trạng thái", "Trung bình", "lib/features/voice_navigation/domain/controlled_speech_lexicon.dart", "281-295", "", "", "", "", ""],
  ["INT-017", "Rời luyện nói", "Dịch từng câu/liên tục", "Con muốn học cái khác", "Cái gì khác để học; Gì khác để học; Có gì khác không; Học thử khác; Học môn khác; Học bài khác; Đổi sang học khác; Không muốn luyện nói nữa; Dừng luyện nói; Thoát luyện nói", "Dừng dịch và gọi trợ lý MAIN", "Cao", "lib/features/voice_navigation/application/main_speaking_command_resolver.dart", "15-34", "", "", "", "", ""],
  ["INT-018", "Dừng dịch", "Dịch từng câu/liên tục", "Dừng lại", "Con muốn dừng; Dừng dịch; Dừng dịch liên tục; Ngừng; Con muốn ngừng; Ngừng dịch; Thôi dừng lại; Không dịch nữa; Con không muốn dịch nữa; Thoát dịch", "Dừng phiên dịch", "Cao", "lib/features/voice_navigation/application/main_speaking_command_resolver.dart", "38-59", "", "", "", "", ""],
  ["INT-019", "Có", "Xác nhận học lại", "Có", "Có ạ; Dạ có; Con có; Muốn học lại; Học lại; Tiếp tục; Học tiếp", "Xác nhận học lại", "Cao", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", "925-933", "", "", "", "", ""],
  ["INT-020", "Không", "Xác nhận học lại", "Không", "Không ạ; Dạ không; Con không; Không đâu; Không muốn; Không học; Dừng học", "Không học lại; quay về chọn chủ đề", "Cao", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", "935-943", "", "", "", "", ""],
  ["INT-021", "Số tuổi/chủ đề/bài", "Chọn bằng số", "Một đến mười lăm", "1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15 và dạng chữ tiếng Việt", "Trích số cho tuổi/chủ đề/bài", "Cao", "lib/features/voice_navigation/application/main_voice_assistant_flow.dart", "1011-1031", "", "", "", "", ""],
  ["INT-022", "Wake word", "Chế độ đánh thức cũ", "Hey Pipo", "Hey Pico; Hey Piko; Hay Pico; Hey Pi Co; Hay Pi Co; Hey Bi Co; Hay Bi Co; Hey Bico; Hay Bico; Hey Bigo; Hay Bigo; Ê Pico; Ê Pi Co", "Mở trợ lý giọng nói", "Thấp", "lib/features/voice_navigation/application/voice_navigation_intent_resolver.dart", "34-49", "", "", "", "", ""],
  ["INT-023", "Trang giao tiếp", "Điều hướng chung", "Giao tiếp", "Luyện giao tiếp; Trang giao tiếp; Luyện nói; Nói chuyện", "Mở trang giao tiếp", "Trung bình", "lib/features/voice_navigation/application/voice_navigation_intent_resolver.dart", "84-94", "", "", "", "", ""],
  ["INT-024", "Lịch sử/Cài đặt", "Điều hướng chung", "Lịch sử / Cài đặt", "Lịch sử gần đây; Lịch sử học; Câu đã học; Mở cài đặt; Thiết lập; Đổi giao diện", "Mở trang tương ứng", "Thấp", "lib/features/voice_navigation/application/voice_navigation_intent_resolver.dart", "96-120", "", "", "", "", ""],
];

const silenceRows = [
  ["SIL-001", "Trợ lý MAIN", "Không nói lần 1", "6 giây", "Con muốn làm gì?", "Phát câu nhắc rồi tự mở mic lại", "Có", "1", "lib/features/voice_navigation/application/voice_navigation_controller.dart", "471-480", "Đang dùng"],
  ["SIL-002", "Trợ lý MAIN", "Không nói lần 2", "6 giây tiếp theo", "Khi nào sẵn sàng, con nhấn MAIN gọi mình nhé.", "Kết thúc phiên MAIN và reset", "Không", "2", "lib/features/voice_navigation/application/voice_navigation_controller.dart", "482-493", "Đang dùng"],
  ["SIL-003", "Dịch liên tục", "Không nói/quá ngắn lần 1", "6 giây", "Cô chưa nghe thấy con nói. Con nói lại nhé.", "Tự bắt đầu lượt ghi âm mới", "Có", "1", "lib/app/ai_speaking_app.dart", "853-889", "Đang dùng"],
  ["SIL-004", "Dịch liên tục", "Không nói/quá ngắn lần 2", "6 giây tiếp theo", "Tạm biệt con nhé, khi nào con cần gì hãy nhấn MAIN nhé.", "Kết thúc chế độ nói liên tục", "Không", "2", "lib/app/ai_speaking_app.dart", "874-878", "Đang dùng"],
  ["SIL-005", "Ghi âm giao tiếp", "ASR rỗng/không phát hiện tiếng", "Mặc định 3 giây; có luồng truyền 6 hoặc 12 giây", "Cô chưa nghe thấy con nói. Con nói lại nhé.", "Dừng lượt hiện tại; có thể phát lời nhắc tùy cấu hình", "Tùy luồng", "Không đếm chung", "lib/features/conversation/presentation/conversation_controller.dart", "1294-1298, 3019-3034", "Đang dùng"],
  ["SIL-006", "Ghi âm giao tiếp", "Môi trường bị đánh dấu ồn", "Khi kết thúc lượt không có kết quả", "Môi trường đang khá ồn. Hãy đưa micro gần hơn, tránh hướng quạt hoặc chuyển sang chỗ yên hơn rồi thử lại.", "Yêu cầu điều chỉnh vị trí rồi thử lại", "Tùy luồng", "Không đếm chung", "lib/features/conversation/presentation/conversation_controller.dart", "2542-2546", "Đang dùng"],
  ["SIL-007", "Luyện phát âm", "Không nghe rõ bản ghi", "Sau lượt ghi âm", "Cô chưa nghe rõ. Con nói lại nhé.", "Mở lượt luyện lại", "Có", "Theo số lần thử câu", "lib/features/listening/domain/lesson_guide_flow.dart", "84", "Đang dùng"],
  ["SIL-008", "Hoàn tất bài", "Không hiểu Luyện lại/Bài tiếp", "Sau khi trẻ trả lời", "Nói lại lựa chọn của con nhé", "Mở mic chờ lựa chọn lại", "Có", "Chưa thấy giới hạn riêng", "lib/features/listening/domain/lesson_guide_flow.dart", "69", "Đang dùng"],
  ["SIL-009", "Web Batch", "Finalize không có transcript", "Sau khi upload/finalize", "Mình chưa nghe rõ. Con thử nói lại nhé.", "Ném lỗi WEB_BATCH_NO_SPEECH cho tầng trên", "Không trực tiếp", "Không đếm chung", "lib/features/voice_navigation/data/web_batch_streaming_speech_input.dart", "225-231", "Thông báo kỹ thuật; cần xác nhận có được TTS phát hay chỉ hiện UI"],
];

const fallbackRows = [
  ["FB-001", "Chọn chức năng gốc", "Câu không khớp học chủ đề / từ mới / dịch", "Lặp lại: Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?", "Con muốn đi chơi", "Cô chưa hiểu ý con. Con có thể nói: học theo chủ đề, học từ mới hoặc dịch sang tiếng Anh.", "Mở mic lại", "Cô vẫn chưa hiểu. Khi nào sẵn sàng, con nhấn MAIN gọi cô nhé.", "Kết thúc phiên, giữ trạng thái an toàn", "Khẩn cấp", "Đề xuất; chưa có trong code"],
  ["FB-002", "Chọn chế độ dịch", "Câu không khớp một câu / liên tục", "Lặp lại: Con muốn dịch một câu hay dịch liên tục?", "Con muốn nói tiếng Anh nhanh", "Cô chưa hiểu. Con nói “một câu” hoặc “liên tục” nhé.", "Mở mic lại", "Mình tạm quay lại. Con muốn học theo chủ đề, học từ mới hay dịch sang tiếng Anh?", "Quay về chọn chức năng", "Cao", "Đề xuất; chưa có fallback hai cấp"],
  ["FB-003", "Chọn tuổi", "Không có số tuổi hoặc câu ngoài phạm vi", "Hỏi lại kèm ví dụ: Con 6 tuổi", "Con học lớp một", "Cô chưa nhận được tuổi. Con nói: con 6 tuổi, hoặc nhờ bố mẹ chọn tuổi trong ứng dụng nhé.", "Mở mic lại", "Mình chưa chọn được tuổi. Con nhờ bố mẹ giúp nhé.", "Dừng điều hướng giọng nói; giữ màn chọn tuổi", "Cao", "Đề xuất thêm biến thể lớp học nếu nội dung cho phép"],
  ["FB-004", "Chọn chủ đề", "Không có số hoặc số ngoài phạm vi", "Đọc lại khoảng số hợp lệ", "Con thích động vật", "Con hãy nói số chủ đề, ví dụ “chủ đề số 3” nhé.", "Mở mic lại", "Mình chưa chọn được chủ đề. Con có thể chọn trên màn hình nhé.", "Giữ màn danh sách chủ đề", "Cao", "Có thể phát triển nhận tên chủ đề ở giai đoạn sau"],
  ["FB-005", "Chọn bài", "Không có số hoặc số ngoài phạm vi", "Đọc lại khoảng số bài hợp lệ", "Con muốn bài về trường học", "Con hãy nói số bài, ví dụ “bài số 1” nhé.", "Mở mic lại", "Mình chưa chọn được bài. Con có thể chọn trên màn hình nhé.", "Giữ màn chủ đề", "Cao", "Có thể phát triển nhận tên bài ở giai đoạn sau"],
  ["FB-006", "Trong bài luyện nghe", "Câu không khớp câu tiếp/câu trước/dừng/không học nữa", "Lặp lại toàn bộ câu hỏi điều hướng trong bài", "Con muốn đi chơi", "Cô chưa hiểu. Con có thể nói: câu tiếp theo, câu trước, dừng lại hoặc không học nữa.", "Mở mic lại và giữ nguyên câu", "Mình vẫn chưa hiểu. Cô sẽ tiếp tục câu hiện tại nhé.", "Resume câu hiện tại; không tự chuyển sai", "Khẩn cấp", "Đúng ví dụ người dùng nêu; tránh câu “Con tập trung học đi” quá cứng"],
  ["FB-007", "Xác nhận học lại chủ đề", "Không khớp Có/Không", "Hỏi lại và yêu cầu nói có hoặc không", "Con muốn bài khác", "Con hãy nói “có” để học lại, hoặc “không” để chọn chủ đề khác nhé.", "Mở mic lại", "Mình sẽ đưa con về chọn chủ đề khác nhé.", "Quay về danh sách chủ đề", "Trung bình", "Đề xuất mặc định an toàn sau 2 lần"],
  ["FB-008", "Từ vựng: chọn luyện lại/ngôi sao", "Không khớp hai bộ", "Lặp lại câu hỏi hiện tại", "Con muốn chơi", "Con nói “luyện lại” hoặc “ngôi sao” nhé.", "Mở mic lại", "Mình tạm dừng học từ vựng. Khi nào sẵn sàng, con nhấn MAIN nhé.", "Kết thúc luồng từ vựng", "Trung bình", "Đề xuất fallback hai cấp"],
  ["FB-009", "Dịch từng câu/liên tục", "Trẻ nói lệnh khác hoạt động hoặc dừng", "Một số cụm đã được tách khỏi pipeline dịch; câu khác vẫn có thể bị dịch như nội dung", "Con muốn học bài", "Con muốn dừng dịch để học theo chủ đề hay học từ mới phải không?", "Xác nhận chuyển luồng; không dịch câu lệnh", "Cô chưa hiểu. Con nói “dừng lại” để gọi trợ lý nhé.", "Giữ chế độ dịch hoặc dừng theo lựa chọn rõ", "Khẩn cấp", "Cần test tránh dịch nhầm lệnh điều hướng thành câu tiếng Anh"],
  ["FB-010", "Hoàn tất bài", "Không khớp Luyện lại từ đầu/Bài tiếp theo", "Nói: Nói lại lựa chọn của con nhé", "Con muốn về nhà", "Con nói “luyện lại từ đầu” hoặc “bài tiếp theo” nhé.", "Mở mic lại", "Mình sẽ dừng ở đây. Khi nào muốn học tiếp, con nhấn MAIN nhé.", "Giữ tiến độ hoàn thành và thoát an toàn", "Cao", "Đề xuất thêm giới hạn retry"],
];

const sourceRows = [
  ["Nguồn 1", "main_voice_assistant_flow.dart", "Luồng hội thoại MAIN, chọn chức năng, chủ đề, bài, dịch, từ vựng và lệnh trong bài", "Đã rà"],
  ["Nguồn 2", "controlled_speech_lexicon.dart", "Bộ câu trẻ hiện được nhận dạng theo intent", "Đã rà"],
  ["Nguồn 3", "voice_navigation_controller.dart", "Thời gian im lặng, retry và kết thúc MAIN", "Đã rà"],
  ["Nguồn 4", "ai_speaking_app.dart", "Retry im lặng và kết thúc nói liên tục", "Đã rà"],
  ["Nguồn 5", "conversation_controller.dart", "Không nghe thấy, môi trường ồn và prompt giao tiếp", "Đã rà"],
  ["Nguồn 6", "lesson_guide_flow.dart", "Lời dẫn luyện nghe, sửa phát âm và kết bài", "Đã rà"],
  ["Nguồn 7", "lesson_*_screen.dart / song_karaoke_screen.dart", "Câu phản hồi theo trạng thái màn học và bài hát", "Đã rà"],
  ["Nguồn 8", "main_speaking_command_resolver.dart", "Lệnh dừng/rời chế độ dịch", "Đã rà"],
];

const wb = Workbook.create();
const overview = wb.worksheets.add("Tổng quan");
const assistant = wb.worksheets.add("Câu trợ lý");
const intents = wb.worksheets.add("Ý định & câu trẻ");
const silence = wb.worksheets.add("Im lặng & không rõ");
const fallback = wb.worksheets.add("Fallback ngoài phạm vi");
const sources = wb.worksheets.add("Nguồn rà soát");

const colors = {
  navy: "#173B63",
  blue: "#1F4E78",
  cyan: "#DCEEFF",
  green: "#E2F0D9",
  yellow: "#FFF2CC",
  peach: "#FCE4D6",
  purple: "#E4DFEC",
  light: "#F6F8FB",
  border: "#D6DEE8",
  text: "#15233B",
  white: "#FFFFFF",
  red: "#C00000",
};

function columnName(n) {
  let s = "";
  let v = n;
  while (v > 0) {
    v -= 1;
    s = String.fromCharCode(65 + (v % 26)) + s;
    v = Math.floor(v / 26);
  }
  return s;
}

function writeTitle(sheet, title, subtitle, lastCol) {
  sheet.mergeCells(`A1:${lastCol}1`);
  sheet.getRange("A1").values = [[title]];
  sheet.getRange(`A1:${lastCol}1`).format = {
    fill: colors.navy,
    font: { bold: true, color: colors.white, size: 18 },
    verticalAlignment: "center",
  };
  sheet.getRange(`A1:${lastCol}1`).format.rowHeight = 32;
  sheet.mergeCells(`A2:${lastCol}2`);
  sheet.getRange("A2").values = [[subtitle]];
  sheet.getRange(`A2:${lastCol}2`).format = {
    fill: colors.cyan,
    font: { color: colors.text, italic: true, size: 10 },
    wrapText: true,
    verticalAlignment: "center",
  };
  sheet.getRange(`A2:${lastCol}2`).format.rowHeight = 30;
}

function writeDataSheet(sheet, title, subtitle, headers, rows, widths, tableName) {
  const lastCol = columnName(headers.length);
  const endRow = 4 + rows.length;
  writeTitle(sheet, title, subtitle, lastCol);
  sheet.getRange(`A4:${lastCol}4`).values = [headers];
  sheet.getRange(`A4:${lastCol}4`).format = {
    fill: colors.blue,
    font: { bold: true, color: colors.white, size: 10 },
    wrapText: true,
    verticalAlignment: "center",
  };
  sheet.getRange(`A4:${lastCol}4`).format.rowHeight = 34;
  if (rows.length) {
    sheet.getRange(`A5:${lastCol}${endRow}`).values = rows;
    sheet.getRange(`A5:${lastCol}${endRow}`).format = {
      font: { color: colors.text, size: 9 },
      wrapText: true,
      verticalAlignment: "top",
    };
    sheet.getRange(`A5:${lastCol}${endRow}`).format.rowHeight = 40;
  }
  widths.forEach((width, index) => {
    sheet.getRange(`${columnName(index + 1)}:${columnName(index + 1)}`).format.columnWidth = width;
  });
  sheet.freezePanes.freezeRows(4);
  sheet.tables.add(`A4:${lastCol}${endRow}`, true, tableName);
  return endRow;
}

// Overview
writeTitle(
  overview,
  "DANH MỤC CÂU THOẠI TRỢ LÝ AI & FALLBACK",
  "Rà từ mã nguồn Flutter hiện tại ngày 21/08/2026. Các câu đề xuất được tách riêng, không được ghi nhầm là đã triển khai.",
  "H",
);
overview.getRange("A4:B4").values = [["Chỉ số", "Số lượng"]];
overview.getRange("A4:B4").format = { fill: colors.blue, font: { bold: true, color: colors.white } };
overview.getRange("A5:A8").values = [["Câu trợ lý/ mẫu động"], ["Nhóm ý định của trẻ"], ["Kịch bản im lặng/không rõ"], ["Kịch bản fallback cần chốt"]];
overview.getRange("B5:B8").formulas = [
  ["=COUNTA('Câu trợ lý'!$A$5:$A$500)"],
  ["=COUNTA('Ý định & câu trẻ'!$A$5:$A$500)"],
  ["=COUNTA('Im lặng & không rõ'!$A$5:$A$200)"],
  ["=COUNTA('Fallback ngoài phạm vi'!$A$5:$A$200)"],
];
overview.getRange("A5:B8").format = { fill: colors.light, font: { color: colors.text }, verticalAlignment: "center" };
overview.getRange("A10:H10").merge();
overview.getRange("A10").values = [["CÁCH SỬ DỤNG FILE"]];
overview.getRange("A10:H10").format = { fill: colors.navy, font: { bold: true, color: colors.white } };
overview.getRange("A11:H14").values = [
  ["1", "Sheet “Câu trợ lý”", "Danh sách câu/mẫu câu app đang phát; có nguồn và dòng code.", "", "", "", "", ""],
  ["2", "Sheet “Ý định & câu trẻ”", "Biến thể đang nhận dạng; điền thêm câu tương đương vào 5 cột cuối.", "", "", "", "", ""],
  ["3", "Sheet “Im lặng & không rõ”", "Các mốc timeout, câu AI nói và hành động tiếp theo.", "", "", "", "", ""],
  ["4", "Sheet “Fallback ngoài phạm vi”", "So sánh hành vi hiện tại với phương án đề xuất hai cấp; dùng để chốt nội dung trước khi code.", "", "", "", "", ""],
];
overview.getRange("A11:H14").format = { wrapText: true, verticalAlignment: "center", font: { color: colors.text } };
overview.getRange("A16:D16").values = [["Nhãn", "Ý nghĩa", "Màu", "Lưu ý"]];
overview.getRange("A16:D16").format = { fill: colors.blue, font: { bold: true, color: colors.white } };
overview.getRange("A17:D20").values = [
  ["Đang dùng trong code", "Chuỗi tĩnh đang được gọi", "Xanh lá nhạt", "Có thể trùng ở nhiều luồng"],
  ["Ghép động từ dữ liệu", "Tên bài/số lượng/từ vựng được ghép khi chạy", "Vàng nhạt", "Không phải một câu cố định"],
  ["Thông báo kỹ thuật", "Có thể chỉ là exception/UI, chưa chắc được phát", "Tím nhạt", "Cần QA trên thiết bị"],
  ["Đề xuất", "Chưa có trong code", "Cam nhạt", "Cần duyệt nội dung trước khi triển khai"],
];
overview.getRange("A17:D17").format.fill = colors.green;
overview.getRange("A18:D18").format.fill = colors.yellow;
overview.getRange("A19:D19").format.fill = colors.purple;
overview.getRange("A20:D20").format.fill = colors.peach;
overview.getRange("A17:D20").format.wrapText = true;
overview.getRange("A22:H24").values = [
  ["Kết luận nhanh", "Hiện fallback ngoài phạm vi chủ yếu là lặp lại câu hỏi của trạng thái. Chưa có bộ đếm hai cấp thống nhất cho mọi trạng thái.", "", "", "", "", "", ""],
  ["Ưu tiên nội dung", "Chốt fallback trong bài luyện nghe, chọn chức năng gốc và tránh dịch nhầm lệnh điều hướng trước.", "", "", "", "", "", ""],
  ["Phạm vi", "File này chỉ kiểm kê lời thoại/ý định trong mã Flutter; không thay thế kiểm thử âm thanh thực tế H20, Android hoặc iOS.", "", "", "", "", "", ""],
];
overview.getRange("A22:H24").format = { fill: colors.light, wrapText: true, verticalAlignment: "center", font: { color: colors.text } };
overview.getRange("A:A").format.columnWidth = 20;
overview.getRange("B:B").format.columnWidth = 22;
overview.getRange("C:H").format.columnWidth = 16;
overview.freezePanes.freezeRows(2);

const assistantEnd = writeDataSheet(
  assistant,
  "CÂU TRỢ LÝ AI ĐANG DÙNG",
  "Một dòng là một câu hoặc mẫu câu động. Cột nguồn code giúp đội kỹ thuật truy ngược nhanh.",
  ["ID", "Nhóm luồng", "Trạng thái", "Kích hoạt", "Câu trợ lý (VI)", "Loại", "Kênh", "Hành động sau câu", "Mở mic lại?", "Nền tảng", "Nguồn code", "Dòng", "Ghi chú"],
  assistantRows,
  [10, 20, 20, 24, 48, 20, 14, 25, 13, 14, 42, 9, 34],
  "AssistantPromptsTable",
);
assistant.getRange(`F5:F${assistantEnd}`).conditionalFormats.addCustom('=F5="Đang dùng trong code"', { fill: colors.green });
assistant.getRange(`F5:F${assistantEnd}`).conditionalFormats.addCustom('=F5="Ghép động từ dữ liệu"', { fill: colors.yellow });
assistant.getRange(`F5:F${assistantEnd}`).conditionalFormats.addCustom('=F5="Thông báo kỹ thuật"', { fill: colors.purple });

const intentEnd = writeDataSheet(
  intents,
  "Ý ĐỊNH & CÂU TRẺ ĐANG ĐƯỢC NHẬN",
  "Năm cột cuối để đội nội dung bổ sung câu tương đương. Không sửa trực tiếp cột biến thể đang nhận nếu chưa cập nhật code.",
  ["Intent ID", "Nhóm", "Trạng thái", "Câu chuẩn", "Biến thể đang nhận", "Kết quả/điều hướng", "Ưu tiên", "Nguồn code", "Dòng", "Tương đương mới 1", "Tương đương mới 2", "Tương đương mới 3", "Tương đương mới 4", "Tương đương mới 5"],
  intentRows,
  [11, 20, 19, 22, 55, 28, 13, 42, 11, 24, 24, 24, 24, 24],
  "ChildIntentsTable",
);
intents.getRange(`J5:N${intentEnd}`).format.fill = colors.peach;
intents.getRange(`G5:G${intentEnd}`).dataValidation = { rule: { type: "list", values: ["Khẩn cấp", "Cao", "Trung bình", "Thấp"] } };

const silenceEnd = writeDataSheet(
  silence,
  "IM LẶNG, KHÔNG RÕ & TIẾNG ỒN",
  "Tách riêng thời gian chờ, lần nhắc và hành động sau lời nhắc để tránh hiểu nhầm giữa MAIN, dịch liên tục và luyện nghe.",
  ["ID", "Luồng", "Tình huống", "Mốc thời gian", "Câu AI nói", "Hành động", "Mở mic lại?", "Lần", "Nguồn code", "Dòng", "Trạng thái/ghi chú"],
  silenceRows,
  [10, 21, 25, 18, 52, 30, 14, 14, 44, 18, 34],
  "SilenceCasesTable",
);
silence.getRange(`E5:E${silenceEnd}`).format.fill = colors.yellow;

const fallbackEnd = writeDataSheet(
  fallback,
  "FALLBACK KHI TRẺ NÓI NGOÀI PHẠM VI",
  "Cột hiện tại phản ánh code; các cột đề xuất chưa được triển khai. Đây là bảng làm việc để duyệt câu tương đương và chính sách retry.",
  ["ID", "Ngữ cảnh", "Điều kiện ngoài phạm vi", "Hành vi hiện tại", "Ví dụ câu trẻ", "Đề xuất lần 1", "Hành động lần 1", "Đề xuất lần 2", "Hành động cuối", "Ưu tiên", "Trạng thái"],
  fallbackRows,
  [10, 22, 30, 42, 24, 46, 28, 46, 30, 14, 26],
  "FallbackDesignTable",
);
fallback.getRange(`F5:I${fallbackEnd}`).format.fill = colors.peach;
fallback.getRange(`J5:J${fallbackEnd}`).dataValidation = { rule: { type: "list", values: ["Khẩn cấp", "Cao", "Trung bình", "Thấp"] } };
fallback.getRange(`K5:K${fallbackEnd}`).dataValidation = { rule: { type: "list", values: ["Đề xuất; chưa có trong code", "Đã duyệt nội dung", "Đã triển khai", "Đã kiểm thử"] } };

writeDataSheet(
  sources,
  "NGUỒN MÃ ĐÃ RÀ SOÁT",
  "Danh sách các cụm file chính dùng để lập workbook. Nguồn là code hiện tại trong workspace ngày 21/08/2026.",
  ["ID", "File/cụm file", "Phạm vi", "Trạng thái"],
  sourceRows,
  [12, 42, 70, 16],
  "SourcesTable",
);

// General presentation polish.
for (const sheet of [overview, assistant, intents, silence, fallback, sources]) {
  const used = sheet.getUsedRange();
  if (used) {
    used.format.wrapText = true;
    used.format.verticalAlignment = "top";
  }
}

// Verify workbook structure and formulas before export.
const sheetInspection = await wb.inspect({ kind: "sheet", include: "id,name" });
console.log(sheetInspection.ndjson);
const formulaInspection = await wb.inspect({ kind: "formula", sheetId: "Tổng quan", range: "A1:H30", maxChars: 4000, options: { maxResults: 50 } });
console.log(formulaInspection.ndjson);

const renderTargets = [
  ["Tổng quan", "A1:H24", "01_tong_quan.png"],
  ["Câu trợ lý", "A1:M22", "02_cau_tro_ly.png"],
  ["Ý định & câu trẻ", "A1:N18", "03_y_dinh_cau_tre.png"],
  ["Im lặng & không rõ", "A1:K14", "04_im_lang.png"],
  ["Fallback ngoài phạm vi", "A1:K15", "05_fallback.png"],
  ["Nguồn rà soát", "A1:D13", "06_nguon.png"],
];
for (const [sheetName, range, filename] of renderTargets) {
  const preview = await wb.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(path.join(previewDir, filename), new Uint8Array(await preview.arrayBuffer()));
}

const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outputFile);
console.log(`OUTPUT=${outputFile}`);

