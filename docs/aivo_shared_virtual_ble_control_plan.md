# AIVO V1 — Kế hoạch cơ chế điều khiển dùng chung cho nút ảo và BLE

## 1. Mục tiêu

Chuẩn bị trước cơ chế điều khiển trong APP khi chưa có thiết bị H20 hoàn chỉnh.

Nút ảo trên màn hình và nút vật lý gửi qua BLE phải sử dụng **cùng một đường xử lý**:

```text
Nút ảo ─┐
        ├─> Control Input ─> Intent Mapper ─> Shared Dispatcher ─> Active Module
BLE  ───┘                                              │
                                                       └─> Result / APP State / ACK
```

Không được viết riêng logic phát lại, chuyển câu, tạm dừng hoặc gọi trợ lý trong widget nút ảo. Widget chỉ tạo sự kiện đầu vào và gửi vào dispatcher chung.

## 2. Nền móng hiện có trong source

Source hiện tại đã có các thành phần có thể tái sử dụng:

- `ActiveLearningCommand` tại `lib/core/device/active_learning_module.dart` chứa các lệnh `resume`, `replayCurrent`, `nextItem`, `previousItem`, `stop` và các lệnh điều hướng bài học khác.
- `ActiveLearningModuleRegistry.execute(...)` chuyển lệnh đến module học đang hiển thị.
- `ActiveLearningModuleController.handleMainCommand(...)` là điểm vào chung của màn hình luyện nghe, tổng kết, karaoke và từ vựng.
- `LessonPracticeScreen`, `LessonReviewScreen` và `SongKaraokeScreen` đã có cơ chế dừng audio, hủy ghi âm và vô hiệu hóa kết quả cũ khi tạm dừng.
- `Aiv0BleControl` đã có mô hình `Aiv0ButtonEvent`, parser BLE và đường gửi APP State.

Không tạo thêm một state machine luyện nghe thứ hai. Cơ chế mới phải đứng trước các thành phần trên và điều phối chúng.

## 3. Điểm cần thống nhất trước khi triển khai

Quy tắc mới của MAIN là:

- `MAIN_LONG`: chỉ tạm dừng hoạt động hiện tại.
- `MAIN_SHORT`: gọi trợ lý AI hoặc tiếp tục hoạt động đang tạm dừng.

Trong source hiện tại, `_toggleActiveLearningFromLongPress()` có thể dùng lần bấm giữ tiếp theo để tiếp tục bài học. Khi triển khai tài liệu này phải bỏ hành vi toggle đó. Không để `MAIN_LONG` vừa pause vừa resume.

Parser hiện tại mới có dữ liệu thực tế cho một sự kiện MAIN của firmware H20 cũ. Chưa được giả định rằng firmware mới đã gửi đủ bốn nút hoặc đúng packet đề xuất. Nút ảo có thể dùng ngay; adapter BLE chỉ hoàn thiện sau khi ODM xác nhận GATT và Raw Hex.

Khi bắt đầu triển khai phần chuẩn bị:

- Mở rộng `Aiv0Button` thành `main`, `power`, `volumeUp`, `volumeDown`, `unknown`. Việc thêm giá trị domain không có nghĩa là parser được phép nhận packet chưa xác nhận.
- Nối thêm `paused` vào cuối `Aiv0AppState` để giữ nguyên các mã hiện có và dành mã `06` cho PAUSED. Không đổi thứ tự các trạng thái cũ vì encoder hiện dùng chỉ số enum.
- Parser BLE vẫn trả `unknown` cho các Button ID chưa được ODM xác nhận; fake BLE trong test được phép tạo event domain đã chuẩn hóa.

## 4. Mô hình đầu vào chung

Tạo một mô hình đầu vào duy nhất, ví dụ:

```dart
enum AivoControlSource {
  virtualButton,
  bleDevice,
  diagnostic,
}

class AivoControlInput {
  const AivoControlInput({
    required this.source,
    required this.button,
    required this.gesture,
    required this.occurredAt,
    this.sequence,
    this.deviceId,
  });

  final AivoControlSource source;
  final Aiv0Button button;
  final Aiv0ButtonGesture gesture;
  final DateTime occurredAt;
  final int? sequence;
  final String? deviceId;
}
```

Quy tắc:

- BLE tạo `AivoControlInput` sau khi packet được kiểm tra hợp lệ.
- Nút ảo tạo cùng kiểu input với `source = virtualButton`.
- Màn hình chẩn đoán có thể tạo input với `source = diagnostic`.
- `sequence` của BLE lấy từ firmware; nút ảo dùng bộ đếm cục bộ chỉ để log và kiểm thử.
- Không truyền Raw Hex xuống module học. Raw Hex chỉ thuộc adapter BLE và màn hình chẩn đoán.

## 5. Intent dùng chung

Không ánh xạ thẳng mọi nút vào hàm UI. Chuẩn hóa chúng thành intent nghiệp vụ:

```dart
enum AivoControlIntent {
  previousItem,
  replayCurrent,
  nextItem,
  assistantOrResume,
  pauseCurrent,
  noAppAction,
}
```

Ánh xạ V1:

| Nút vật lý | Gesture | Intent APP | Nút ảo tương ứng |
|---|---|---|---|
| Tăng âm lượng | LONG | `previousItem` | Câu trước |
| Giảm âm lượng | LONG | `nextItem` | Câu sau |
| Nguồn | SHORT | `replayCurrent` | Nghe lại |
| MAIN | SHORT | `assistantOrResume` | Trợ lý hoặc Tiếp tục |
| MAIN | LONG | `pauseCurrent` | Tạm dừng |
| Tăng/Giảm âm lượng | SHORT | `noAppAction` | Không cần nút ảo; thiết bị tự chỉnh âm lượng |
| Nguồn | LONG | `noAppAction` | Không tạo nút ảo; thiết bị tự bật/tắt nguồn |

`AivoControlIntentMapper` là nơi duy nhất giữ bảng ánh xạ này. BLE adapter và widget không được tự ánh xạ lại.

## 6. Shared Dispatcher

Tạo một dispatcher cấp ứng dụng, ví dụ `AivoLearningControlDispatcher`.

API đề xuất:

```dart
abstract interface class AivoLearningControlDispatcher {
  Future<AivoControlResult> dispatch(AivoControlInput input);
}
```

Trình tự xử lý bắt buộc:

1. Kiểm tra input và xác định intent bằng `AivoControlIntentMapper`.
2. Kiểm tra sự kiện trùng dựa trên `deviceId + sequence` đối với BLE.
3. Đọc trạng thái hiện tại của module, recorder, audio player và trợ lý.
4. Áp dụng chính sách ưu tiên/hủy thao tác cũ.
5. Chuyển intent thành `ActiveLearningCommand` hoặc lệnh MAIN chung.
6. Gọi đúng một điểm xử lý nghiệp vụ.
7. Chuẩn hóa kết quả thành `AivoControlResult`.
8. Nếu nguồn là BLE và giao thức APP State đã được xác nhận, gửi ACK qua `9E3B0003`.
9. Ghi telemetry; không lưu audio hoặc dữ liệu giọng nói trong log điều khiển.

Không đặt nhánh kiểu `if (virtual) { xử lý riêng } else { xử lý BLE }`. Khác biệt theo nguồn chỉ được phép ở hai biên:

- Biên đầu vào: BLE cần parse packet; nút ảo không cần parse.
- Biên đầu ra: BLE có thể cần gửi APP State/ACK; nút ảo chỉ cập nhật UI và log.

## 7. Kết quả dùng chung

```dart
enum AivoControlStatus {
  accepted,
  busy,
  ignored,
  unavailable,
  duplicate,
  failed,
}

class AivoControlResult {
  const AivoControlResult({
    required this.status,
    required this.appState,
    this.relatedSequence,
    this.message,
  });

  final AivoControlStatus status;
  final Aiv0AppState appState;
  final int? relatedSequence;
  final String? message;
}
```

Kết quả này được dùng đồng thời cho:

- Trạng thái enable/disable và thông báo của nút ảo.
- Log trên màn hình kiểm tra.
- `Result/ACK` và `APP State` gửi về H20.
- Telemetry kiểm tra thời gian xử lý và lỗi.

## 8. Ma trận hành vi trong chủ đề luyện nghe

| Intent | Điều kiện | Hành vi chung | Kết quả |
|---|---|---|---|
| `previousItem` | Có câu trước | Dừng audio/recording, vô hiệu hóa kết quả cũ, giảm chỉ số câu và chạy câu được chọn | `accepted` |
| `previousItem` | Đang ở câu đầu | Không đổi câu | `unavailable` |
| `nextItem` | Có câu tiếp theo | Dừng audio/recording, vô hiệu hóa kết quả cũ, tăng chỉ số câu và chạy câu được chọn | `accepted` |
| `nextItem` | Đang ở câu cuối | Theo quy tắc hoàn thành bài hiện có; không tự thoát nếu module chưa cho phép | `unavailable` hoặc `accepted` theo module |
| `replayCurrent` | Có câu hiện tại | Giữ nguyên chỉ số câu; hủy lượt ghi/chấm đang chạy; bỏ kết quả trả về trễ; phát lại câu hiện tại và tiếp tục luồng luyện | `accepted` |
| `replayCurrent` | Không ở luyện nghe hoặc chưa có câu | Không làm gì | `ignored` hoặc `unavailable` |
| `pauseCurrent` | Có hoạt động | Dừng phát; dừng và hủy ghi âm; hủy hoặc vô hiệu hóa xử lý cũ; giữ nguyên bài/câu; chuyển sang `PAUSED` | `accepted` |
| `pauseCurrent` | Đã `PAUSED` | Giữ nguyên trạng thái; không tự resume | `ignored` |
| `assistantOrResume` | Module đang `PAUSED` | Gọi `ActiveLearningCommand.resume` | `accepted` nếu module tiếp tục được |
| `assistantOrResume` | Module không pause | Đi qua MAIN coordinator hiện có để gọi trợ lý AI | Kết quả của MAIN coordinator |

Mỗi module chịu trách nhiệm cho chi tiết của bài học thông qua `handleMainCommand(...)`. Dispatcher không được thay đổi trực tiếp `_sentenceIndex`, gọi riêng media service của màn hình hoặc tự điều khiển `setState`.

## 9. Xử lý bất đồng bộ và chống lỗi

Các yêu cầu sau là bắt buộc vì audio, recorder và cloud có thể hoàn tất sau khi trẻ đã bấm nút khác:

- Mỗi module tiếp tục dùng generation/request token để vô hiệu hóa callback cũ.
- `pauseCurrent`, `previousItem`, `nextItem` và `replayCurrent` được phép ngắt hoạt động đang chạy.
- Kết quả ASR/chấm điểm thuộc generation cũ phải bị bỏ qua.
- Dừng recorder và player phải có timeout; native cleanup treo không được khóa nút vĩnh viễn.
- Dispatcher chỉ chạy một thay đổi trạng thái tại một thời điểm. Sự kiện đến trong lúc chuyển trạng thái được trả `busy`, hoặc xếp tối đa một lệnh mới nhất theo chính sách đã kiểm thử.
- BLE dùng `deviceId + sequence` và cửa sổ thời gian để chống trùng. Không chống trùng nút ảo bằng thời gian vì người dùng có thể chủ động bấm hai lần.
- `pauseCurrent` có ưu tiên cao nhất và không bị xếp sau replay/next/previous.

## 10. Nút ảo trên giao diện

### Giao diện dành cho trẻ

Trong màn hình luyện nghe, hiển thị tối đa năm thao tác dễ hiểu:

```text
[ Câu trước ]  [ Nghe lại ]  [ Câu sau ]
[ Trợ lý / Tiếp tục ]        [ Tạm dừng ]
```

Yêu cầu:

- Dùng icon và nhãn tiếng Việt/tiếng Trung theo hệ thống dịch hiện có.
- Nút `Câu trước` hoặc `Câu sau` bị vô hiệu hóa khi module báo không khả dụng.
- Khi `PAUSED`, nhãn MAIN đổi thành `Tiếp tục` nhưng vẫn gửi `assistantOrResume`.
- Khi dispatcher đang chuyển trạng thái, vô hiệu hóa thao tác có thể gây xung đột; nút Tạm dừng vẫn được ưu tiên.
- Không hiển thị `POWER_SHORT`, `VOLUME_UP_LONG` hoặc Raw Hex cho trẻ.

Mỗi callback chỉ được phép gọi dispatcher:

```dart
onPressed: () => dispatcher.dispatch(
  AivoControlInput.virtual(
    button: Aiv0Button.power,
    gesture: Aiv0ButtonGesture.shortPress,
  ),
);
```

Không được gọi trực tiếp `_playCurrentSentence()`, `_goNext()`, recorder hoặc media service từ widget nút ảo.

### Giao diện kiểm tra nội bộ

Màn hình chẩn đoán có thể hiển thị:

- Tên sự kiện kỹ thuật.
- Nguồn `virtualButton`, `bleDevice` hoặc `diagnostic`.
- Sequence, thời gian nhận và độ trễ dispatch.
- Intent sau khi ánh xạ.
- Trạng thái trước/sau.
- Kết quả và APP State/ACK dự kiến.

## 11. Kết nối adapter BLE sau khi có dữ liệu ODM

Adapter BLE chỉ thực hiện:

1. Nhận Indication từ `9E3B0002`.
2. Kiểm tra độ dài, protocol version và các byte hợp lệ.
3. Parse thành `Aiv0ButtonEvent`.
4. Chuyển thành `AivoControlInput`.
5. Gọi cùng dispatcher mà nút ảo đang dùng.
6. Nhận `AivoControlResult`.
7. Mã hóa APP State 8 byte và ghi qua `9E3B0003` nếu protocol đã được ODM xác nhận.

Không đặt logic bài học trong `Aiv0BleControl`, Kotlin/Swift bridge hoặc parser Raw Hex.

## 12. Cấu trúc file dự kiến khi triển khai

Tên có thể điều chỉnh theo convention của dự án, nhưng trách nhiệm phải giữ nguyên:

```text
lib/core/device/
  aiv0_control_input.dart
  aiv0_control_intent.dart
  aiv0_control_intent_mapper.dart
  aiv0_learning_control_dispatcher.dart
  aiv0_ble_control.dart                 # chỉ BLE transport/parser/writer

lib/features/listening/presentation/
  widgets/aiv0_virtual_lesson_controls.dart

test/core_device/
  aiv0_control_intent_mapper_test.dart
  aiv0_learning_control_dispatcher_test.dart

test/features/listening/
  aiv0_virtual_lesson_controls_test.dart
```

Ưu tiên tái sử dụng `ActiveLearningCommand`, `ActiveLearningCommandResult`, `ActiveLearningModuleRegistry` và `MainButtonCoordinator`. Không tạo bản sao của các lớp này.

## 13. Kiểm thử bắt buộc trước khi nối BLE

### Unit test mapper

- Năm sự kiện chính ánh xạ đúng intent.
- SHORT của âm lượng và LONG của nguồn trả `noAppAction`.
- Sự kiện không hợp lệ trả `ignored` và không gọi module.

### Unit test dispatcher

- Nút ảo và BLE có cùng button/gesture tạo cùng intent và cùng lệnh module.
- Event BLE trùng sequence chỉ được xử lý một lần.
- `MAIN_LONG` khi đã pause không resume.
- `MAIN_SHORT` khi pause gọi `resume`.
- `pauseCurrent` thắng một replay hoặc next đang chạy.
- Kết quả cũ trả về sau next/replay không thay đổi màn hình.
- Chỉ nguồn BLE mới yêu cầu gửi APP State/ACK.

### Widget test

- Nút ảo chỉ gọi dispatcher; không gọi trực tiếp media/recorder.
- Trạng thái enable/disable đúng ở câu đầu, câu cuối, busy và paused.
- Nhãn `Trợ lý` đổi thành `Tiếp tục` khi paused.
- Bấm nút ảo phát lại/chuyển câu/tạm dừng có kết quả giống fake BLE event.

### Integration test không cần H20

1. Mở một chủ đề luyện nghe.
2. Bấm Nghe lại trong lúc audio đang phát.
3. Bấm Câu sau trong lúc đang ghi âm.
4. Cho kết quả chấm cũ trả về và xác nhận nó bị bỏ qua.
5. Bấm Tạm dừng trong lúc processing.
6. Xác nhận recorder/audio dừng, câu hiện tại không đổi và trạng thái là PAUSED.
7. Bấm Tiếp tục và xác nhận bài học tiếp tục đúng vị trí.
8. Lặp lại bằng fake BLE input và so sánh cùng kết quả.

## 14. Những việc chỉ kiểm tra được khi có H20

- Raw Hex thực tế và Button ID/Gesture của bốn nút.
- Ngưỡng SHORT/LONG và việc LONG có phát kèm SHORT hay không.
- Debounce và mỗi thao tác có đúng một Indication hay không.
- Mất gói khi HFP/SCO bắt đầu hoặc kết thúc.
- APP State Write With Response và ACK thực tế.
- Tự kết nối lại BLE/HFP.
- Micro H20 và loa H20 có thực sự là audio route đang dùng.

## 15. Thứ tự triển khai đề xuất

1. Viết test cho mapper và dispatcher.
2. Tạo input, intent mapper, result và dispatcher dùng chung.
3. Chuyển xử lý MAIN hiện tại sang dispatcher; sửa `MAIN_LONG` thành pause-only.
4. Nối dispatcher với `ActiveLearningModuleRegistry` và MAIN coordinator hiện có.
5. Thêm widget nút ảo vào màn hình luyện nghe.
6. Chạy unit/widget/integration test với fake BLE input.
7. Khi ODM gửi GATT và Raw Hex đã xác nhận, mở rộng parser BLE cho bốn nút.
8. Nối kết quả dispatcher với APP State/ACK.
9. Kiểm tra lại trên Android và iOS Native với H20 thật.

## 16. Điều kiện hoàn thành

Cơ chế được xem là sẵn sàng nối thiết bị khi:

- Không có hàm xử lý nghiệp vụ riêng cho nút ảo.
- Cùng một input logic từ nút ảo và fake BLE cho cùng kết quả.
- MAIN_LONG chỉ pause; MAIN_SHORT mới resume hoặc gọi trợ lý.
- Replay/next/previous không để callback cũ thay đổi câu hoặc trạng thái.
- Module học là nơi duy nhất quyết định chi tiết luồng bài học.
- BLE adapter chỉ chịu trách nhiệm transport, parse và ACK.
- Toàn bộ test bắt buộc ở Mục 13 đạt.
