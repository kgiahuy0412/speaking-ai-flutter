# Kế hoạch tách module và quản lý audio HOMI

## 1. Mục tiêu

Tách riêng logic của các tính năng để việc sửa một luồng không làm thay đổi hành vi của luồng khác:

- Trợ lý MAIN và điều hướng bằng giọng nói.
- Dịch liên tục.
- Luyện nghe theo chủ đề, Challenge, Level Mission và bài hát.
- Từ vựng.
- BLE, HFP/SCO, micro, SpeechRecognizer, Apple Speech và phát âm thanh.
- Chạy nền Android/iOS.

Kiến trúc đích là **Modular Monolith + một Audio Turn Coordinator dùng chung**. Logic tính năng tách riêng, nhưng tài nguyên vật lý vẫn được một nơi duy nhất phân xử.

## 2. Baseline và nguyên tắc bảo vệ production

- Baseline bất biến: `97261f92ec542b0ac7c0159649648288719a205e`.
- Nhánh production hiện tại: `codex/main-ios-integration`.
- Không triển khai tái cấu trúc trực tiếp trên nhánh production.
- Nhánh đề xuất: `codex/audio-session-modularization`.
- Không force-push nhánh production trong quá trình triển khai.
- Không dùng `git reset --hard` để xử lý lỗi triển khai.
- Không xóa hoặc ghi đè thay đổi có sẵn của người dùng.
- Mỗi giai đoạn phải là một commit độc lập và có thể revert riêng.
- Không thay đổi backend, giao thức BLE, chính sách quyền hoặc nội dung bài học nếu chưa được người dùng chấp thuận.

Trước mỗi giai đoạn, phải chạy và ghi nhận:

```powershell
git branch --show-current
git rev-parse HEAD
git status --short
```

Nếu working tree có thay đổi không thuộc giai đoạn đang làm, phải giữ nguyên và làm việc xung quanh chúng. Nếu không thể làm an toàn, dừng lại và hỏi người dùng.

## 3. Các hành vi bắt buộc phải được giữ nguyên

### Trợ lý và MAIN

- MAIN trên màn hình và MAIN vật lý đi qua cùng một chính sách lệnh.
- MAIN có thể tạm dừng module học đang hoạt động và mở trợ lý.
- Kết thúc trợ lý có thể quay lại đúng module và checkpoint.
- Không tự mở micro khi không có phiên HOMI do người dùng chủ động bắt đầu.

### Dịch liên tục

- Ghi âm tiếng Việt, nhận transcript, sửa transcript, dịch và phát tiếng Anh.
- Khi nói dừng, không được mở lại micro dịch; phải chuyển sang micro điều hướng của trợ lý.
- Online và offline fallback giữ nguyên thứ tự đang có.
- Không thêm request backend hoặc bước xử lý làm tăng độ trễ nếu chưa có số đo chứng minh.

### Luyện nghe

- Luồng overview, core lesson, retry, Challenge, Level Mission, song và completion giữ nguyên.
- Evaluator do caller truyền vào luôn được tôn trọng.
- Chấm offline/online và định dạng WAV/M4A/WebM giữ nguyên.
- MAIN và nút ảo phải dừng hoạt động hiện tại trước khi thực hiện lệnh mới.
- Không dùng sự tồn tại của file ghi âm để kết luận trẻ nói đúng.

### Audio và thiết bị

- Tại một thời điểm chỉ có một chủ sở hữu micro/recognizer.
- Callback cũ không được đóng audio của lượt mới.
- BLE Control không được dùng thay cho trạng thái HFP/SCO.
- Trên iOS, mọi thay đổi `AVAudioSession` tiếp tục đi qua `IOSAudioSessionCoordinator`.
- Trên Android, tiếp tục dùng một process-scoped FlutterEngine và một foreground service cho phiên HOMI nền.
- Không tạo foreground service riêng cho từng tính năng.

## 4. Kiến trúc đích

```text
                         AppFlowCoordinator
                    điều hướng và chuyển module
                                  |
          +-----------------------+-----------------------+
          |                       |                       |
 MainAssistantSession   ContinuousTranslationSession   ListeningLessonSession
          |                       |                       |
          +-----------------------+-----------------------+
                                  |
                        AudioTurnCoordinator
                       chủ sở hữu audio duy nhất
                                  |
        +-------------+-----------+----------+-------------+
        |             |                      |             |
   Speech/ASR      Recorder              TTS/Playback    HFP/SCO
                                  |
                     Android/iOS native bridges
```

### Ranh giới dependency bắt buộc

- `features/listening/**` không được import `features/conversation/presentation/**`.
- `features/conversation/**` không được gọi controller của listening hoặc vocabulary.
- Feature không được gọi MethodChannel audio trực tiếp.
- Presentation chỉ gọi controller/view-model của chính feature.
- Các feature dùng tài nguyên chung thông qua interface trong `core/audio` hoặc `core/session`.
- Không dùng global event bus không định kiểu.

### Interface dự kiến

Tên cuối cùng có thể điều chỉnh theo source, nhưng trách nhiệm không được trộn lại:

- `AudioTurnCoordinator`: cấp, chuyển và thu hồi quyền sử dụng audio.
- `AudioTurnLease`: token/generation của một lượt audio.
- `SpeechCapturePort`: start, stop, cancel ASR.
- `RecordedAudioPort`: ghi và đọc lại file audio.
- `PromptPlaybackPort`: phát lời trợ lý và chờ hoàn tất.
- `AudioRoutePort`: chọn/kiểm tra/release HFP/SCO.
- `BackgroundSessionPort`: start, stop, interruption và checkpoint.
- `ContinuousTranslationSession`: state machine của dịch liên tục.
- `ListeningLessonSession`: state machine của bài học.
- `MainAssistantSession`: state machine của trợ lý MAIN.
- `AppFlowCoordinator`: chuyển giữa các module bằng command/result định kiểu.

## 5. Chính sách sở hữu audio

Mỗi thao tác audio phải có owner và token:

```dart
final lease = await coordinator.acquire(
  owner: AudioOwner.listeningLesson,
  mode: AudioTurnMode.speechCapture,
);

try {
  await speechCapture.start(lease);
} finally {
  await lease.release();
}
```

Quy tắc:

1. Chỉ lease hiện hành mới được start/stop/cancel tài nguyên audio.
2. Release bằng token cũ phải trở thành no-op và được ghi diagnostic.
3. Mọi thao tác start/stop phải được serialize.
4. Acquire có timeout và cancellation generation.
5. Dispose của một màn hình không được dispose singleton dùng chung.
6. OS interruption luôn có quyền dừng lượt hiện tại.
7. MAIN là lệnh ngắt có chủ đích: yêu cầu feature hiện tại pause tại boundary, sau đó mới chuyển lease.
8. Background chỉ giữ eligibility/wake/checkpoint; không tự sở hữu micro khi chưa có lượt hợp lệ.

## 6. Thứ tự triển khai

Trạng thái trên nhánh `codex/audio-session-modularization`: các giai đoạn 0–6
đã có commit độc lập; giai đoạn 7 đã vượt qua kiểm tra kiến trúc, analyzer và
toàn bộ 697 test không-golden trước bước commit/build cuối.

### Giai đoạn 0 — Khóa baseline bằng test

Mục đích: ghi lại hành vi hiện tại trước khi thay đổi kiến trúc.

Công việc:

- Tạo nhánh `codex/audio-session-modularization` từ `97261f9`.
- Chạy toàn bộ analyze và test hiện hành.
- Thêm integration/contract test còn thiếu cho các đường biên:
  - MAIN ngắt dịch liên tục.
  - MAIN tạm dừng và tiếp tục lesson.
  - Prompt nói xong mới mở micro.
  - Callback stop cũ không đóng lượt mới.
  - Dừng dịch chuyển sang trợ lý, không quay lại micro dịch.
  - Lesson evaluator tùy chỉnh không bị thay thế.
  - Online/offline fallback giữ nguyên.
- Chưa thay đổi production code trong giai đoạn này.

Điều kiện hoàn thành:

- Test mới thất bại nếu cố tình tái tạo lỗi tranh chấp audio.
- Test hiện hành vẫn đạt.
- Có báo cáo baseline Android/iOS theo mẫu ở mục 9.

Commit đề xuất:

```text
test(audio): lock current cross-feature behavior
```

### Giai đoạn 1 — Thêm AudioTurnCoordinator ở chế độ tương thích

Mục đích: tạo một điểm phân xử nhưng chưa đổi flow người dùng.

Công việc:

- Thêm `AudioTurnCoordinator` và `AudioTurnLease`.
- Thêm owner/mode/token/generation và hàng đợi serialize.
- Bọc các implementation hiện tại bằng adapter.
- Ban đầu coordinator chạy ở compatibility mode: gọi đúng các method hiện hành, không đổi thời điểm prompt/micro.
- Thêm diagnostic cho acquire, transfer, release, stale release và timeout.
- Chưa tách `ConversationController`.

Test bắt buộc:

- Chỉ một owner hoạt động.
- Token cũ không release token mới.
- Acquire đang chờ bị hủy đúng cách.
- Timeout không làm hàng đợi kẹt.
- Dispose owner không ảnh hưởng owner kế tiếp.

Điều kiện hoàn thành:

- Không có thay đổi UI hoặc lời thoại.
- Thời gian từ prompt kết thúc đến micro ready không tăng quá ngưỡng baseline đã đo.

Commit đề xuất:

```text
refactor(audio): add compatible audio turn coordinator
```

### Giai đoạn 2 — Chuẩn hóa prompt, playback và HFP ownership

Mục đích: ngăn nhiều `VoicePromptService`, player hoặc `LessonMediaService` tự đóng audio của nhau.

Công việc:

- Mọi prompt/playback/capture phải đi qua lease.
- Giữ implementation phát lesson, song và TTS riêng khi cần, nhưng chỉ coordinator cho phép implementation nào được hoạt động.
- Không để màn hình tự dispose native prompt engine dùng chung.
- Thay boolean `_ownsActiveHfpRoute` phân tán bằng lease token.
- iOS map lease Dart sang owner của `IOSAudioSessionCoordinator`.
- Android thêm lớp phân xử route/audio focus dùng chung trong process runtime; không tạo service thứ hai.

Test bắt buộc:

- Lesson prompt → sample → record không rơi về micro điện thoại.
- MAIN trong khi lesson phát audio chuyển quyền đúng thứ tự.
- Prompt cũ hoàn tất muộn không đóng HFP của capture mới.
- App khác phát media không làm hai nguồn chồng lên H20 theo chính sách hiện tại.

Commit đề xuất:

```text
refactor(audio): centralize prompt playback and HFP ownership
```

### Giai đoạn 3 — Tách dịch liên tục

Mục đích: sửa dịch liên tục mà không thay đổi listening hoặc trợ lý.

Công việc:

- Trích xuất `ContinuousTranslationSession` khỏi `ConversationController`.
- Session chỉ quản lý:
  - Record/capture.
  - Transcript và alternatives.
  - Lệnh dừng.
  - Exact correction/local exact.
  - Một request conversation.
  - Offline fallback.
  - Phát tiếng Anh.
- `ConversationController` tạm thời giữ façade để UI cũ không đổi.
- Không chuyển code lesson vào session này.

Test bắt buộc:

- Online pipeline đúng thứ tự.
- Offline pipeline đúng thứ tự.
- Không tăng số request backend.
- Câu thứ hai và các câu sau không nhận state/audio của câu trước.
- MAIN và lệnh dừng không bị dịch như nội dung bình thường.

Commit đề xuất:

```text
refactor(conversation): extract continuous translation session
```

### Giai đoạn 4 — Tách state machine luyện nghe

Mục đích: sửa lesson không ảnh hưởng conversation.

Công việc:

- Trích state và orchestration khỏi `LessonPracticeScreen` sang `ListeningLessonSession`.
- Screen chỉ render state và gửi intent.
- Tách các subflow:
  - Overview/intro.
  - Core practice/retry.
  - Challenge.
  - Level Mission.
  - Song.
  - Stars/completion/relearn.
- Thay `ConversationController? controller` bằng dependency interface hẹp.
- Xóa toàn bộ import từ listening sang conversation presentation.
- Apple Speech/Android SpeechRecognizer được cấp qua `SpeechCapturePort`.
- Giữ nguyên custom `LessonAttemptEvaluator`.

Test bắt buộc:

- Toàn bộ unit/widget test listening hiện hành.
- Retry/no-response/unclear luôn mở lại micro theo policy.
- Role-play chỉ mở micro ở lượt của trẻ.
- Relearn, ngôi sao, completion choice và bài hát giữ nguyên.
- Previous/next/replay ngắt audio hiện tại trước khi chuyển.

Commit đề xuất:

```text
refactor(listening): isolate lesson session from conversation
```

### Giai đoạn 5 — Tách trợ lý và điều hướng app

Mục đích: MAIN không còn điều khiển trực tiếp các controller feature.

Công việc:

- Giữ `MainButtonCoordinator` làm decoder/chính sách gesture.
- Tạo `MainAssistantSession` cho hội thoại điều hướng.
- Tạo `AppFlowCoordinator` nhận command/result định kiểu.
- `ActiveLearningModuleRegistry` chỉ đăng ký capability của module hiện hành.
- Giảm `AiSpeakingApp` về composition root, startup và render.
- Không đặt lesson/translation business logic trong `AppFlowCoordinator`.

Test bắt buộc:

- MAIN màn hình và MAIN BLE tương đương.
- MAIN pause/resume đúng module topmost.
- Route thay đổi trong lúc pause không làm lệnh rơi vào màn hình cũ.
- Long press/short press/release không chạy trùng.

Commit đề xuất:

```text
refactor(navigation): isolate MAIN assistant and app flow
```

### Giai đoạn 6 — Chuẩn hóa background lifecycle

Mục đích: foreground/background không trực tiếp can thiệp business state.

Công việc:

- `BackgroundLearningCoordinator` lưu module, checkpoint và turn boundary.
- Android foreground service giữ runtime/BLE/eligibility; feature session vẫn ở Dart runtime dùng chung.
- iOS tiếp tục dùng background audio/BLE mode và `IOSAudioSessionCoordinator`.
- Khi process được phục hồi, tiếp tục từ đầu câu hoặc khối audio gần nhất; không tiếp tục giữa file ghi âm dở.
- OS interruption chuyển thành event định kiểu cho module hiện hành.

Test bắt buộc:

- Home/đa nhiệm, khóa màn hình, mở lại app.
- Background trong lúc prompt, giữa prompt và micro, trong capture và sau response.
- Android process recreation/checkpoint.
- iOS interruption/resume và route handoff.

Commit đề xuất:

```text
refactor(background): coordinate lifecycle through session checkpoints
```

### Giai đoạn 7 — Dọn façade cũ và khóa dependency

Mục đích: loại bỏ đường gọi cũ sau khi thiết bị thật đã đạt test.

Công việc:

- Xóa façade/deprecated adapter không còn caller.
- Tách file lớn thành application/domain/presentation rõ ràng.
- Thêm script CI kiểm tra import sai ranh giới.
- Cập nhật tài liệu kiến trúc và sơ đồ ownership.
- Không xóa compatibility path native còn dùng trên thiết bị Android/iOS hỗ trợ cũ.

Điều kiện hoàn thành:

- Không feature presentation nào import presentation của feature khác.
- Không feature nào gọi MethodChannel audio trực tiếp.
- Không còn nhiều đối tượng tự nhận mình sở hữu cùng HFP route.

Commit đề xuất:

```text
refactor(architecture): enforce feature and audio boundaries
```

## 7. Lệnh kiểm tra bắt buộc

Sau mỗi commit:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Nếu root analyzer loại trừ package tool độc lập, phải phân tích package đó từ thư mục của nó:

```powershell
Set-Location tool/voice_audit
dart pub get
dart analyze
```

Trước khi giao Android test:

```powershell
flutter build apk --release --dart-define-from-file=output/apk/install-production-defines.json
```

iOS phải chạy Codemagic trên đúng commit của giai đoạn. Không kết luận iOS đạt chỉ dựa trên test Dart chạy ở Windows.

## 8. Ma trận test thiết bị thật

Mỗi giai đoạn có thay đổi audio phải kiểm tra tối thiểu:

| Nền tảng | Trạng thái | Luồng |
| --- | --- | --- |
| Android | Online | MAIN, dịch liên tục, lesson, Challenge, Mission |
| Android | Offline | Dịch fallback và chấm lesson offline |
| Android | Background | Home, app khác, khóa màn hình, quay lại app |
| Android | H20 | BLE, HFP/SCO, mic, loa, MAIN vật lý |
| iOS | Online | MAIN, dịch liên tục, lesson, Challenge, Mission |
| iOS | Offline | Apple Speech/on-device path và audio fallback |
| iOS | Background | Home, app khác, khóa màn hình, interruption |
| iOS | H20 | `bluetoothHFP`, mic, loa, BLE coexistence |

Mỗi lượt test cần ghi:

- Commit hash.
- Model máy và phiên bản OS.
- Có/không H20.
- Online/offline.
- Thời điểm prompt kết thúc.
- Thời điểm beep/micro ready.
- Transcript.
- Route input/output thực tế.
- Kết quả và log nếu lỗi.

## 9. Mẫu báo cáo sau mỗi giai đoạn

```text
Giai đoạn:
Nhánh:
Commit:
File thay đổi:
Hành vi cố ý thay đổi:
Hành vi phải giữ nguyên:
Analyze:
Unit/widget tests:
Android release build:
iOS Codemagic build:
Android device test:
iOS device test:
Rủi ro còn lại:
Rollback commit:
```

## 10. Điều kiện phải dừng và hỏi người dùng

Không tự quyết định nếu gặp một trong các trường hợp:

- Cần thay đổi lời thoại, nội dung bài học hoặc cách chấm điểm.
- Cần quyền Android/iOS mới hoặc thay đổi nội dung pháp lý.
- Cần thay đổi API/backend/database.
- Cần dependency lớn hoặc framework quản lý state mới.
- Cần thay đổi giao thức BLE/HFP hay firmware ODM.
- Test hiện hành đang phản ánh hành vi mâu thuẫn với yêu cầu đã chốt.
- Chỉ có thể hoàn thành bằng cách xóa hoặc ghi đè thay đổi của người dùng.
- Có khác biệt giữa hành vi Android và iOS chưa được chấp thuận.

## 11. Tiêu chí hoàn tất toàn bộ

- Sửa logic lesson không làm thay đổi dịch liên tục hoặc MAIN.
- Sửa dịch liên tục không làm thay đổi lesson/evaluator.
- Sửa background không thay đổi nội dung hoặc state machine tính năng.
- Một lượt chỉ có một audio owner hợp lệ.
- Stale callback không thể dừng lượt mới.
- Android/iOS dùng cùng contract ở Dart nhưng giữ adapter native riêng.
- Các giới hạn hệ điều hành được giữ nguyên, không hứa chạy sau Force Stop trên Android hoặc sau khi iOS chấm dứt app.
- Analyze, test, Android release build và iOS Codemagic đều đạt.
- Test thiết bị thật online/offline/background/H20 đạt trên cả Android và iOS.
- Có thể rollback từng giai đoạn độc lập về baseline `97261f9`.
