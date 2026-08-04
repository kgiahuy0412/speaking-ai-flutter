# API contract Flutter ↔ Next.js

Flutter dùng contract hiện tại và không gọi nhà cung cấp AI trực tiếp. Backend
chỉ dùng Cloudflare Workers AI cho ASR, dịch và TTS.

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

## Cloudflare Batch Chunks và fast path WAV

APK và Web/Safari yêu cầu noise suppression, echo cancellation và auto gain từ
hệ điều hành/trình duyệt. Luồng PCM16 sau đó đi qua high-pass 80 Hz và noise gate
thích nghi bảo thủ ở client trước khi được lưu hoặc upload. Noise gate hiệu chỉnh
300 ms đầu và chỉ giảm tối đa khoảng 7 dB để tránh cắt giọng nhỏ của trẻ.

Web/Safari giữ các chunk PCM16 200 ms trong RAM. Nếu người dùng dừng trước 8
giây, client gửi một request multipart trực tiếp tới `/api/conversation`; cách
này bỏ qua request tạo session, các request chunk và request finalize. Nếu lượt
nói dài hơn 8 giây, client tạo session, flush phần đã đệm rồi ghép 4 source chunk
thành mỗi request transport khoảng 800 ms. APK mở Batch session song song với
microphone; speech gate giữ pre-roll 400 ms và post-roll 200 ms. Nếu VAD không
xác nhận giọng nói, client hủy session và backend xóa chunk tạm.

Endpoint legacy `POST /api/realtime/transcription-session` trả HTTP 410. Client
production cũng chặn chế độ này tại chỗ và không gửi request.

### 1. Tạo audio session

`POST /api/audio-sessions`

```json
{
  "protocolVersion": 2,
  "audio": {
    "encoding": "pcm_s16le",
    "requestedSampleRate": 16000,
    "channelCount": 1,
    "bitsPerSample": 16,
    "sourceChunkDurationMs": 200,
    "maxDurationMs": 12000
  }
}
```

```json
{
  "audioSessionId": "audio_v2-...",
  "uploadToken": "short-lived-hmac-token",
  "expiresAt": "2026-08-03T12:15:00.000Z",
  "capabilities": {
    "pcm16WavFinalize": true,
    "chunkChecksumSha256": true,
    "missingChunkRecovery": true,
    "scopedUploadToken": true,
    "uploadProtocolVersion": 2,
    "sessionTtlSeconds": 900
  }
}
```

Backend vẫn trả session protocol 1 khi chưa cấu hình token để APK/Web cũ không
bị gãy. Sau khi bản mới đã phát hành, production bật
`AUDIO_UPLOAD_REQUIRE_SCOPED_TOKEN=true`.

### 2. Upload audio

`POST /api/audio-sessions/{audioSessionId}/chunks`

Headers:

```http
Authorization: Bearer {uploadToken}
Idempotency-Key: chunk:{audioSessionId}:{sequence}
X-Chunk-SHA256: {sha256-hex}
```

`multipart/form-data`:

- `sequence`: `0..N-1` cho PCM16 khi backend hỗ trợ `pcm16WavFinalize`;
- `audio`: transport chunk PCM16 mono khoảng 800 ms.

Backend lưu theo `(audioSessionId, sequence)`, không ghép theo thứ tự request đến.
Retry cùng sequence và checksum trả thành công với `duplicate=true`; cùng sequence
nhưng nội dung khác trả `AUDIO_CHUNK_CONFLICT`.

```json
{
  "uploaded": true,
  "sequence": 3,
  "sha256": "...",
  "duplicate": false,
  "totalBytes": 128000,
  "chunkCount": 4
}
```

Hủy phiên:

```http
DELETE /api/audio-sessions/{audioSessionId}/chunks
Authorization: Bearer {uploadToken}
X-Discard-Reason: no_speech
```

DELETE không đợi các upload đang retry. Backend xóa/đánh dấu phiên kết thúc và
từ chối chunk đến muộn. Session bị bỏ quên tự hết hạn sau TTL 15 phút; tiến trình
cleanup nền chạy định kỳ 5 phút.

### 3. Finalize và chạy pipeline

`POST /api/audio-sessions/{audioSessionId}/finalize`

```json
{
  "context": "school",
  "childAge": 6,
  "asrMode": "batch_chunks",
  "mimeType": "audio/wav",
  "pcm16Wav": {
    "sampleRate": 48000,
    "channelCount": 1,
    "bitsPerSample": 16,
    "pcmByteLength": 192000,
    "chunkCount": 2
  },
  "benchmark": {
    "device": "mobile",
    "browser": "flutter_android",
    "utteranceDurationMs": 2180,
    "vadSilenceMs": 900,
    "requestedAsrMode": "batch_chunks",
    "audioInputLabel": "Mic điện thoại",
    "bluetoothAudioInput": false,
    "initialNoiseRms": 0.013,
    "batchTransport": "streamed_pcm16_chunks",
    "chunkIntervalMs": 800,
    "sourceChunkIntervalMs": 200,
    "audioChunkCount": 10,
    "transportChunkCount": 2,
    "uploadedAudioBytes": 72000,
    "sessionCreateMs": 28,
    "firstChunkAckMs": 186,
    "chunkUploadP50Ms": 74,
    "chunkUploadP95Ms": 119,
    "chunkRetryCount": 0,
    "missingChunkCount": 0,
    "recoveryUploadCount": 0,
    "uploadDrainAfterStopMs": 34,
    "retryStrategy": "exponential_full_jitter_retry_after",
    "platformNoiseSuppressionRequested": true,
    "platformNoiseSuppressionApplied": true,
    "platformEchoCancellationRequested": true,
    "platformEchoCancellationApplied": true,
    "platformAutoGainRequested": true,
    "platformAutoGainApplied": true,
    "pcmHighPassApplied": true,
    "pcmHighPassCutoffHz": 80.0,
    "pcmAdaptiveNoiseGateApplied": true,
    "pcmNoiseFloorDbfs": -48.2,
    "estimatedSnrDb": 15.6,
    "pcmClippingRatio": 0.001,
    "pcmNoiseAttenuationDb": 4.8
  }
}
```

Finalize dùng header `Idempotency-Key: finalize:{audioSessionId}`. Khi thiếu
sequence, backend trả lỗi có cấu trúc để client chỉ gửi lại chunk thiếu:

```json
{
  "error": {
    "code": "AUDIO_CHUNKS_MISSING",
    "message": "Audio session thiếu chunk.",
    "details": { "missingSequences": [3, 7] }
  }
}
```

Client thử khôi phục tối đa 2 vòng. `429` tôn trọng `Retry-After`; timeout, `408`,
`425` và `5xx` dùng exponential backoff có full jitter. Lỗi ngữ nghĩa hoặc lỗi
vĩnh viễn như `ASR_LOW_CONFIDENCE`, token sai, metadata sai và checksum conflict
không upload lại toàn bộ WAV. WAV chỉ còn là lớp dự phòng cho lỗi transport không
thể khôi phục.

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

Normalize, rule/cache, Cloudflare text/TTS, history và review vẫn chạy ở backend.
Nếu Android không có dịch vụ nhận diện, Flutter chuyển thẳng sang Cloudflare
Batch Chunks/WAV.

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
