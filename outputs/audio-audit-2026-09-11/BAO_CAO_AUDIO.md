# Đối chiếu audio HOMI với ứng dụng Flutter

> Đây là báo cáo trước khi tích hợp. Audio đã được bổ sung theo yêu cầu tiếp theo của người dùng; xem kết quả và kiểm tra trong [TICH_HOP_AUDIO.md](TICH_HOP_AUDIO.md).

Ngày kiểm tra: 11/09/2026. Phạm vi: mã nguồn trong workspace hiện tại, file TXT người dùng cung cấp và thư mục `D:/Code/HuaMei/App_noi/Tao_audio_11th9`. Đây là kết quả kiểm tra mã nguồn và dữ liệu, không phải xác nhận phiên bản đang cài trên điện thoại.

## Kết luận

Ứng dụng đã triển khai phần lớn luồng học V4/V4.1 được nhắc trong TXT. Tuy nhiên, việc phát audio thu sẵn theo bộ TXT chưa hoàn chỉnh: phần lớn lời nói đang dùng TTS của thiết bị/trình duyệt. Có thể tích hợp bộ MP3 mới với mức độ khớp nội dung cao; cần thêm ánh xạ và nối các điểm phát audio, không chỉ chép thư mục.

Đã đối chiếu toàn bộ 600 Core target, 872 Challenge và 180 Mission trong TXT với dữ liệu ứng dụng, đồng thời kiểm tra manifest của các gói audio. ID, nội dung nói, lựa chọn, đáp án và tham chiếu target của Challenge/Mission đều khớp. So sánh văn bản bỏ qua khoảng trắng và các chỉ dẫn sản xuất `[SFX:...]`; việc khớp lời nói không có nghĩa hiệu ứng đã được triển khai.

## Luồng hiện có và khoảng trống

Luồng chính hiện có: chọn Level/Chủ đề → giới thiệu bài/Hook → Core tiếng Anh → nghỉ 2 giây → nghĩa tiếng Việt → cue mời nói → ghi âm/chấm/feedback → Role-play nếu có → 2 Challenge → mốc hoàn thành → Song nếu có → 4 câu Mission khi đủ Chủ đề → luyện bổ sung nếu chưa đạt → lựa chọn tiếp theo. Có lưu trạng thái để học tiếp theo giai đoạn.

| Nhóm trong TXT | Tình trạng trong mã nguồn | Audio thu sẵn hiện tại |
|---|---|---|
| A. Cue hệ thống, điều hướng, học tiếp | Có lời nhắc và xử lý nhiều trạng thái, có xoay 5 Core speak cue theo target | Các điểm phát chủ yếu gọi TTS; mã/biến/tên file của bộ mới chưa được ánh xạ |
| B. Feedback theo tuổi | Có 5 nhóm tuổi và các trạng thái Correct/Retry/Give/No response/ASR/Skip | Thư viện chọn một câu cố định cho mỗi nhóm/trạng thái; chưa chọn đầy đủ biến thể MP3 theo tuổi |
| C. Hook/Micro-objective | Cả 109 bài có entry; lời entry được ghép vào câu giới thiệu | Dùng TTS; chưa phát các Hook MP3 đã ghép SFX |
| D. Role-play | Có 10 hội thoại, phân lượt HOMI/trẻ và nối sang Challenge | Lượt HOMI dùng TTS. Scenario và opening hint có dữ liệu và UI nhưng chưa được đọc ở bước mở đầu |
| E. Core | Có đầy đủ phát EN → 2 giây → VI → mời nói/ghi âm/feedback | Có sẵn cơ chế tra `englishAudioId`/`vietnameseAudioId`, nhưng chưa có file mới hoặc URL tương ứng nên dùng TTS |
| F. Challenge | 872 câu trong ngân hàng; chọn 2 câu cho mỗi lượt | Màn hình gọi TTS cho prompt và đáp án mẫu; chưa tra MP3 PROMPT/CHOICE |
| G. Mission | 180 câu, ngân hàng theo Level; mỗi lượt 4 câu; có lưu câu đã hoàn thành và luyện bổ sung | Prompt, đáp án và phần ôn vẫn dùng TTS |
| H. Milestone | Có câu mốc Bài/Chủ đề/Level/Khóa và điều kiện hoàn thành Mission | TTS; chưa có bộ milestone MP3 riêng trong thư mục mới |
| I. Song/SFX | 5 bài hát đã có URI asset và file tồn tại | Song đã được nối; chưa thấy phát SFX STAR tại sự kiện nhận sao; SFX trong TXT đã bị bỏ khỏi chuỗi TTS |
| J. Resume | Có Core/Role-play/Challenge/Mission/Reinforcement/Song và checkpoint chọn Chủ đề | Cue học tiếp hiện chủ yếu dùng TTS |

Các điểm có thể kiểm tra trực tiếp:

- [Dữ liệu ứng dụng](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/assets/data/listening_lessons.json:1) ghi `audioProvider: v4-tts-manifest-pending`. Có 109 bài, 601 Core, 872 Challenge, 180 Mission và 10 Role-play.
- [Manifest audio](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/assets/data/listening_audio_manifest_v4.json:1) có 2.435 entry: 2.430 `PENDING_TTS`, 5 `READY_SOURCE_AUDIO` là Song. Không tìm thấy mã production đọc manifest này để resolve đường dẫn; hiện đây chủ yếu là danh mục giao sản xuất và dữ liệu kiểm tra.
- [Core phát audio](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:3339) ưu tiên URI, rồi tra ID, rồi TTS. Toàn bộ URL EN/VI của 601 target đang trống; không có basename Core V4 tương ứng trong `assets/audio`.
- [Tra file theo mã](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/application/lesson_guide_audio_library.dart) yêu cầu basename bằng chính xác audio code, không hiểu cột CSV hoặc hậu tố tốc độ.
- [Giới thiệu/học tiếp](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_intro_screen.dart:189) ghép văn bản theo trạng thái; `_beginIntro` dùng TTS nếu không có `introAudioUri`. Cả 109 bài hiện chưa có intro URL.
- [Challenge và Role-play](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_challenge_screen.dart:291), [Mission](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_mission_screen.dart:353) gọi `speakAndWait` trực tiếp. Model Challenge/Mission chưa có trường URI prompt/choice.
- [Nhận sao](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:1590) lưu sao và đọc giải thích lần đầu, chưa phát SFX STAR tại đây.
- [Mốc hoàn thành](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:1929), [chọn Chủ đề và checkpoint](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/lib/features/listening/presentation/topic_listening_screen.dart:532).

## Bộ audio mới dùng được đến đâu?

| Gói | File/nội dung đã kiểm tra | Mức độ tương thích |
|---|---|---|
| 01 A System cue | 387 MP3 | Dùng được sau khi ánh xạ cue + biến; thiếu một số giá trị được liệt kê bên dưới |
| 02 B Feedback | 53 MP3 | Cần ánh xạ theo tuổi + trạng thái + biến thể + ngôn ngữ |
| 03 C Hook | 97 file bài + 17 SFX | Cả 97 dòng khớp đúng bài và lời nói trong ứng dụng |
| 05 E Core | 1.200 MP3 cho 600 target | 1.200/1.200 ID-ngôn ngữ và lời nói khớp; basename `_EN`/`_VI` phù hợp cơ chế resolver hiện có |
| 06 F Challenge | 2.616 file cho 872 câu + 11 SFX | 872/872 câu khớp; mỗi câu gồm prompt và 2 lựa chọn |
| 07 G Mission | 540 file cho 180 câu | 180/180 câu khớp; mỗi câu gồm prompt và 2 lựa chọn |

Tổng: **4.921 MP3, 189.789.797 byte (~189,8 MB hoặc 181,0 MiB)**. Tất cả 4.893 đường dẫn được liệt kê trong 6 manifest đều tồn tại và có dữ liệu; 28 file còn lại là SFX phụ trợ. Đây là kiểm tra tồn tại/kích thước và metadata, chưa phải kiểm tra giải mã hoặc nghe toàn bộ file.

Các thiếu hụt cần xử lý:

1. **Core “Taxi.”**: ứng dụng có target `C1112-L2-T04-B01-T03`, TXT và gói Core không có. Cần bổ sung audio EN/VI tương ứng hoặc giữ TTS cho riêng target này. 600 target có trong TXT đều khớp ứng dụng; khác biệt là ứng dụng có thêm một target.
2. **12 Hook/Micro-objective của Topic 1**: TXT thực tế chỉ có 97 dòng ở phần C dù dòng kiểm đếm cuối tài liệu ghi 109. Bộ mới có đủ 97 dòng thực tế này, nhưng ứng dụng cần entry cho 109 bài. Danh sách 12 bài thiếu được lưu ở `hooks.missingInPack` trong file kết quả.
3. **36 cue theo tên bài cho 12 bài Topic 1**: thiếu `FIRST_LESSON_INTRO`, `NEXT_LESSON_INTRO`, `RESUME_CORE`. File `unresolved_dynamic_templates.csv` đã liệt kê rõ. Tên của cả 12 bài hiện có trong dữ liệu ứng dụng nên có thể dùng để tạo bổ sung.
4. **Cue số sao**: bộ A chỉ có `REMAINING_STARS` từ 1 đến 9. 13 bài có tổng số sao tối đa lớn hơn 9. Nhóm 3–10 cần xét thêm 10/11/12; nhóm 11–15 cần xét thêm 10/11, hoặc TTS cho giá trị chưa có. Ví dụ `One to Ten` có 10 Core + 2 Challenge = 12 sao.
5. **Role-play và milestone**: không có gói D/H riêng. Toàn bộ 38 câu trong 10 Role-play đều có văn bản tiếng Anh tương ứng trong Core của chính bài, vì vậy có thể tái sử dụng audio Core khi cần đọc mẫu hoặc lượt HOMI. Cần nối thêm lời dẫn/gợi ý đầu hội thoại và milestone; không được tự động đọc mẫu mọi lượt trẻ khi luồng đang yêu cầu trẻ tự nói.
6. **SFX**: tập SFX của gói mới có 23 ID khác nhau; thiếu `CLOCK_CHIME_SINGLE` và `STAR` trong danh sách tham chiếu của TXT. Có 5 hiệu ứng ngữ cảnh bổ sung trong Hook. File Hook và một số prompt Challenge đã ghép SFX: phát file hoàn chỉnh thì không phát thêm cùng SFX lần nữa.

## Cách tích hợp phù hợp

1. Chuyển 6 CSV manifest sang bảng tra audio dùng chung, phân biệt Core, cue động, feedback, Hook, prompt và lựa chọn. Bảo toàn ID nội dung để không làm lệch tiến độ/đáp án.
2. Đưa audio vào asset khai báo trong Flutter hoặc storage tải xuống và cache. Player hiện có hỗ trợ asset, file và URL. Đường dẫn ổ D của máy phát triển không phải đường dẫn khả dụng trên điện thoại. Nếu đóng gói cả bộ thì phần audio tăng thêm khoảng 190 MB.
3. Core có thể gắn trực tiếp vào `audioUrl`/`vietnameseAudioUrl`, hoặc khai báo asset với basename hiện có rồi dùng `englishAudioId`/`vietnameseAudioId`. Ví dụ `C35-L1-T01-B01-T01_EN` → file cùng basename trong `lesson_table_001`.
4. Cue A cần ánh xạ rõ: runtime tìm `CORE_SPEAK_01`, nhưng file mới tên `CORE_SPEAK_01_VI_0.85x.mp3`. Một số ID danh mục cũ cũng khác bộ mới: `FIRST_LESSON` ↔ `FIRST_LESSON_INTRO`, `NEXT_LESSON` ↔ `NEXT_LESSON_INTRO`, `RESUME_LESSON` ↔ `RESUME_CORE`, `RESUME_ROLE_PLAY` ↔ `RESUME_ROLEPLAY`, `MISSION_REMEDIATE` ↔ `REINFORCEMENT_START`. Cue động phải kèm giá trị biến để chọn đúng file.
5. Intro phải phát theo danh sách đoạn phù hợp trạng thái: Topic cue → Lesson cue → Hook/Mục tiêu → Detail transition. Resume phải dùng nhánh resume. Chỉ gắn một `introAudioUrl` cố định cho cả bài sẽ làm mất khác biệt giữa lần đầu, học lại và học tiếp.
6. Nối Challenge/Mission tới `QUESTION_ID_PROMPT` và `QUESTION_ID_CHOICE_1/2`; dùng choice thích hợp khi cần đọc mẫu/đáp án. Prompt hoàn chỉnh đã chứa các lựa chọn, nên không mặc định phát thêm cả hai choice sau prompt.
7. Nối feedback theo tuổi/ngôn ngữ; Role-play scenario/hint; milestone; sự kiện SFX STAR. Giữ trình tự phát xong mới mở mic và xử lý dừng/học tiếp trên H20.
8. Bộ mới đã xử lý tốc độ EN 0,75× và VI 0,85× theo metadata sản xuất. Phát ở tốc độ player 1,0× để tránh làm chậm lần nữa. Player hiện mặc định 1,0×.
9. Giữ TTS cho nội dung còn thiếu, kiểm thử một bài Alphabet, một bài Hook có SFX, một bài Role-play, một lượt Mission có học tiếp và một bài có Song trước khi thay toàn bộ luồng.

[Script import cũ](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/tool/import_listening_audio.dart:7) đòi package `AIV0_A..._AGE..._THEME...` và `audio_manifest.json`. Bộ mới dùng thư mục `01_A_...` và `manifest.csv`, nên không thể dùng script đó nguyên trạng.

## Kiểm chứng

Đã chạy **46 test, tất cả đạt**, trong 8 file: `v4_listening_content_test`, `lesson_guide_flow_v2_test`, `lesson_guide_audio_library_test`, `listening_curriculum_flow_test`, `v4_completion_flow_test`, `lesson_challenge_screen_test`, `lesson_mission_screen_test`, `v4_song_stage_screen_test`.

Test xác nhận các phần logic/model/widget hiện có; không xác nhận chất lượng phát âm của 4.921 MP3 hay trải nghiệm loa/mic trên thiết bị thật. Kết quả này không khẳng định tất cả quy tắc trong TXT đã được kiểm thử đầu-cuối.

- [Kết quả so sánh đầy đủ](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/outputs/audio-audit-2026-09-11/comparison.json)
- [Script đối chiếu](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/outputs/audio-audit-2026-09-11/audit.mjs)
- [Log kiểm thử](D:/Code/HuaMei/App_noi/flutter/16_10th9/speaking-ai-flutter/outputs/audio-audit-2026-09-11/flutter-tests-direct.log)

Lần phân tích này chỉ tạo báo cáo và dữ liệu kiểm chứng trong thư mục outputs; chưa tích hợp bộ audio mới vào ứng dụng.
