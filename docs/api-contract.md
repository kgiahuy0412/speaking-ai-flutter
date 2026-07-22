# API contract Flutter ↔ Next.js

Flutter dùng contract hiện tại, không gọi OpenAI trực tiếp.

## Khởi động ứng dụng

Mỗi lần mở APK, Flutter gửi một yêu cầu không chặn giao diện:

`POST /api/cache/warmup`

```json
{
  "context": "all",
  "background": true
}
```

Backend trả `202 Accepted` ngay, sau đó gộp các yêu cầu đồng thời, bỏ câu trùng
giữa các ngữ cảnh và chỉ tạo audio TTS còn thiếu. Warm-up lỗi không chặn người
dùng bắt đầu nói.

Flutter đồng thời tải danh mục fast path BLE:

`GET /api/offline-intents?limit=40`

Response gồm `version`, `sampleRate=24000`, policy confidence/margin/stability và
30–50 intent với câu mẫu, ngữ cảnh, câu tiếng Anh, `audioUrl`. APK dùng danh mục
này cho recognizer native và cache audio; endpoint không chứa API key.

## Một lượt nói OpenAI Realtime

### 1. Xin client secret sống ngắn

`POST /api/realtime/transcription-session`

```json
{
  "clientId": "device_...",
  "bluetoothAudioInput": false
}
```

Backend tạo transcription session PCM16 mono 24 kHz, tiếng Việt, manual commit.
API key chuẩn không rời backend; Flutter chỉ nhận client secret hết hạn nhanh.

### 2. Stream và finalize

Flutter mở WebSocket ngay khi bắt đầu một lượt ghi âm và gửi
`input_audio_buffer.append` trong lúc nói, sau đó gửi `input_audio_buffer.commit`
khi Stop. Kết nối không được prewarm ngoài lượt nói. Partial chỉ gọi preview rule/cache; final
text được gửi một lần vào `POST /api/conversation` với:

```json
{
  "context": "home",
  "childAge": 6,
  "sourceText": "Con muốn ăn cơm",
  "asrMode": "openai_realtime",
  "benchmark": {
    "requestedAsrMode": "openai_realtime",
    "asrFirstDeltaMs": 620,
    "asrFinalAfterStopMs": 180,
    "realtimeSessionCreateMs": 140,
    "realtimeWebSocketConnectMs": 95,
    "realtimeWebSocketOpenAfterRecordingMs": 235,
    "realtimeChunkDurationMs": 200
  }
}
```

## Batch Chunks/WAV dự phòng

### 1. Tạo audio session

`POST /api/audio-sessions`

```json
{
  "audioSessionId": "audio_..."
}
```

### 2. Upload audio

`POST /api/audio-sessions/{audioSessionId}/chunks`

`multipart/form-data`:

- `sequence`: `1..N` cho PCM16 và `0` cho WAV header;
- `audio`: các chunk PCM16 mono 24 kHz khoảng 200 ms.

Luồng này chỉ tự bật khi Realtime không sẵn sàng. Backend ghép thành WAV hợp lệ
và gọi OpenAI ASR đúng một lần; không chạy song song với Realtime.

### 3. Finalize và chạy pipeline

`POST /api/audio-sessions/{audioSessionId}/finalize`

```json
{
  "context": "school",
  "childAge": 6,
  "asrMode": "batch_chunks",
  "mimeType": "audio/wav",
  "benchmark": {
    "device": "mobile",
    "browser": "flutter_android",
    "utteranceDurationMs": 2180,
    "vadSilenceMs": 700,
    "requestedAsrMode": "batch_chunks",
    "audioInputLabel": "Mic điện thoại",
    "bluetoothAudioInput": false,
    "initialNoiseRms": 0.013,
    "batchTransport": "streamed_pcm16_chunks",
    "chunkIntervalMs": 200,
    "audioChunkCount": 9,
    "uploadedAudioBytes": 72000,
    "sessionCreateMs": 28,
    "uploadDrainAfterStopMs": 34
  }
}
```

Response tiếp tục dùng `ConversationResponse` hiện tại:

```json
{
  "conversationId": "conv_...",
  "sessionId": "sess_...",
  "context": "school",
  "vietnameseText": "Con cần bút chì",
  "englishText": "I need a pencil, please.",
  "audioUrl": "/api/audio/stream?text=...",
  "processingMode": "rule",
  "textSource": "phrase_rule",
  "audioSource": "cache",
  "asrMode": "batch_chunks",
  "latency": {
    "asrMs": 420,
    "llmMs": 3,
    "ttsMs": 1,
    "timeToFirstAudioMs": 760
  }
}
```

Client resolve `audioUrl` tương đối theo `BACKEND_BASE_URL`.

### Fast path Android streaming

Android `SpeechRecognizer` trả partial/final tiếng Việt ngay trong lúc nói. Flutter
gửi final text vào cùng pipeline Next.js bằng:

`POST /api/conversation`

```json
{
  "context": "home",
  "childAge": 6,
  "sourceText": "Con muốn ăn cơm",
  "asrMode": "android_streaming",
  "benchmark": {
    "device": "mobile",
    "browser": "flutter_android",
    "requestedAsrMode": "android_streaming",
    "asrFirstDeltaMs": 850,
    "asrFinalAfterStopMs": 40
  }
}
```

Normalize, rule/cache, AI fallback, TTS, history và review vẫn chạy ở backend.
Nếu Android không có dịch vụ nhận diện, Flutter chuyển sang OpenAI Realtime;
nếu Realtime lỗi mới dùng Batch Chunks/WAV.

## Telemetry playback

Sau khi Android bắt đầu phát:

`PATCH /api/history`

```json
{
  "conversationId": "conv_...",
  "latency": {
    "ttsFirstByteMs": 150,
    "browserAudioStartedMs": 790,
    "timeToFirstAudioMs": 790,
    "audioStartedAfterStopMs": 790
  }
}
```

Tên `browserAudioStartedMs` được giữ để không phá report hiện tại. Bản contract
v2 nên đổi thành tên trung tính `clientAudioStartedMs` nhưng đọc được cả hai.

## Đánh giá

`PATCH /api/history`

```json
{
  "conversationId": "conv_...",
  "qualityApproved": true
}
```

## Lịch sử

`GET /api/history`

Flutter đọc `conversations[]` và hiển thị các lượt gần đây trong settings.

## Error mapping

Client hiển thị `error.message` do backend trả về và giữ nguyên các code:

- `AUDIO_TOO_SHORT`, `AUDIO_TOO_LONG`;
- `ASR_FAILED`, `ASR_LOW_CONFIDENCE`;
- `LLM_FAILED`, `TTS_FAILED`;
- `RATE_LIMITED`, `UNSAFE_CONTENT`, `BAD_REQUEST`.

Production nên thêm `UNAUTHORIZED`, `DEVICE_NOT_REGISTERED`,
`BACKEND_VERSION_UNSUPPORTED` và một `requestId` để tra log.
