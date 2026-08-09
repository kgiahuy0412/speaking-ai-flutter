import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/offline_intent_recognizer.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/wav_audio.dart';
import '../../../core/network/multipart_audio_file.dart';
import '../../../core/network/realtime_socket.dart';
import '../domain/conversation_models.dart';
import '../domain/conversation_repository.dart';

class NextConversationRepository
    implements
        ConversationRepository,
        ChunkedConversationRepository,
        RealtimeConversationRepository,
        OfflineIntentCatalogRepository {
  NextConversationRepository({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    http.Client? client,
  }) : _config = config,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clientId = clientIdProvider();

  final AppConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String> _clientId;
  Future<OfflineIntentManifest>? _offlineIntentManifest;

  @override
  Future<OfflineIntentManifest> fetchOfflineIntentManifest() {
    return _offlineIntentManifest ??= _loadOfflineIntentManifest();
  }

  Future<OfflineIntentManifest> _loadOfflineIntentManifest() async {
    try {
      final uri = _config
          .resolve('/api/offline-intents')
          .replace(queryParameters: const <String, String>{'limit': '500'});
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      return OfflineIntentManifest.fromJson(
        _decodeResponse(response),
        backendBaseUri: _config.backendBaseUri,
      );
    } catch (_) {
      _offlineIntentManifest = null;
      rethrow;
    }
  }

  @override
  Future<void> warmAudioCache() async {
    final clientId = await _clientId;
    final response = await _client
        .post(
          _config.resolve('/api/cache/warmup'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': clientId,
            'context': 'all',
            'background': true,
            // Warm all reviewed/product rules used by the current corpus, not
            // only the first screenful. Persistent storage makes later starts
            // cheap because already-generated audio becomes a cache hit.
            'limit': 1500,
          }),
        )
        .timeout(const Duration(seconds: 12));
    _decodeResponse(response);
  }

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    final clientId = await _clientId;
    try {
      return await _processAudioDirect(
        clientId: clientId,
        capture: capture,
        context: context,
        childAge: childAge,
        vadSilenceMs: vadSilenceMs,
        fallbackReason: fallbackReason,
      );
    } catch (error, stackTrace) {
      if (!_canFallBackFromDirectUpload(error)) {
        rethrow;
      }
      developer.log(
        'Direct audio upload failed; using resumable audio session.',
        name: 'conversation.audio_upload',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final audioSession = await _createAudioSession(encoding: 'encoded_audio');
    final audioSessionId = audioSession.id;
    await _uploadAudio(audioSession: audioSession, capture: capture);

    return _finalizeAudioSession(
      clientId: clientId,
      audioSessionId: audioSessionId,
      uploadToken: audioSession.uploadToken,
      capture: capture,
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
      clientVadApplied: false,
      batchTelemetry: <String, dynamic>{
        'batchFallbackReason': fallbackReason ?? 'direct_upload_failed',
      },
    );
  }

  Future<ConversationResult> _processAudioDirect({
    required String clientId,
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async {
    final benchmark = ConversationBenchmark(
      utteranceDurationMs: capture.duration.inMilliseconds,
      vadSilenceMs: vadSilenceMs,
      requestedAsrMode: AsrMode.batchChunks,
      audioInputLabel: capture.inputLabel,
      bluetoothAudioInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      audioProcessing: capture.audioProcessing,
      // A direct/fallback file still contains the leading and trailing audio.
      // Let Cloudflare apply its VAD instead of claiming it was client-trimmed.
      clientVadApplied: false,
    );
    final request =
        http.MultipartRequest('POST', _config.resolve('/api/conversation'))
          ..fields['clientId'] = clientId
          ..fields['context'] = context.apiValue
          ..fields['childAge'] = childAge.toString()
          ..fields['benchmark'] = jsonEncode(<String, dynamic>{
            ...benchmark.toJson(),
            'batchTransport': 'direct_multipart',
            'batchFallbackReason': ?fallbackReason,
          })
          ..files.add(
            await createAudioMultipartFile(
              field: 'audio',
              path: capture.filePath,
              filename: _audioFilename(capture.mimeType),
              bytes: capture.dataBytes,
            ),
          );
    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);
    final json = _decodeResponse(response);
    return ConversationResult.fromJson(
      json,
      backendBaseUri: _config.backendBaseUri,
    );
  }

  bool _canFallBackFromDirectUpload(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    if (error is! ConversationApiException) {
      return false;
    }
    final statusCode = error.statusCode;
    return statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 408 ||
        statusCode == 413 ||
        statusCode == 425 ||
        (statusCode != null && statusCode >= 500);
  }

  Future<ConversationResult> _finalizeAudioSession({
    required String clientId,
    required String audioSessionId,
    String? uploadToken,
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    bool assemblePcmWav = false,
    bool clientVadApplied = true,
    String? prefetchId,
    Map<String, dynamic> batchTelemetry = const <String, dynamic>{},
  }) async {
    final benchmark = ConversationBenchmark(
      utteranceDurationMs: capture.duration.inMilliseconds,
      vadSilenceMs: vadSilenceMs,
      requestedAsrMode: AsrMode.batchChunks,
      audioInputLabel: capture.inputLabel,
      bluetoothAudioInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      clientVadApplied: clientVadApplied,
      audioProcessing: capture.audioProcessing,
    );
    final uri = _config.resolve('/api/audio-sessions/$audioSessionId/finalize');
    final body = jsonEncode(<String, dynamic>{
      'clientId': clientId,
      'context': context.apiValue,
      'childAge': childAge,
      'asrMode': 'batch_chunks',
      'mimeType': capture.mimeType,
      'prefetchId': ?prefetchId,
      if (assemblePcmWav)
        'pcm16Wav': <String, dynamic>{
          'sampleRate': capture.recordingSampleRate,
          'channelCount': pcm16ChannelCount,
          'bitsPerSample': pcm16BitsPerSample,
          'pcmByteLength': capture.streamedAudioBytes,
          if (batchTelemetry['transportChunkCount'] is int)
            'chunkCount': batchTelemetry['transportChunkCount'],
        },
      'benchmark': <String, dynamic>{...benchmark.toJson(), ...batchTelemetry},
    });
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        final response = await _client
            .post(
              uri,
              headers: <String, String>{
                'content-type': 'application/json',
                'Idempotency-Key': 'finalize:$audioSessionId',
                if (uploadToken != null) 'Authorization': 'Bearer $uploadToken',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 35));
        return ConversationResult.fromJson(
          _decodeResponse(response),
          backendBaseUri: _config.backendBaseUri,
        );
      } catch (error) {
        lastError = error;
        if (!_isRetryableConversationRequest(error)) {
          rethrow;
        }
      }

      if (attempt < 3) {
        await Future<void>.delayed(
          _conversationRetryDelay(
            error: lastError,
            attempt: attempt,
            baseMs: 300,
          ),
        );
      }
    }

    if (lastError is ConversationApiException) {
      throw lastError;
    }
    throw ConversationApiException(
      'Không finalize được audio sau 3 lần thử: $lastError',
    );
  }

  @override
  Future<BatchChunkUploadSession> startBatchChunkUpload() async {
    final stopwatch = Stopwatch()..start();
    final audioSession = await _createAudioSession();
    stopwatch.stop();
    return _NextBatchChunkUploadSession(
      repository: this,
      audioSessionId: audioSession.id,
      sessionCreateMs: stopwatch.elapsedMilliseconds,
      supportsPcm16WavFinalize: audioSession.supportsPcm16WavFinalize,
      uploadToken: audioSession.uploadToken,
      supportsChunkChecksum: audioSession.supportsChunkChecksum,
      supportsMissingChunkRecovery: audioSession.supportsMissingChunkRecovery,
      supportsBatchPrefetch: audioSession.supportsBatchPrefetch,
      uploadProtocolVersion: audioSession.uploadProtocolVersion,
    );
  }

  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription({
    required String audioInputLabel,
    required bool bluetoothAudioInput,
  }) async {
    throw const ConversationApiException(
      'Chế độ Realtime cũ đã bị tắt. Hãy dùng Cloudflare Batch Chunks.',
    );
  }

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    final clientId = await _clientId;
    final requestedMode = AsrMode.values.firstWhere(
      (mode) => mode.apiValue == capture.asrMode,
      orElse: () => AsrMode.androidStreaming,
    );
    final benchmark = ConversationBenchmark(
      utteranceDurationMs: capture.duration.inMilliseconds,
      vadSilenceMs: vadSilenceMs,
      requestedAsrMode: requestedMode,
      audioInputLabel: capture.inputLabel,
      bluetoothAudioInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
    );
    final response = await _client
        .post(
          _config.resolve('/api/conversation'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': clientId,
            'context': context.apiValue,
            'childAge': childAge,
            'sourceText': capture.sourceText,
            'asrMode': capture.asrMode,
            'benchmark': <String, dynamic>{
              ...benchmark.toJson(),
              if (capture.confidence != null)
                'asrConfidence': capture.confidence,
              if (capture.firstResultMs != null)
                'asrFirstDeltaMs': capture.firstResultMs,
              'asrFinalAfterStopMs': capture.finalAfterStopMs,
              if (capture.realtimeSessionCreateMs != null)
                'realtimeSessionCreateMs': capture.realtimeSessionCreateMs,
              if (capture.realtimeWebSocketConnectMs != null)
                'realtimeWebSocketConnectMs':
                    capture.realtimeWebSocketConnectMs,
              if (capture.realtimeWebSocketOpenAfterRecordingMs != null)
                'realtimeWebSocketOpenAfterRecordingMs':
                    capture.realtimeWebSocketOpenAfterRecordingMs,
              if (capture.realtimeChunkDurationMs != null)
                'realtimeChunkDurationMs': capture.realtimeChunkDurationMs,
              if (capture.workerAsrPilotRttMs != null)
                'workerAsrPilotRttMs': capture.workerAsrPilotRttMs,
              if (capture.workerAsrPilotAsrMs != null)
                'workerAsrPilotAsrMs': capture.workerAsrPilotAsrMs,
              if (capture.workerAsrPilotAudioBytes != null)
                'workerAsrPilotAudioBytes': capture.workerAsrPilotAudioBytes,
              if (capture.extraBenchmark != null) ...capture.extraBenchmark!,
            },
          }),
        )
        .timeout(const Duration(seconds: 20));
    final json = _decodeResponse(response);

    return ConversationResult.fromJson(
      json,
      backendBaseUri: _config.backendBaseUri,
    );
  }

  @override
  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  }) async {
    final clientId = await _clientId;
    final response = await _client
        .post(
          _config.resolve('/api/conversation/preview'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': clientId,
            'context': context.apiValue,
            'childAge': childAge,
            'sourceText': sourceText,
          }),
        )
        .timeout(const Duration(seconds: 4));
    final json = _decodeResponse(response);
    if (json['matched'] != true) {
      return null;
    }
    final rawAudioUrl = json['audioUrl'] as String?;
    return ConversationPreview(
      sourceText: json['sourceText'] as String? ?? sourceText,
      englishText: json['englishText'] as String? ?? '',
      textSource: json['textSource'] as String? ?? 'fallback',
      audioUri: rawAudioUrl == null
          ? null
          : _config.backendBaseUri.resolve(rawAudioUrl),
    );
  }

  Future<_BatchSpeculativePreview?> _previewAudioSession({
    required String audioSessionId,
    required String? uploadToken,
    required PracticeContext context,
    required int childAge,
    required int pcmByteLength,
    required int chunkCount,
    required bool terminal,
    String? previousPrefetchId,
    Map<String, dynamic>? benchmark,
  }) async {
    final response = await _client
        .post(
          _config.resolve('/api/audio-sessions/$audioSessionId/preview'),
          headers: <String, String>{
            'content-type': 'application/json',
            if (uploadToken != null) 'Authorization': 'Bearer $uploadToken',
          },
          body: jsonEncode(<String, dynamic>{
            'clientId': await _clientId,
            'context': context.apiValue,
            'childAge': childAge,
            'terminal': terminal,
            'previousPrefetchId': ?previousPrefetchId,
            'benchmark': ?benchmark,
            'pcm16Wav': <String, dynamic>{
              'sampleRate': pcm16SampleRate,
              'channelCount': pcm16ChannelCount,
              'bitsPerSample': pcm16BitsPerSample,
              'pcmByteLength': pcmByteLength,
              'chunkCount': chunkCount,
            },
          }),
        )
        .timeout(const Duration(seconds: 8));
    final json = _decodeResponse(response);
    if (json['eligible'] != true) {
      return null;
    }
    final prefetchId = json['prefetchId'];
    final englishText = json['englishText'];
    if (prefetchId is! String ||
        prefetchId.isEmpty ||
        englishText is! String ||
        englishText.trim().isEmpty) {
      return null;
    }
    final rawAudioUrl = json['audioUrl'];
    return _BatchSpeculativePreview(
      prefetchId: prefetchId,
      snapshotChunkCount:
          (json['snapshotChunkCount'] as num?)?.toInt() ?? chunkCount,
      preview: ConversationPreview(
        sourceText: json['sourceText'] as String? ?? '',
        englishText: englishText,
        textSource: json['textSource'] as String? ?? 'fallback',
        audioUri: rawAudioUrl is String && rawAudioUrl.isNotEmpty
            ? _config.backendBaseUri.resolve(rawAudioUrl)
            : null,
      ),
    );
  }

  Future<_AudioSessionDescriptor> _createAudioSession({
    String encoding = 'pcm_s16le',
  }) async {
    final response = await _client
        .post(
          _config.resolve('/api/audio-sessions'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'protocolVersion': 2,
            'audio': <String, dynamic>{
              'encoding': encoding,
              'requestedSampleRate': pcm16SampleRate,
              'channelCount': pcm16ChannelCount,
              'bitsPerSample': pcm16BitsPerSample,
              'sourceChunkDurationMs': pcmChunkDurationMs,
              'maxDurationMs': 12000,
            },
          }),
        )
        .timeout(const Duration(seconds: 10));
    final json = _decodeResponse(response);
    final audioSessionId = json['audioSessionId'];

    if (audioSessionId is! String || audioSessionId.isEmpty) {
      throw const ConversationApiException(
        'Backend không trả về audioSessionId.',
      );
    }
    final capabilities = json['capabilities'];
    final capabilityMap = capabilities is Map<String, dynamic>
        ? capabilities
        : const <String, dynamic>{};
    final uploadToken = json['uploadToken'];
    final uploadProtocolVersion = capabilityMap['uploadProtocolVersion'];
    return _AudioSessionDescriptor(
      id: audioSessionId,
      supportsPcm16WavFinalize: capabilityMap['pcm16WavFinalize'] == true,
      uploadToken: uploadToken is String && uploadToken.isNotEmpty
          ? uploadToken
          : null,
      supportsChunkChecksum: capabilityMap['chunkChecksumSha256'] == true,
      supportsMissingChunkRecovery:
          capabilityMap['missingChunkRecovery'] == true,
      supportsBatchPrefetch: capabilityMap['batchPrefetch'] == true,
      uploadProtocolVersion: uploadProtocolVersion is num
          ? uploadProtocolVersion.toInt()
          : 1,
    );
  }

  Future<_WorkerAsrTranscript> _transcribeWorkerAsrPilot({
    required String audioSessionId,
    required String uploadToken,
    required Uint8List pcmBytes,
    required int snapshotChunkCount,
  }) async {
    final workerBaseUri = _config.workerAsrPilotBaseUri;
    if (!_config.workerAsrPilotReady || workerBaseUri == null) {
      throw const ConversationApiException(
        'Worker ASR Pilot chưa được cấu hình.',
        errorCode: 'WORKER_ASR_PILOT_DISABLED',
      );
    }
    if (pcmBytes.isEmpty) {
      throw const ConversationApiException(
        'Worker ASR Pilot chỉ nhận PCM 16 kHz.',
        errorCode: 'WORKER_ASR_PILOT_PCM_INVALID',
      );
    }

    final requestStopwatch = Stopwatch()..start();
    final response = await _client
        .post(
          workerBaseUri.resolve('/v1/asr/transcribe'),
          headers: <String, String>{
            'Authorization': 'Bearer $uploadToken',
            'Content-Type': 'application/octet-stream',
            'X-Audio-Session-Id': audioSessionId,
            'X-Snapshot-Chunk-Count': snapshotChunkCount.toString(),
            'X-Audio-Sample-Rate': pcm16SampleRate.toString(),
            'X-Audio-Channels': pcm16ChannelCount.toString(),
            'X-Audio-Encoding': 'pcm_s16le',
          },
          body: pcmBytes,
        )
        .timeout(const Duration(seconds: 6));
    requestStopwatch.stop();

    Map<String, dynamic> payload = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } on FormatException {
      // The status handling below reports a stable pilot error code.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawCode = payload['error'];
      throw ConversationApiException(
        'Worker ASR Pilot trả về lỗi ${response.statusCode}.',
        statusCode: response.statusCode,
        errorCode: rawCode is String && rawCode.isNotEmpty
            ? rawCode
            : 'WORKER_ASR_PILOT_FAILED',
      );
    }
    final transcript = payload['transcript'];
    if (transcript is! String || transcript.trim().isEmpty) {
      throw const ConversationApiException(
        'Worker ASR Pilot không nhận dạng được câu nói.',
        statusCode: 422,
        errorCode: 'WORKER_ASR_PILOT_UNCLEAR',
      );
    }
    final timing = payload['timing'];
    final asrMs = timing is Map<String, dynamic>
        ? (timing['asrMs'] as num?)?.round()
        : null;
    developer.log(
      jsonEncode(<String, dynamic>{
        'event': 'worker_asr_pilot_completed',
        'audioSessionId': audioSessionId,
        'snapshotChunkCount': snapshotChunkCount,
        'audioBytes': pcmBytes.length,
        'workerRttMs': requestStopwatch.elapsedMilliseconds,
        'workerAsrMs': asrMs,
      }),
      name: 'conversation.worker_asr_pilot',
    );

    return _WorkerAsrTranscript(
      sourceText: transcript.trim(),
      snapshotChunkCount: snapshotChunkCount,
      snapshotHash: crypto.sha256.convert(pcmBytes).toString(),
      audioBytes: pcmBytes.length,
      rttMs: requestStopwatch.elapsedMilliseconds,
      asrMs: asrMs,
    );
  }

  Future<ConversationResult> _processWorkerTranscript({
    required _WorkerAsrTranscript transcript,
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    Map<String, dynamic>? extraBenchmark,
  }) {
    return processStreamingText(
      capture: StreamingSpeechCapture(
        sourceText: transcript.sourceText,
        duration: capture.duration,
        inputLabel: capture.inputLabel,
        confidence: null,
        firstResultMs: null,
        finalAfterStopMs: transcript.rttMs,
        asrMode: AsrMode.workerAsrPilot.apiValue,
        isBluetoothInput: capture.isBluetoothInput,
        initialNoiseRms: capture.initialNoiseRms,
        workerAsrPilotRttMs: transcript.rttMs,
        workerAsrPilotAsrMs: transcript.asrMs,
        workerAsrPilotAudioBytes: transcript.audioBytes,
        extraBenchmark: extraBenchmark,
      ),
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
    );
  }

  Future<_PreparedWorkerConversation> _prepareWorkerConversation({
    required String audioSessionId,
    required _WorkerAsrTranscript transcript,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    required int workerStartedAtSessionMs,
  }) async {
    final response = await _client
        .post(
          _config.resolve('/api/conversation/prepare'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': await _clientId,
            'audioSessionId': audioSessionId,
            'snapshotHash': transcript.snapshotHash,
            'sourceText': transcript.sourceText,
            'context': context.apiValue,
            'childAge': childAge,
            'asrLatencyMs': transcript.asrMs ?? transcript.rttMs,
            'benchmark': <String, dynamic>{
              ...ConversationBenchmark(
                utteranceDurationMs:
                    (transcript.audioBytes * 1000) ~/ (pcm16SampleRate * 2),
                vadSilenceMs: vadSilenceMs,
                requestedAsrMode: AsrMode.workerAsrPilot,
                audioInputLabel: 'Web PCM Worker prepare',
                bluetoothAudioInput: false,
                initialNoiseRms: null,
                clientVadApplied: true,
              ).toJson(),
              'workerAsrPilotRttMs': transcript.rttMs,
              if (transcript.asrMs != null)
                'workerAsrPilotAsrMs': transcript.asrMs,
              'workerAsrPilotAudioBytes': transcript.audioBytes,
              'workerStartedAtSessionMs': workerStartedAtSessionMs,
              'workerPrepareAttempted': true,
            },
          }),
        )
        .timeout(const Duration(seconds: 8));
    final json = _decodeResponse(response);
    final prepareId = json['prepareId'];
    final resultJson = json['result'];
    if (prepareId is! String ||
        prepareId.isEmpty ||
        resultJson is! Map<String, dynamic>) {
      throw const ConversationApiException(
        'Backend không trả về kết quả chuẩn bị hợp lệ.',
        errorCode: 'WORKER_PREPARE_INVALID',
      );
    }
    final result = ConversationResult.fromJson(
      resultJson,
      backendBaseUri: _config.backendBaseUri,
    );
    return _PreparedWorkerConversation(
      prepareId: prepareId,
      transcript: transcript,
      result: result,
      preview: ConversationPreview(
        sourceText: result.vietnameseText,
        englishText: result.englishText,
        textSource: result.textSource,
        audioUri: result.audioUri,
      ),
    );
  }

  Future<ConversationResult> _commitPreparedWorkerConversation({
    required String audioSessionId,
    required _PreparedWorkerConversation prepared,
    required Map<String, dynamic> benchmark,
  }) async {
    final response = await _client
        .post(
          _config.resolve('/api/conversation/prepare/commit'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'prepareId': prepared.prepareId,
            'audioSessionId': audioSessionId,
            'snapshotHash': prepared.transcript.snapshotHash,
            'benchmark': benchmark,
          }),
        )
        .timeout(const Duration(seconds: 5));
    return ConversationResult.fromJson(
      _decodeResponse(response),
      backendBaseUri: _config.backendBaseUri,
    );
  }

  Future<void> _uploadAudio({
    required _AudioSessionDescriptor audioSession,
    required AudioCapture capture,
  }) async {
    final audioBytes = await readAudioBytes(
      path: capture.filePath,
      bytes: capture.dataBytes,
    );
    final checksum = crypto.sha256.convert(audioBytes).toString();
    final request =
        http.MultipartRequest(
            'POST',
            _config.resolve('/api/audio-sessions/${audioSession.id}/chunks'),
          )
          ..fields['sequence'] = '0'
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              audioBytes,
              filename: _audioFilename(capture.mimeType),
            ),
          );
    request.headers['Idempotency-Key'] = 'chunk:${audioSession.id}:0';
    request.headers['X-Chunk-SHA256'] = checksum;
    if (audioSession.uploadToken != null) {
      request.headers['Authorization'] = 'Bearer ${audioSession.uploadToken}';
    }
    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);
    final json = _decodeResponse(response);
    final acknowledgedSha256 = json['sha256'];
    if (acknowledgedSha256 is String &&
        acknowledgedSha256.isNotEmpty &&
        acknowledgedSha256.toLowerCase() != checksum) {
      throw const ConversationApiException(
        'Checksum file audio không khớp xác nhận từ backend.',
        errorCode: 'AUDIO_CHUNK_ACK_MISMATCH',
      );
    }
  }

  Future<void> _uploadAudioBytes({
    required String audioSessionId,
    required int sequence,
    required Uint8List bytes,
    required String filename,
    required String sha256,
    String? uploadToken,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _config.resolve('/api/audio-sessions/$audioSessionId/chunks'),
          )
          ..fields['sequence'] = sequence.toString()
          ..files.add(
            http.MultipartFile.fromBytes('audio', bytes, filename: filename),
          );
    request.headers['Idempotency-Key'] = 'chunk:$audioSessionId:$sequence';
    request.headers['X-Chunk-SHA256'] = sha256;
    if (uploadToken != null) {
      request.headers['Authorization'] = 'Bearer $uploadToken';
    }
    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamedResponse);
    final json = _decodeResponse(response);
    final acknowledgedSequence = json['sequence'];
    if (acknowledgedSequence is num &&
        acknowledgedSequence.toInt() != sequence) {
      throw ConversationApiException(
        'Backend xác nhận sai audio chunk $sequence.',
        errorCode: 'AUDIO_CHUNK_ACK_MISMATCH',
      );
    }
    final acknowledgedSha256 = json['sha256'];
    if (acknowledgedSha256 is String &&
        acknowledgedSha256.isNotEmpty &&
        acknowledgedSha256.toLowerCase() != sha256) {
      throw ConversationApiException(
        'Checksum audio chunk $sequence không khớp xác nhận từ backend.',
        errorCode: 'AUDIO_CHUNK_ACK_MISMATCH',
      );
    }
  }

  Future<void> _discardAudioSession(
    String audioSessionId, {
    String? uploadToken,
    String reason = 'unspecified',
  }) async {
    final response = await _client
        .delete(
          _config.resolve('/api/audio-sessions/$audioSessionId/chunks'),
          headers: <String, String>{
            if (uploadToken != null) 'Authorization': 'Bearer $uploadToken',
            'X-Discard-Reason': reason,
          },
        )
        .timeout(const Duration(seconds: 5));
    _decodeResponse(response);
  }

  @override
  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  }) async {
    final clientId = await _clientId;
    final response = await _client
        .patch(
          _config.resolve('/api/history'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': clientId,
            'conversationId': conversationId,
            'qualityApproved': approved,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final json = _decodeResponse(response);
    return ConversationLearningOutcome.fromJson(
      json['learning'],
      approved: approved,
    );
  }

  @override
  Future<void> patchPlaybackLatency({
    required String conversationId,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
    int? responseToPlaybackMs,
    bool? audioPreloadLoadedData,
    bool? audioPreloadCanPlay,
    int? audioPreloadLoadedDataMs,
    int? audioPreloadCanPlayMs,
  }) async {
    final clientId = await _clientId;
    final body = jsonEncode(<String, dynamic>{
      'clientId': clientId,
      'conversationId': conversationId,
      'latency': <String, dynamic>{
        'audioLoadMs': audioLoadMs,
        'audioFromDeviceCache': audioFromDeviceCache,
        'browserAudioStartedMs': timeToFirstAudioMs,
        'timeToFirstAudioMs': timeToFirstAudioMs,
        'audioStartedAfterStopMs': timeToFirstAudioMs,
        'responseToPlaybackMs': ?responseToPlaybackMs,
        'audioPreloadLoadedData': ?audioPreloadLoadedData,
        'audioPreloadCanPlay': ?audioPreloadCanPlay,
        'audioPreloadLoadedDataMs': ?audioPreloadLoadedDataMs,
        'audioPreloadCanPlayMs': ?audioPreloadCanPlayMs,
      },
    });
    Object? lastError;

    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final response = await _client
            .patch(
              _config.resolve('/api/history'),
              headers: const <String, String>{
                'content-type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 10));
        _decodeResponse(response);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }

    throw ConversationApiException(
      'Không gửi được telemetry phát audio: $lastError',
    );
  }

  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async {
    final clientId = await _clientId;
    final uri = _config
        .resolve('/api/history')
        .replace(
          queryParameters: <String, String>{
            'limit': '100',
            'clientId': clientId,
          },
        );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 10));
    final json = _decodeResponse(response);
    final conversations = json['conversations'];

    if (conversations is! List<dynamic>) {
      return const <ConversationHistoryItem>[];
    }
    return conversations
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => ConversationHistoryItem.fromJson(
            item,
            backendBaseUri: _config.backendBaseUri,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteHistoryItem(String conversationId) async {
    final clientId = await _clientId;
    final uri = _config
        .resolve('/api/history')
        .replace(
          queryParameters: <String, String>{
            'conversationId': conversationId,
            'clientId': clientId,
          },
        );
    final response = await _client
        .delete(uri)
        .timeout(const Duration(seconds: 10));
    _decodeResponse(response);
  }

  @override
  Future<void> clearHistory() async {
    final clientId = await _clientId;
    final uri = _config
        .resolve('/api/history')
        .replace(queryParameters: <String, String>{'clientId': clientId});
    final response = await _client
        .delete(uri)
        .timeout(const Duration(seconds: 10));
    _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> json = <String, dynamic>{};
    Object? decodeError;

    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else {
          decodeError = const FormatException(
            'Backend response is not a JSON object.',
          );
        }
      } on FormatException catch (error) {
        decodeError = error;
      }
    } else {
      decodeError = const FormatException('Backend response is empty.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json['error'];
      final message = error is Map<String, dynamic>
          ? error['message'] as String?
          : null;
      final errorCode = error is Map<String, dynamic>
          ? error['code'] as String?
          : null;
      final detailsValue = error is Map<String, dynamic>
          ? error['details']
          : null;
      final details = detailsValue is Map<String, dynamic>
          ? detailsValue
          : null;
      final requestId = response.headers['x-request-id']?.trim();
      final supportCode = requestId == null || requestId.isEmpty
          ? ''
          : ' Mã hỗ trợ: $requestId.';
      throw ConversationApiException(
        '${message ?? 'Backend trả về lỗi ${response.statusCode}.'}$supportCode',
        statusCode: response.statusCode,
        errorCode: errorCode,
        details: details,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }

    if (decodeError != null) {
      throw const ConversationApiException(
        'Backend trả về dữ liệu không hợp lệ.',
      );
    }

    return json;
  }

  Duration? _parseRetryAfter(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(normalized);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: math.min(seconds, 30));
    }
    final retryAt = DateTime.tryParse(normalized)?.toUtc();
    if (retryAt == null) {
      return null;
    }
    final delay = retryAt.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      return Duration.zero;
    }
    return delay > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : delay;
  }

  String _audioFilename(String mimeType) => switch (mimeType) {
    'audio/mp4' || 'audio/m4a' => 'utterance.m4a',
    'audio/wav' || 'audio/wave' || 'audio/x-wav' => 'utterance.wav',
    'audio/webm' || 'audio/webm;codecs=opus' => 'utterance.webm',
    _ => 'utterance.audio',
  };

  @override
  Future<void> dispose() async {
    if (_ownsClient) {
      _client.close();
    }
  }
}

// Legacy implementation retained only to decode and exercise old records.
// New production sessions are rejected by startRealtimeTranscription above.
// ignore: unused_element
class _LegacyRealtimeTranscriptionSession
    implements RealtimeTranscriptionSession {
  _LegacyRealtimeTranscriptionSession({
    required RealtimeSocket socket,
    required this.audioInputLabel,
    required this.bluetoothAudioInput,
    required DateTime sessionStartedAt,
    required DateTime connectedAt,
    required this.sessionCreateMs,
    required this.websocketConnectMs,
  }) : _socket = socket,
       _sessionStartedAt = sessionStartedAt,
       _connectedAt = connectedAt {
    _subscription = _socket.messages.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );
  }

  final RealtimeSocket _socket;
  final String audioInputLabel;
  final bool bluetoothAudioInput;
  final DateTime _sessionStartedAt;
  final DateTime _connectedAt;
  final int sessionCreateMs;
  final int websocketConnectMs;
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final Completer<String> _completed = Completer<String>();
  late final StreamSubscription<dynamic> _subscription;
  final StringBuffer _deltas = StringBuffer();
  DateTime? _firstDeltaAt;
  DateTime? _stopRequestedAt;
  DateTime? _recordingStartedAt;
  String _latestTranscript = '';
  double? _transcriptConfidence;
  bool _closed = false;

  @override
  Stream<String> get partialText => _partialController.stream;

  @override
  void markRecordingStarted(DateTime startedAt) {
    _recordingStartedAt ??= startedAt;
  }

  @override
  void addAudioChunk(Uint8List bytes) {
    if (_closed || _completed.isCompleted || bytes.isEmpty) {
      return;
    }
    try {
      _socket.add(
        jsonEncode(<String, dynamic>{
          'type': 'input_audio_buffer.append',
          'audio': base64Encode(bytes),
        }),
      );
    } catch (error, stackTrace) {
      _completed.completeError(
        ConversationApiException('Không thể gửi audio Realtime: $error'),
        stackTrace,
      );
    }
  }

  void _handleMessage(dynamic message) {
    if (_closed || message is! String) {
      return;
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final type = decoded['type'];
    if (type == 'conversation.item.input_audio_transcription.delta') {
      final delta = decoded['delta'];
      if (delta is String && delta.isNotEmpty) {
        _firstDeltaAt ??= DateTime.now();
        _deltas.write(delta);
        final partial = _deltas.toString().trim();
        if (partial.isNotEmpty && partial != _latestTranscript) {
          _latestTranscript = partial;
          _partialController.add(partial);
        }
      }
      return;
    }

    if (type == 'conversation.item.input_audio_transcription.completed') {
      final transcript = decoded['transcript'];
      if (transcript is String && transcript.trim().isNotEmpty) {
        final completedTranscript = transcript.trim();
        final selectedTranscript = preferCompleteVietnameseTranscript(
          partialText: _deltas.toString(),
          finalText: completedTranscript,
        );
        _latestTranscript = selectedTranscript;
        if (selectedTranscript == completedTranscript) {
          _transcriptConfidence = _confidenceFromLogProbs(decoded['logprobs']);
        }
      }
      if (!_completed.isCompleted) {
        _completed.complete(_latestTranscript);
      }
      return;
    }

    if (type == 'error' && !_completed.isCompleted) {
      final error = decoded['error'];
      final message = error is Map<String, dynamic>
          ? error['message'] as String?
          : null;
      _completed.completeError(
        ConversationApiException(
          message ?? 'Chế độ AI không thể nhận diện âm thanh.',
        ),
      );
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (!_completed.isCompleted) {
      _completed.completeError(
        ConversationApiException('Kết nối Chế độ AI bị lỗi: $error'),
        stackTrace,
      );
    }
  }

  void _handleDone() {
    if (!_closed && !_completed.isCompleted) {
      _completed.completeError(
        const ConversationApiException(
          'Kết nối Chế độ AI đã đóng trước khi có kết quả.',
        ),
      );
    }
  }

  @override
  Future<StreamingSpeechCapture> finalize() async {
    if (_closed) {
      throw const ConversationApiException(
        'Lượt Chế độ AI đã được hoàn tất hoặc hủy.',
      );
    }
    _stopRequestedAt = DateTime.now();

    try {
      if (!_completed.isCompleted) {
        try {
          _socket.add(
            jsonEncode(<String, String>{'type': 'input_audio_buffer.commit'}),
          );
        } catch (error, stackTrace) {
          _completed.completeError(
            ConversationApiException(
              'Không thể hoàn tất audio Realtime: $error',
            ),
            stackTrace,
          );
        }
      }
      final sourceText = await _completed.future.timeout(
        const Duration(seconds: 10),
      );
      if (sourceText.trim().isEmpty) {
        throw const ConversationApiException(
          'Không nghe rõ câu nói. Hãy nói lại gần micro hơn.',
        );
      }
      final completedAt = DateTime.now();
      final latencyOrigin = _recordingStartedAt ?? _sessionStartedAt;
      final websocketOpenAfterRecordingMs = _connectedAt
          .difference(latencyOrigin)
          .inMilliseconds
          .clamp(0, 1 << 31)
          .toInt();
      final firstResultMs = _firstDeltaAt
          ?.difference(latencyOrigin)
          .inMilliseconds
          .clamp(0, 1 << 31)
          .toInt();
      final finalAfterStopMs = completedAt
          .difference(_stopRequestedAt!)
          .inMilliseconds
          .clamp(0, 1 << 31)
          .toInt();
      developer.log(
        jsonEncode(<String, dynamic>{
          'event': 'openai_realtime_latency',
          'sessionCreateMs': sessionCreateMs,
          'websocketConnectMs': websocketConnectMs,
          'websocketOpenAfterRecordingMs': websocketOpenAfterRecordingMs,
          'firstTranscriptDeltaAfterRecordingMs': firstResultMs,
          'finalTranscriptAfterStopMs': finalAfterStopMs,
          'chunkDurationMs': pcmChunkDurationMs,
        }),
        name: 'openai_realtime_latency',
      );
      return StreamingSpeechCapture(
        sourceText: sourceText.trim(),
        duration: _stopRequestedAt!.difference(latencyOrigin),
        inputLabel: audioInputLabel,
        confidence: _transcriptConfidence,
        firstResultMs: firstResultMs,
        finalAfterStopMs: finalAfterStopMs,
        asrMode: AsrMode.openAiRealtime.apiValue,
        isBluetoothInput: bluetoothAudioInput,
        realtimeSessionCreateMs: sessionCreateMs,
        realtimeWebSocketConnectMs: websocketConnectMs,
        realtimeWebSocketOpenAfterRecordingMs: websocketOpenAfterRecordingMs,
        realtimeChunkDurationMs: pcmChunkDurationMs,
      );
    } finally {
      await _close();
    }
  }

  double? _confidenceFromLogProbs(dynamic value) {
    if (value is! List || value.isEmpty) {
      return null;
    }
    final logProbs = value
        .whereType<Map<String, dynamic>>()
        .map((entry) => entry['logprob'])
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
    if (logProbs.isEmpty) {
      return null;
    }
    final average =
        logProbs.reduce((left, right) => left + right) / logProbs.length;
    return math.exp(average).clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> discard() async {
    if (_closed) {
      return;
    }
    try {
      if (!_completed.isCompleted) {
        _socket.add(
          jsonEncode(<String, String>{'type': 'input_audio_buffer.clear'}),
        );
      }
    } finally {
      await _close();
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _socket.close(1000);
    } finally {
      await _subscription.cancel();
      await _partialController.close();
    }
  }
}

class _AudioSessionDescriptor {
  const _AudioSessionDescriptor({
    required this.id,
    required this.supportsPcm16WavFinalize,
    required this.uploadToken,
    required this.supportsChunkChecksum,
    required this.supportsMissingChunkRecovery,
    required this.supportsBatchPrefetch,
    required this.uploadProtocolVersion,
  });

  final String id;
  final bool supportsPcm16WavFinalize;
  final String? uploadToken;
  final bool supportsChunkChecksum;
  final bool supportsMissingChunkRecovery;
  final bool supportsBatchPrefetch;
  final int uploadProtocolVersion;
}

class _BatchSpeculativePreview {
  const _BatchSpeculativePreview({
    required this.prefetchId,
    required this.snapshotChunkCount,
    required this.preview,
  });

  final String prefetchId;
  final int snapshotChunkCount;
  final ConversationPreview preview;
}

class _WorkerAsrTranscript {
  const _WorkerAsrTranscript({
    required this.sourceText,
    required this.snapshotChunkCount,
    required this.snapshotHash,
    required this.audioBytes,
    required this.rttMs,
    required this.asrMs,
  });

  final String sourceText;
  final int snapshotChunkCount;
  final String snapshotHash;
  final int audioBytes;
  final int rttMs;
  final int? asrMs;
}

class _PreparedWorkerConversation {
  const _PreparedWorkerConversation({
    required this.prepareId,
    required this.transcript,
    required this.result,
    required this.preview,
  });

  final String prepareId;
  final _WorkerAsrTranscript transcript;
  final ConversationResult result;
  final ConversationPreview preview;
}

class _NextBatchChunkUploadSession
    implements BatchChunkUploadSession, SpeculativeBatchChunkUploadSession {
  _NextBatchChunkUploadSession({
    required NextConversationRepository repository,
    required this.audioSessionId,
    required this.sessionCreateMs,
    required this.supportsPcm16WavFinalize,
    required this.uploadToken,
    required this.supportsChunkChecksum,
    required this.supportsMissingChunkRecovery,
    required this.supportsBatchPrefetch,
    required this.uploadProtocolVersion,
  }) : _repository = repository,
       _uploadLanes = List<Future<void>>.generate(
         _maxConcurrentUploads,
         (_) => Future<void>.value(),
       ) {
    _sessionStopwatch.start();
  }

  static const _defaultSourceChunksPerTransportUpload = 4;
  static const _webSourceChunksPerTransportUpload = 3;
  static const _maxConcurrentUploads = 2;
  static const _maxMissingRecoveryRounds = 2;
  static const _maxRetainedAudioBytes = 2 * 1024 * 1024;
  static const _maxSpeculativeAttempts = 4;
  static const _maxRegularSpeculativeAttempts = 3;
  static const _minimumPreparedWorkerLeadMs = 300;

  final NextConversationRepository _repository;
  final String audioSessionId;
  final int sessionCreateMs;
  final bool supportsPcm16WavFinalize;
  final String? uploadToken;
  final bool supportsChunkChecksum;
  final bool supportsMissingChunkRecovery;
  final bool supportsBatchPrefetch;
  final int uploadProtocolVersion;
  final List<Future<void>> _pendingUploads = <Future<void>>[];
  final List<Future<void>> _uploadLanes;
  final BytesBuilder _transportBuffer = BytesBuilder(copy: false);
  final Map<int, _RetainedTransportChunk> _retainedChunks =
      <int, _RetainedTransportChunk>{};
  final Map<int, int> _transportChunkByteLengths = <int, int>{};
  final Set<int> _ackedTransportSequences = <int>{};
  final List<int> _chunkUploadDurationsMs = <int>[];
  final Stopwatch _sessionStopwatch = Stopwatch();
  final StreamController<ConversationPreview> _speculativePreviewController =
      StreamController<ConversationPreview>.broadcast();
  late var _nextSequence = supportsPcm16WavFinalize ? 0 : 1;
  var _nextUploadLane = 0;
  var _sourceChunkCount = 0;
  var _sourceChunksPerTransportUpload = _defaultSourceChunksPerTransportUpload;
  var _transportChunkCount = 0;
  late var _nextContiguousAckSequence = supportsPcm16WavFinalize ? 0 : 1;
  var _contiguousAckedChunkCount = 0;
  var _contiguousAckedPcmByteLength = 0;
  var _audioByteCount = 0;
  var _retainedAudioBytes = 0;
  var _chunkRetryCount = 0;
  var _missingChunkCount = 0;
  var _recoveryUploadCount = 0;
  int? _firstChunkAckMs;
  int? _lastFailedSequence;
  String? _lastUploadErrorCode;
  var _recoveryBufferTruncated = false;
  var _closed = false;
  var _finalizing = false;
  var _discarded = false;
  PracticeContext? _speculativeContext;
  int? _speculativeChildAge;
  bool _speculativeSpeechDetected = false;
  bool _speculativeVoiceActive = false;
  int _speculativeAttemptCount = 0;
  int _speculativeTransientRetryCount = 0;
  int _terminalSpeculativeAttemptCount = 0;
  int _terminalDuplicateSuppressed = 0;
  int _speechGeneration = 0;
  int _lastTerminalSpeechGeneration = 0;
  DateTime? _speculativeVoiceInactiveAt;
  int? _vadSilenceAtSessionMs;
  int? _terminalPreviewRequestedAtSessionMs;
  int? _terminalPipelineStartedAtSessionMs;
  int? _terminalUploadWaitMs;
  int? _terminalSnapshotAckedChunkCount;
  int? _finalizeRequestSentAtSessionMs;
  int? _terminalPreviewStartedAfterVoiceInactiveMs;
  int _lastSpeculativeAttemptChunkCount = 0;
  int _lastTerminalSpeculativeAttemptChunkCount = 0;
  DateTime? _lastSpeculativeAttemptAt;
  Timer? _speculativePreviewTimer;
  Future<void>? _speculativePreviewFuture;
  Future<void>? _terminalSpeculativePreviewFuture;
  bool _terminalSpeculativePreviewRequested = false;
  bool _terminalPreviewCoversLatestSpeech = false;
  int _latestAcceptedPreviewChunkCount = 0;
  bool _latestAcceptedPreviewWasTerminal = false;
  String? _prefetchId;
  bool _workerAsrPilotAttempted = false;
  String? _workerAsrPilotFallbackCode;
  int? _workerAsrPilotFallbackMs;
  final Map<String, Future<_WorkerAsrTranscript>> _workerTranscriptFlights =
      <String, Future<_WorkerAsrTranscript>>{};
  _WorkerAsrTranscript? _readyWorkerTranscript;
  _PreparedWorkerConversation? _readyWorkerPreparation;
  Future<_PreparedWorkerConversation?>? _workerPrepareFlight;
  Future<_WorkerAsrTranscript>? _workerActiveTranscriptFlight;
  int? _workerPrepareSpeechGeneration;
  int? _workerPrepareStartedAtSessionMs;
  int? _workerTranscriptReadyAtSessionMs;
  int? _workerPreparationReadyAtSessionMs;
  int? _workerFinalizeStartedAtSessionMs;
  bool _workerPrepareJoinedAtFinalize = false;
  bool _workerPrepareAbandoned = false;
  bool _workerPrepareSkippedLowLead = false;
  bool _workerPrepareAbandonedAtFinalize = false;
  bool _workerLatePrepareSkipped = false;
  String? _workerPrepareFailureCode;
  int _workerPrepareDuplicateSuppressed = 0;
  int _workerPrepareInvalidated = 0;
  final Map<String, dynamic> _clientTerminalTelemetry = <String, dynamic>{};

  bool get _usesWorkerPrepare =>
      _repository._config.workerAsrPrepareReady &&
      supportsPcm16WavFinalize &&
      uploadToken != null;

  @override
  Stream<ConversationPreview> get speculativePreviews =>
      _speculativePreviewController.stream;

  @override
  void configureSpeculativePreview({
    required PracticeContext context,
    required int childAge,
  }) {
    if ((!supportsBatchPrefetch && !_usesWorkerPrepare) ||
        _closed ||
        _finalizing) {
      return;
    }
    // This configuration is only called by the adaptive Web manager. Android
    // Streaming and its Batch fallback retain the established 800 ms chunks.
    _sourceChunksPerTransportUpload = _webSourceChunksPerTransportUpload;
    _speculativeContext = context;
    _speculativeChildAge = childAge;
    if (!_usesWorkerPrepare) {
      _scheduleSpeculativePreview();
    }
  }

  @override
  void markSpeculativeSpeechDetected() {
    if ((!supportsBatchPrefetch && !_usesWorkerPrepare) ||
        _closed ||
        _finalizing) {
      return;
    }
    final firstDetection = !_speculativeSpeechDetected;
    _speculativeSpeechDetected = true;
    if (firstDetection) {
      _speechGeneration = 1;
    } else if (_terminalSpeculativePreviewRequested ||
        _terminalSpeculativeAttemptCount > 0 ||
        _terminalSpeculativePreviewFuture != null ||
        _terminalPreviewCoversLatestSpeech ||
        _workerPrepareFlight != null ||
        _readyWorkerTranscript != null ||
        _readyWorkerPreparation != null) {
      // Only an actual VAD speech-start event opens a new terminal generation.
      // Raw voice-active/noise frames are deliberately insufficient because
      // they previously caused a silence-only final chunk to launch ASR twice.
      _speechGeneration += 1;
      _terminalSpeculativePreviewRequested = false;
      _terminalPreviewCoversLatestSpeech = false;
      _terminalPreviewRequestedAtSessionMs = null;
      _terminalPipelineStartedAtSessionMs = null;
      _terminalUploadWaitMs = null;
      _terminalSnapshotAckedChunkCount = null;
      _terminalPreviewStartedAfterVoiceInactiveMs = null;
      _readyWorkerTranscript = null;
      _readyWorkerPreparation = null;
      _workerPrepareSpeechGeneration = null;
      _workerPrepareStartedAtSessionMs = null;
      _workerTranscriptReadyAtSessionMs = null;
      _workerPreparationReadyAtSessionMs = null;
      _workerPrepareJoinedAtFinalize = false;
      _workerPrepareAbandoned = false;
      _workerPrepareSkippedLowLead = false;
      _workerPrepareAbandonedAtFinalize = false;
      _workerLatePrepareSkipped = false;
      _workerPrepareFailureCode = null;
      _workerActiveTranscriptFlight = null;
      _workerPrepareInvalidated += 1;
    }
    if (!_usesWorkerPrepare) {
      _scheduleSpeculativePreview();
    }
  }

  @override
  void markSpeculativeVoiceActive() {
    _speculativeVoiceActive = true;
    _speculativeVoiceInactiveAt = null;
    _vadSilenceAtSessionMs = null;
    // Do not invalidate terminal work for a raw voice-active frame. A new
    // terminal generation is opened by markSpeculativeSpeechDetected(), which
    // represents a confirmed VAD speech start rather than transient noise.
  }

  @override
  void markSpeculativeVoiceInactive() {
    if (_speculativeVoiceActive || _speculativeVoiceInactiveAt == null) {
      _speculativeVoiceInactiveAt = DateTime.now();
      _vadSilenceAtSessionMs = _sessionStopwatch.elapsedMilliseconds;
    }
    _speculativeVoiceActive = false;
    if ((!supportsBatchPrefetch && !_usesWorkerPrepare) ||
        _closed ||
        _finalizing ||
        !_speculativeSpeechDetected) {
      return;
    }
    // Upload the speech-end bytes now, but reserve this snapshot for the
    // delayed terminal request. Scheduling a regular preview here used to
    // consume the same chunkCount and made the terminal request a no-op.
    _flushTransportBuffer(schedulePreview: false);
  }

  @override
  void updateClientTerminalTelemetry(Map<String, dynamic> telemetry) {
    if (_closed || telemetry.isEmpty) {
      return;
    }
    _clientTerminalTelemetry.addAll(telemetry);
  }

  @override
  void requestTerminalSpeculativePreview({bool atRecorderStop = false}) {
    _speculativeVoiceActive = false;
    if ((!supportsBatchPrefetch && !_usesWorkerPrepare) ||
        _closed ||
        !_speculativeSpeechDetected ||
        _speculativeContext == null ||
        _speculativeChildAge == null) {
      return;
    }
    _terminalPreviewRequestedAtSessionMs ??=
        _sessionStopwatch.elapsedMilliseconds;
    if (_usesWorkerPrepare) {
      if (atRecorderStop) {
        // A terminal request created only after recorder.stop() has no lead to
        // hide ASR/translation. Let finalize use Worker-only instead of adding
        // prepare + commit to the critical path.
        _workerLatePrepareSkipped =
            _workerPrepareFlight == null &&
            _readyWorkerTranscript == null &&
            _readyWorkerPreparation == null;
        if (!_workerLatePrepareSkipped) {
          _workerPrepareDuplicateSuppressed += 1;
        }
        return;
      }
      _flushTransportBuffer(schedulePreview: false);
      _scheduleWorkerPrepare();
      return;
    }
    if (_terminalPreviewCoversLatestSpeech) {
      // Recorder stop can append one final silence-only PCM frame. Keep the
      // terminal pipeline that already started during VAD silence; backend tail
      // validation decides whether that earlier snapshot remains authoritative.
      _terminalDuplicateSuppressed += 1;
      return;
    }
    _terminalSpeculativePreviewRequested = true;
    _speculativePreviewTimer?.cancel();
    _speculativePreviewTimer = null;
    _flushTransportBuffer(schedulePreview: false);
    _scheduleSpeculativePreview(terminal: true);
  }

  void _scheduleWorkerPrepare() {
    if (!_usesWorkerPrepare ||
        _closed ||
        _finalizing ||
        _speculativeVoiceActive ||
        !_speculativeSpeechDetected) {
      return;
    }
    final context = _speculativeContext;
    final childAge = _speculativeChildAge;
    final pcmBytes = _retainedPcmForWorkerPilot();
    if (context == null || childAge == null || pcmBytes == null) {
      return;
    }
    final snapshotHash = crypto.sha256.convert(pcmBytes).toString();
    final generation = _speechGeneration;
    if (_workerPrepareSpeechGeneration == generation &&
        (_readyWorkerTranscript?.snapshotHash == snapshotHash ||
            _readyWorkerPreparation?.transcript.snapshotHash == snapshotHash ||
            _workerPrepareFlight != null)) {
      _workerPrepareDuplicateSuppressed += 1;
      return;
    }

    _workerAsrPilotAttempted = true;
    _workerPrepareSpeechGeneration = generation;
    _workerPrepareAbandoned = false;
    _workerPrepareStartedAtSessionMs = _sessionStopwatch.elapsedMilliseconds;
    final immutablePcm = Uint8List.fromList(pcmBytes);
    final transcriptFlight = _workerTranscriptFlights.putIfAbsent(
      snapshotHash,
      () => _repository._transcribeWorkerAsrPilot(
        audioSessionId: audioSessionId,
        uploadToken: uploadToken!,
        pcmBytes: immutablePcm,
        snapshotChunkCount: _transportChunkCount,
      ),
    );
    _workerActiveTranscriptFlight = transcriptFlight;
    final operation = () async {
      try {
        final transcript = await transcriptFlight;
        if (_closed || generation != _speechGeneration) {
          return null;
        }
        _readyWorkerTranscript = transcript;
        _workerTranscriptReadyAtSessionMs =
            _sessionStopwatch.elapsedMilliseconds;
        if (_workerPrepareAbandoned) {
          return null;
        }
        final prepared = await _repository._prepareWorkerConversation(
          audioSessionId: audioSessionId,
          transcript: transcript,
          context: context,
          childAge: childAge,
          // The authoritative value is attached during commit. Preparation
          // does not use this value for rule/translation/TTS decisions.
          vadSilenceMs: 0,
          workerStartedAtSessionMs: _workerPrepareStartedAtSessionMs!,
        );
        if (_closed || generation != _speechGeneration) {
          return null;
        }
        _readyWorkerPreparation = prepared;
        _workerPreparationReadyAtSessionMs =
            _sessionStopwatch.elapsedMilliseconds;
        if (!_speculativePreviewController.isClosed) {
          _speculativePreviewController.add(prepared.preview);
          // Give the controller one event-loop turn to attach Safari's
          // existing HTMLAudioElement to the streaming URL before the commit
          // response wins the race back to the client.
          await Future<void>.delayed(Duration.zero);
        }
        return prepared;
      } catch (error, stackTrace) {
        if (generation == _speechGeneration) {
          _workerPrepareFailureCode = error is ConversationApiException
              ? error.errorCode ?? 'WORKER_ASR_PILOT_FAILED'
              : error.runtimeType.toString();
        }
        developer.log(
          'Early Worker prepare failed; finalize will use the established fallback.',
          name: 'conversation.worker_asr_prepare',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }();
    _workerPrepareFlight = operation;
    unawaited(
      operation.then<void>((_) {
        if (identical(_workerPrepareFlight, operation)) {
          _workerPrepareFlight = null;
        }
      }),
    );
  }

  @override
  void addAudioChunk(Uint8List bytes) {
    if (_closed || _finalizing || bytes.isEmpty) {
      return;
    }
    final immutableBytes = Uint8List.fromList(bytes);
    _audioByteCount += immutableBytes.length;
    _sourceChunkCount += 1;
    _transportBuffer.add(immutableBytes);
    if (_sourceChunkCount % _sourceChunksPerTransportUpload == 0) {
      // Once VAD has entered silence, continue uploading bytes without letting
      // a regular preview steal the snapshot reserved for terminal prefetch.
      _flushTransportBuffer(schedulePreview: _speculativeVoiceActive);
    }
  }

  void _flushTransportBuffer({bool schedulePreview = true}) {
    if (_transportBuffer.length == 0) {
      return;
    }
    final sequence = _nextSequence++;
    final bytes = _transportBuffer.takeBytes();
    _transportChunkCount += 1;
    _scheduleNewUpload(
      sequence: sequence,
      bytes: bytes,
      filename: 'chunk-$sequence.pcm',
    );
    if (_terminalSpeculativePreviewRequested && !_speculativeVoiceActive) {
      // A terminal request can arrive before the second transport chunk is
      // available. Wake it as soon as the next silence chunk is flushed;
      // otherwise it would remain pending until recorder.stop().
      _scheduleSpeculativePreview(terminal: true);
    } else if (schedulePreview && !_usesWorkerPrepare) {
      _scheduleSpeculativePreview();
    }
  }

  void _scheduleSpeculativePreview({bool terminal = false}) {
    if (_usesWorkerPrepare) {
      return;
    }
    final terminalAttempt = terminal || _terminalSpeculativePreviewRequested;
    final availableChunkCount = terminalAttempt
        ? _contiguousAckedChunkCount
        : _transportChunkCount;
    final activePreviewFuture = terminalAttempt
        ? _terminalSpeculativePreviewFuture
        : _speculativePreviewFuture;
    if (!supportsBatchPrefetch ||
        _closed ||
        (_finalizing && !terminalAttempt) ||
        (terminalAttempt && _speculativeVoiceActive) ||
        !_speculativeSpeechDetected ||
        _speculativeContext == null ||
        _speculativeChildAge == null ||
        (terminalAttempt
            ? _speculativeAttemptCount >= _maxSpeculativeAttempts
            : _speculativeAttemptCount >= _maxRegularSpeculativeAttempts) ||
        availableChunkCount < 2 ||
        activePreviewFuture != null) {
      return;
    }

    if (terminalAttempt) {
      final hasPreviousTerminal = _lastTerminalSpeculativeAttemptChunkCount > 0;
      final hasNewAckedSnapshot =
          availableChunkCount > _lastTerminalSpeculativeAttemptChunkCount;
      final hasConfirmedNewSpeech =
          _speechGeneration > _lastTerminalSpeechGeneration;
      if (hasPreviousTerminal &&
          !(hasNewAckedSnapshot && hasConfirmedNewSpeech)) {
        _terminalSpeculativePreviewRequested = false;
        _terminalDuplicateSuppressed += 1;
        return;
      }
    } else {
      if (availableChunkCount < _lastSpeculativeAttemptChunkCount) {
        return;
      }
      if (availableChunkCount == _lastSpeculativeAttemptChunkCount) {
        return;
      }
    }

    const minimumInterval = Duration(milliseconds: 700);
    final lastAttemptAt = _lastSpeculativeAttemptAt;
    final delay = terminalAttempt || lastAttemptAt == null
        ? Duration.zero
        : minimumInterval - DateTime.now().difference(lastAttemptAt);
    if (delay > Duration.zero) {
      _speculativePreviewTimer ??= Timer(delay, () {
        _speculativePreviewTimer = null;
        _scheduleSpeculativePreview(terminal: terminalAttempt);
      });
      return;
    }

    final context = _speculativeContext!;
    final childAge = _speculativeChildAge!;
    final snapshotChunkCount = availableChunkCount;
    final snapshotByteLength = terminalAttempt
        ? _contiguousAckedPcmByteLength
        : _retainedAudioBytes;
    final uploadWatermark = terminalAttempt
        ? const <Future<void>>[]
        : List<Future<void>>.of(_uploadLanes);
    if (terminalAttempt) {
      _terminalSpeculativePreviewRequested = false;
      _terminalSpeculativeAttemptCount += 1;
      _lastTerminalSpeculativeAttemptChunkCount = snapshotChunkCount;
      _lastTerminalSpeechGeneration = _speechGeneration;
      _terminalSnapshotAckedChunkCount = snapshotChunkCount;
      _terminalPreviewCoversLatestSpeech = true;
      final voiceInactiveAt = _speculativeVoiceInactiveAt;
      if (voiceInactiveAt != null) {
        _terminalPreviewStartedAfterVoiceInactiveMs ??= DateTime.now()
            .difference(voiceInactiveAt)
            .inMilliseconds;
      }
    }
    _speculativeAttemptCount += 1;
    _lastSpeculativeAttemptChunkCount = math.max(
      _lastSpeculativeAttemptChunkCount,
      snapshotChunkCount,
    );
    _lastSpeculativeAttemptAt = DateTime.now();
    final operation = _requestSpeculativePreview(
      context: context,
      childAge: childAge,
      snapshotChunkCount: snapshotChunkCount,
      snapshotByteLength: snapshotByteLength,
      uploadWatermark: uploadWatermark,
      terminal: terminalAttempt,
    );
    if (terminalAttempt) {
      _terminalSpeculativePreviewFuture = operation;
    } else {
      _speculativePreviewFuture = operation;
    }
    unawaited(
      operation
          .whenComplete(() {
            if (terminalAttempt) {
              if (identical(_terminalSpeculativePreviewFuture, operation)) {
                _terminalSpeculativePreviewFuture = null;
              }
            } else if (identical(_speculativePreviewFuture, operation)) {
              _speculativePreviewFuture = null;
            }
            if (!_closed &&
                (_terminalSpeculativePreviewRequested ||
                    (!_finalizing &&
                        _speculativeVoiceActive &&
                        _transportChunkCount >
                            _lastSpeculativeAttemptChunkCount))) {
              _scheduleSpeculativePreview(
                terminal: _terminalSpeculativePreviewRequested,
              );
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _requestSpeculativePreview({
    required PracticeContext context,
    required int childAge,
    required int snapshotChunkCount,
    required int snapshotByteLength,
    required List<Future<void>> uploadWatermark,
    required bool terminal,
  }) async {
    try {
      await Future.wait<void>(uploadWatermark);
      if (_closed) {
        return;
      }
      if (terminal) {
        final pipelineStartedAt = _sessionStopwatch.elapsedMilliseconds;
        _terminalPipelineStartedAtSessionMs ??= pipelineStartedAt;
        final requestedAt = _terminalPreviewRequestedAtSessionMs;
        if (requestedAt != null) {
          _terminalUploadWaitMs ??= math.max(
            0,
            pipelineStartedAt - requestedAt,
          );
        }
      }
      final result = await _repository._previewAudioSession(
        audioSessionId: audioSessionId,
        uploadToken: uploadToken,
        context: context,
        childAge: childAge,
        pcmByteLength: snapshotByteLength,
        chunkCount: snapshotChunkCount,
        terminal: terminal,
        previousPrefetchId: _prefetchId,
        benchmark: terminal
            ? <String, dynamic>{
                if (_vadSilenceAtSessionMs != null)
                  'batchVadSilenceAtSessionMs': _vadSilenceAtSessionMs,
                if (_terminalPreviewRequestedAtSessionMs != null)
                  'batchTerminalRequestSentAtSessionMs':
                      _terminalPreviewRequestedAtSessionMs,
                if (_terminalPipelineStartedAtSessionMs != null)
                  'batchTerminalPipelineStartedAtSessionMs':
                      _terminalPipelineStartedAtSessionMs,
                if (_terminalUploadWaitMs != null)
                  'batchTerminalUploadWaitMs': _terminalUploadWaitMs,
                if (_terminalSnapshotAckedChunkCount != null)
                  'batchTerminalSnapshotAckedChunkCount':
                      _terminalSnapshotAckedChunkCount,
                'batchTerminalDuplicateSuppressed':
                    _terminalDuplicateSuppressed,
              }
            : null,
      );
      if (result == null || _closed) {
        if (terminal) {
          _terminalPreviewCoversLatestSpeech = false;
        }
        return;
      }
      // A slower regular preview may finish after the terminal snapshot. Do
      // not let that stale response replace the newer prefetch id/audio that
      // Safari already preloaded.
      if (result.snapshotChunkCount < _latestAcceptedPreviewChunkCount ||
          (result.snapshotChunkCount == _latestAcceptedPreviewChunkCount &&
              _latestAcceptedPreviewWasTerminal &&
              !terminal)) {
        return;
      }
      _latestAcceptedPreviewChunkCount = result.snapshotChunkCount;
      _latestAcceptedPreviewWasTerminal = terminal;
      _prefetchId = result.prefetchId;
      _lastSpeculativeAttemptChunkCount = math.max(
        _lastSpeculativeAttemptChunkCount,
        result.snapshotChunkCount,
      );
      if (!_speculativePreviewController.isClosed) {
        _speculativePreviewController.add(result.preview);
      }
    } catch (error, stackTrace) {
      if (_isRetryableConversationRequest(error) && !_closed) {
        // A regular preview may retry a transient provider failure. Terminal
        // snapshots do not retry: finalize is already the authoritative
        // fallback and a second terminal used to duplicate Cloudflare work.
        _speculativeTransientRetryCount += 1;
        if (terminal) {
          // Finalize remains the authoritative fallback. Never relaunch the
          // same terminal snapshot after timeout/429/5xx; this was the source
          // of duplicate Cloudflare pipelines several seconds apart.
          _terminalPreviewCoversLatestSpeech = false;
        } else {
          _speculativeAttemptCount = math.max(0, _speculativeAttemptCount - 1);
          _lastSpeculativeAttemptChunkCount = math.min(
            _lastSpeculativeAttemptChunkCount,
            math.max(0, snapshotChunkCount - 1),
          );
        }
      }
      developer.log(
        'Speculative Batch preview was skipped.',
        name: 'conversation.batch_prefetch',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _scheduleNewUpload({
    required int sequence,
    required Uint8List bytes,
    required String filename,
  }) {
    final chunk = _RetainedTransportChunk(
      sequence: sequence,
      bytes: bytes,
      filename: filename,
    );
    _transportChunkByteLengths[sequence] = bytes.length;
    if (_retainedAudioBytes + bytes.length <= _maxRetainedAudioBytes) {
      _retainedChunks[sequence] = chunk;
      _retainedAudioBytes += bytes.length;
    } else {
      _recoveryBufferTruncated = true;
    }
    _scheduleUpload(chunk);
  }

  void _scheduleUpload(_RetainedTransportChunk chunk, {bool recovery = false}) {
    if (recovery) {
      _recoveryUploadCount += 1;
    }
    final laneIndex = _nextUploadLane;
    _nextUploadLane = (_nextUploadLane + 1) % _uploadLanes.length;
    final previousLane = _uploadLanes[laneIndex].then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final upload = previousLane.then<void>((_) => _uploadWithRetry(chunk));
    _uploadLanes[laneIndex] = upload;
    _pendingUploads.add(upload);
    unawaited(upload.catchError((Object _) {}));
  }

  Future<void> _uploadWithRetry(_RetainedTransportChunk chunk) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      final uploadStopwatch = Stopwatch()..start();
      try {
        await _repository._uploadAudioBytes(
          audioSessionId: audioSessionId,
          sequence: chunk.sequence,
          bytes: chunk.bytes,
          filename: chunk.filename,
          sha256: chunk.sha256,
          uploadToken: uploadToken,
        );
        uploadStopwatch.stop();
        _chunkUploadDurationsMs.add(uploadStopwatch.elapsedMilliseconds);
        _firstChunkAckMs ??= _sessionStopwatch.elapsedMilliseconds;
        _markTransportChunkAcked(chunk.sequence);
        return;
      } catch (error) {
        uploadStopwatch.stop();
        lastError = error;
        _lastFailedSequence = chunk.sequence;
        _lastUploadErrorCode = error is ConversationApiException
            ? error.errorCode
            : error.runtimeType.toString();
        if (!_isRetryableConversationRequest(error)) {
          rethrow;
        }
        if (attempt < 3) {
          _chunkRetryCount += 1;
          await Future<void>.delayed(
            _conversationRetryDelay(
              error: lastError,
              attempt: attempt,
              baseMs: 150,
            ),
          );
        }
      }
    }
    if (lastError is ConversationApiException) {
      throw lastError;
    }
    throw ConversationApiException(
      'Không upload được audio chunk ${chunk.sequence}: $lastError',
    );
  }

  void _markTransportChunkAcked(int sequence) {
    if (!_ackedTransportSequences.add(sequence)) {
      return;
    }
    while (_ackedTransportSequences.remove(_nextContiguousAckSequence)) {
      _contiguousAckedPcmByteLength +=
          _transportChunkByteLengths[_nextContiguousAckSequence] ?? 0;
      _contiguousAckedChunkCount += 1;
      _nextContiguousAckSequence += 1;
    }
    if (_terminalSpeculativePreviewRequested && !_speculativeVoiceActive) {
      // The terminal snapshot is defined only by the contiguous chunk prefix
      // already acknowledged by the backend. No upload-lane drain is needed.
      _scheduleSpeculativePreview(terminal: true);
    }
  }

  Future<void> _drainPendingUploads() async {
    if (_pendingUploads.isEmpty) {
      return;
    }
    final pending = List<Future<void>>.of(_pendingUploads);
    _pendingUploads.clear();
    await Future.wait<void>(pending);
  }

  Uint8List? _retainedPcmForWorkerPilot() {
    if (!supportsPcm16WavFinalize ||
        _recoveryBufferTruncated ||
        _retainedAudioBytes <= 0 ||
        _retainedAudioBytes != _audioByteCount) {
      return null;
    }
    final chunks = _retainedChunks.values.toList(growable: false)
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    if (chunks.length != _transportChunkCount) {
      return null;
    }
    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < chunks.length; index += 1) {
      if (chunks[index].sequence != index) {
        return null;
      }
      builder.add(chunks[index].bytes);
    }
    return builder.takeBytes();
  }

  bool _workerSnapshotStillValid(
    _WorkerAsrTranscript transcript,
    Uint8List finalPcm,
  ) {
    if (_workerPrepareSpeechGeneration != _speechGeneration ||
        transcript.audioBytes > finalPcm.length) {
      return false;
    }
    final snapshotBytes = transcript.audioBytes == finalPcm.length
        ? finalPcm
        : Uint8List.sublistView(finalPcm, 0, transcript.audioBytes);
    return crypto.sha256.convert(snapshotBytes).toString() ==
        transcript.snapshotHash;
  }

  Map<String, dynamic> _workerFinalBenchmark({
    required AudioCapture capture,
    required int vadSilenceMs,
    required _WorkerAsrTranscript transcript,
    required bool preparedCommit,
  }) {
    final finalizeStartedAt = _workerFinalizeStartedAtSessionMs;
    final workerStartedAt = _workerPrepareStartedAtSessionMs;
    final transcriptReadyAt = _workerTranscriptReadyAtSessionMs;
    final preparationReadyAt = _workerPreparationReadyAtSessionMs;
    return <String, dynamic>{
      ...ConversationBenchmark(
        utteranceDurationMs: capture.duration.inMilliseconds,
        vadSilenceMs: vadSilenceMs,
        requestedAsrMode: AsrMode.workerAsrPilot,
        audioInputLabel: capture.inputLabel,
        bluetoothAudioInput: capture.isBluetoothInput,
        initialNoiseRms: capture.initialNoiseRms,
        clientVadApplied: true,
        audioProcessing: capture.audioProcessing,
      ).toJson(),
      'workerAsrPilotAttempted': true,
      'workerAsrPilotRttMs': transcript.rttMs,
      if (transcript.asrMs != null) 'workerAsrPilotAsrMs': transcript.asrMs,
      'workerAsrPilotAudioBytes': transcript.audioBytes,
      'workerPrepareAttempted': _workerPrepareSpeechGeneration != null,
      'workerPreparedCommit': preparedCommit,
      'workerPrepareJoinedAtFinalize': _workerPrepareJoinedAtFinalize,
      'workerPrepareSkippedLowLead': _workerPrepareSkippedLowLead,
      'workerPrepareAbandonedAtFinalize': _workerPrepareAbandonedAtFinalize,
      'workerLatePrepareSkipped': _workerLatePrepareSkipped,
      if (_workerPrepareFailureCode != null)
        'workerPrepareFailureCode': _workerPrepareFailureCode,
      'workerPrepareDuplicateSuppressed': _workerPrepareDuplicateSuppressed,
      'workerPrepareInvalidated': _workerPrepareInvalidated,
      'workerFinalizeStartedAtSessionMs': ?finalizeStartedAt,
      if (workerStartedAt != null && finalizeStartedAt != null)
        'workerStartedBeforeStopMs': math.max(
          0,
          finalizeStartedAt - workerStartedAt,
        ),
      'workerTranscriptReadyAtSessionMs': ?transcriptReadyAt,
      if (transcriptReadyAt != null && finalizeStartedAt != null)
        if (transcriptReadyAt <= finalizeStartedAt)
          'workerTranscriptReadyBeforeStopMs':
              finalizeStartedAt - transcriptReadyAt
        else
          'workerTranscriptReadyAfterStopMs':
              transcriptReadyAt - finalizeStartedAt,
      'workerPreparationReadyAtSessionMs': ?preparationReadyAt,
      if (preparationReadyAt != null && finalizeStartedAt != null)
        if (preparationReadyAt <= finalizeStartedAt)
          'workerPreparationReadyBeforeStopMs':
              finalizeStartedAt - preparationReadyAt
        else
          'workerPreparationReadyAfterStopMs':
              preparationReadyAt - finalizeStartedAt,
      'workerTailVadEligible': _workerPrepareSpeechGeneration != null,
      ..._clientTerminalTelemetry,
    };
  }

  Future<ConversationResult?> _tryPreparedWorkerCommit({
    required Uint8List finalPcm,
    required AudioCapture capture,
    required int vadSilenceMs,
  }) async {
    final prepared = _readyWorkerPreparation;
    if (prepared == null) {
      return null;
    }
    if (!_workerSnapshotStillValid(prepared.transcript, finalPcm)) {
      developer.log(
        jsonEncode(<String, dynamic>{
          'event': 'worker_prepared_snapshot_rejected',
          'audioSessionId': audioSessionId,
          'preparedGeneration': _workerPrepareSpeechGeneration,
          'currentGeneration': _speechGeneration,
          'preparedAudioBytes': prepared.transcript.audioBytes,
          'finalAudioBytes': finalPcm.length,
        }),
        name: 'conversation.worker_asr_prepare',
      );
      return null;
    }
    return _repository._commitPreparedWorkerConversation(
      audioSessionId: audioSessionId,
      prepared: prepared,
      benchmark: _workerFinalBenchmark(
        capture: capture,
        vadSilenceMs: vadSilenceMs,
        transcript: prepared.transcript,
        preparedCommit: true,
      ),
    );
  }

  Future<ConversationResult?> _tryWorkerAsrPilot({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    if (!_repository._config.workerAsrPilotReady || uploadToken == null) {
      return null;
    }
    if (_workerPrepareSpeechGeneration == _speechGeneration &&
        _workerPrepareFailureCode != null &&
        _readyWorkerTranscript == null) {
      // The early terminal Worker already failed for this speech generation.
      // Go directly to the established Batch fallback instead of charging and
      // waiting for the same Worker ASR a second time after recorder.stop().
      _workerAsrPilotFallbackCode = _workerPrepareFailureCode;
      return null;
    }
    final pcmBytes = _retainedPcmForWorkerPilot();
    if (pcmBytes == null) {
      _workerAsrPilotFallbackCode = 'WORKER_ASR_PILOT_PCM_UNAVAILABLE';
      return null;
    }
    _workerAsrPilotAttempted = true;
    final stopwatch = Stopwatch()..start();
    late final _WorkerAsrTranscript transcript;
    try {
      final readyTranscript = _readyWorkerTranscript;
      final snapshotHash = crypto.sha256.convert(pcmBytes).toString();
      if (readyTranscript != null &&
          _workerSnapshotStillValid(readyTranscript, pcmBytes)) {
        transcript = readyTranscript;
      } else {
        final activeTranscript =
            _workerPrepareSpeechGeneration == _speechGeneration
            ? _workerActiveTranscriptFlight
            : null;
        final earlyTranscript = activeTranscript == null
            ? null
            : await activeTranscript;
        if (earlyTranscript != null &&
            _workerSnapshotStillValid(earlyTranscript, pcmBytes)) {
          transcript = earlyTranscript;
        } else {
          transcript = await _workerTranscriptFlights.putIfAbsent(
            snapshotHash,
            () => _repository._transcribeWorkerAsrPilot(
              audioSessionId: audioSessionId,
              uploadToken: uploadToken!,
              pcmBytes: Uint8List.fromList(pcmBytes),
              snapshotChunkCount: _transportChunkCount,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      stopwatch.stop();
      _workerAsrPilotFallbackMs = stopwatch.elapsedMilliseconds;
      _workerAsrPilotFallbackCode = error is ConversationApiException
          ? error.errorCode ?? 'WORKER_ASR_PILOT_FAILED'
          : error.runtimeType.toString();
      developer.log(
        'Worker ASR Pilot failed; continuing the existing Batch Chunks finalize.',
        name: 'conversation.worker_asr_pilot',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    // ASR succeeded, so a later rule/translation/TTS failure must surface as
    // that backend error. Re-running full Batch ASR here would add latency and
    // duplicate Cloudflare work without fixing the actual failing stage.
    return _repository._processWorkerTranscript(
      transcript: transcript,
      capture: capture,
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
      extraBenchmark: _workerFinalBenchmark(
        capture: capture,
        vadSilenceMs: vadSilenceMs,
        transcript: transcript,
        preparedCommit: false,
      ),
    );
  }

  Future<void> _discardShadowSessionAfterWorkerSuccess(
    Future<void> uploadDrain,
  ) async {
    try {
      await uploadDrain;
    } catch (_) {
      // The Worker result is already authoritative. Cleanup is best-effort.
    }
    await _repository
        ._discardAudioSession(
          audioSessionId,
          uploadToken: uploadToken,
          reason: 'worker_asr_pilot_succeeded',
        )
        .catchError((Object _) {});
  }

  List<int> _missingSequences(Object error) {
    if (!supportsMissingChunkRecovery ||
        error is! ConversationApiException ||
        error.errorCode != 'AUDIO_CHUNKS_MISSING') {
      return const <int>[];
    }
    final raw = error.details?['missingSequences'];
    if (raw is! List<dynamic>) {
      return const <int>[];
    }
    return raw
        .whereType<num>()
        .map((value) => value.toInt())
        .where((value) => value >= 0)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  int? _percentile(int percentile) {
    if (_chunkUploadDurationsMs.isEmpty) {
      return null;
    }
    final sorted = List<int>.of(_chunkUploadDurationsMs)..sort();
    final rank = ((percentile / 100) * sorted.length).ceil() - 1;
    return sorted[rank.clamp(0, sorted.length - 1)];
  }

  Map<String, dynamic> _batchTelemetry({
    required int uploadDrainMs,
  }) => <String, dynamic>{
    'batchTransport': 'streamed_pcm16_chunks',
    'chunkIntervalMs': pcmChunkDurationMs * _sourceChunksPerTransportUpload,
    'sourceChunkIntervalMs': pcmChunkDurationMs,
    'audioChunkCount': _sourceChunkCount,
    'transportChunkCount': _transportChunkCount,
    'maxConcurrentChunkUploads': _maxConcurrentUploads,
    'uploadedAudioBytes': _audioByteCount,
    'retainedAudioBytes': _retainedAudioBytes,
    'recoveryBufferTruncated': _recoveryBufferTruncated,
    'chunkChecksumSha256': supportsChunkChecksum,
    'missingChunkRecovery': supportsMissingChunkRecovery,
    'uploadProtocolVersion': uploadProtocolVersion,
    'scopedUploadToken': uploadToken != null,
    'chunkRetryCount': _chunkRetryCount,
    'missingChunkCount': _missingChunkCount,
    'recoveryUploadCount': _recoveryUploadCount,
    'batchPrefetchAttemptCount': _speculativeAttemptCount,
    'batchPrefetchTransientRetryCount': _speculativeTransientRetryCount,
    'batchTerminalPrefetchAttemptCount': _terminalSpeculativeAttemptCount,
    'batchTerminalDuplicateSuppressed': _terminalDuplicateSuppressed,
    if (_terminalUploadWaitMs != null)
      'batchTerminalUploadWaitMs': _terminalUploadWaitMs,
    if (_terminalSnapshotAckedChunkCount != null)
      'batchTerminalSnapshotAckedChunkCount': _terminalSnapshotAckedChunkCount,
    'batchFinalSnapshotChunkCount': _transportChunkCount,
    if (_terminalPreviewStartedAfterVoiceInactiveMs != null)
      'batchTerminalPreviewStartedAfterSilenceMs':
          _terminalPreviewStartedAfterVoiceInactiveMs,
    if (_vadSilenceAtSessionMs != null)
      'batchVadSilenceAtSessionMs': _vadSilenceAtSessionMs,
    if (_terminalPreviewRequestedAtSessionMs != null)
      'batchTerminalRequestSentAtSessionMs':
          _terminalPreviewRequestedAtSessionMs,
    if (_terminalPipelineStartedAtSessionMs != null)
      'batchTerminalPipelineStartedAtSessionMs':
          _terminalPipelineStartedAtSessionMs,
    if (_finalizeRequestSentAtSessionMs != null)
      'batchFinalizeRequestSentAtSessionMs': _finalizeRequestSentAtSessionMs,
    if (_terminalPipelineStartedAtSessionMs != null &&
        _finalizeRequestSentAtSessionMs != null)
      'batchTerminalPreviewLeadBeforeFinalizeMs': math.max(
        0,
        _finalizeRequestSentAtSessionMs! - _terminalPipelineStartedAtSessionMs!,
      ),
    'batchPrefetchFinalizeWaitMs': 0,
    'batchPrefetchReady': _prefetchId != null,
    'workerAsrPilotAttempted': _workerAsrPilotAttempted,
    if (_workerAsrPilotFallbackCode != null)
      'workerAsrPilotFallbackCode': _workerAsrPilotFallbackCode,
    if (_workerAsrPilotFallbackMs != null)
      'workerAsrPilotFallbackMs': _workerAsrPilotFallbackMs,
    if (_firstChunkAckMs != null) 'firstChunkAckMs': _firstChunkAckMs,
    if (_percentile(50) != null) 'chunkUploadP50Ms': _percentile(50),
    if (_percentile(95) != null) 'chunkUploadP95Ms': _percentile(95),
    if (_lastFailedSequence != null) 'lastFailedSequence': _lastFailedSequence,
    if (_lastUploadErrorCode != null)
      'lastUploadErrorCode': _lastUploadErrorCode,
    'batchUploadSessionMs': _sessionStopwatch.elapsedMilliseconds,
    'retryStrategy': 'exponential_full_jitter_retry_after',
    'wavHeaderStrategy': supportsPcm16WavFinalize
        ? 'finalize_metadata'
        : 'uploaded_chunk',
    'sessionCreateMs': sessionCreateMs,
    'uploadDrainAfterStopMs': uploadDrainMs,
    ..._clientTerminalTelemetry,
  };

  Future<ConversationResult> _finalizeWithMissingRecovery({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    required int uploadDrainMs,
  }) async {
    for (
      var recoveryRound = 0;
      recoveryRound <= _maxMissingRecoveryRounds;
      recoveryRound += 1
    ) {
      try {
        _finalizeRequestSentAtSessionMs ??=
            _sessionStopwatch.elapsedMilliseconds;
        return await _repository._finalizeAudioSession(
          clientId: await _repository._clientId,
          audioSessionId: audioSessionId,
          uploadToken: uploadToken,
          capture: capture,
          context: context,
          childAge: childAge,
          vadSilenceMs: vadSilenceMs,
          assemblePcmWav: supportsPcm16WavFinalize,
          prefetchId: _prefetchId,
          batchTelemetry: <String, dynamic>{
            ..._batchTelemetry(uploadDrainMs: uploadDrainMs),
            if (capture.recordingSampleRate != null)
              'recordingSampleRate': capture.recordingSampleRate,
          },
        );
      } catch (error) {
        final missing = _missingSequences(error);
        if (missing.isEmpty || recoveryRound >= _maxMissingRecoveryRounds) {
          rethrow;
        }
        final chunks = <_RetainedTransportChunk>[];
        for (final sequence in missing) {
          final chunk = _retainedChunks[sequence];
          if (chunk == null) {
            rethrow;
          }
          chunks.add(chunk);
        }
        _missingChunkCount += missing.length;
        for (final chunk in chunks) {
          _scheduleUpload(chunk, recovery: true);
        }
        await _drainPendingUploads();
      }
    }
    throw const ConversationApiException(
      'Không thể khôi phục audio chunk bị thiếu.',
      errorCode: 'AUDIO_CHUNKS_MISSING',
    );
  }

  @override
  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    if (_closed || _finalizing) {
      throw const ConversationApiException(
        'Audio session đã được hoàn tất hoặc hủy.',
      );
    }
    _workerFinalizeStartedAtSessionMs ??= _sessionStopwatch.elapsedMilliseconds;
    _speculativePreviewTimer?.cancel();
    _speculativePreviewTimer = null;
    // Finalize immediately after the last PCM flush. Any terminal preview
    // already in flight stays alive and is coordinated by the backend; the
    // browser never waits locally for a speculative result.
    _finalizing = true;
    try {
      // Stop accepting recorder input, but keep the already-running preview
      // request and its stream alive until the finalize request completes.
      _flushTransportBuffer(schedulePreview: false);
      final streamedAudioBytes = capture.streamedAudioBytes;
      final recordingSampleRate = capture.recordingSampleRate;
      if (supportsPcm16WavFinalize &&
          (streamedAudioBytes == null ||
              streamedAudioBytes <= 0 ||
              recordingSampleRate == null ||
              recordingSampleRate <= 0)) {
        throw const ConversationApiException(
          'Không tìm thấy metadata PCM của Batch Chunks.',
        );
      }
      final streamHeaderBytes = capture.streamHeaderBytes;
      if (!supportsPcm16WavFinalize &&
          (streamHeaderBytes == null || streamHeaderBytes.isEmpty)) {
        throw const ConversationApiException(
          'Không tìm thấy WAV header của Batch Chunks.',
        );
      }

      if (!supportsPcm16WavFinalize) {
        _scheduleNewUpload(
          sequence: 0,
          bytes: streamHeaderBytes!,
          filename: 'header.wav',
        );
      }
      final uploadDrainStopwatch = Stopwatch()..start();
      final uploadDrain = _drainPendingUploads();
      final finalPcm = _retainedPcmForWorkerPilot();
      if (_usesWorkerPrepare && finalPcm != null) {
        try {
          final activePreparation = _workerPrepareFlight;
          if (_readyWorkerPreparation == null &&
              activePreparation != null &&
              _workerPrepareSpeechGeneration == _speechGeneration) {
            final workerStartedAt = _workerPrepareStartedAtSessionMs;
            final workerLeadMs = workerStartedAt == null
                ? 0
                : math.max(
                    0,
                    _workerFinalizeStartedAtSessionMs! - workerStartedAt,
                  );
            if (_workerTranscriptReadyAtSessionMs != null) {
              // Once ASR has completed, prepare is already doing the same
              // translation/TTS work that Worker-only would start. Join it to
              // avoid duplicate backend work.
              _workerPrepareJoinedAtFinalize = true;
              await activePreparation;
            } else {
              // Never block finalize on an unresolved speculative ASR merely
              // because it started early. Reuse that same ASR through the
              // established Worker-only path, and prevent the speculative
              // flight from adding prepare + commit after ASR completes.
              _workerPrepareSkippedLowLead =
                  workerLeadMs < _minimumPreparedWorkerLeadMs;
              _workerPrepareAbandonedAtFinalize = true;
              _workerPrepareAbandoned = true;
            }
          }
          if (_readyWorkerPreparation != null) {
            _workerPrepareJoinedAtFinalize = true;
          }
          final preparedResult = await _tryPreparedWorkerCommit(
            finalPcm: finalPcm,
            capture: capture,
            vadSilenceMs: vadSilenceMs,
          );
          if (preparedResult != null) {
            unawaited(_discardShadowSessionAfterWorkerSuccess(uploadDrain));
            return preparedResult;
          }
        } catch (error, stackTrace) {
          // A prepared commit is only a fast path. The already-established
          // Worker-only path remains authoritative without a fixed wait.
          developer.log(
            'Prepared Worker commit was unavailable; using Worker-only finalize.',
            name: 'conversation.worker_asr_prepare',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final workerPilot = _tryWorkerAsrPilot(
        capture: capture,
        context: context,
        childAge: childAge,
        vadSilenceMs: vadSilenceMs,
      );
      final workerResult = await workerPilot;
      if (workerResult != null) {
        unawaited(_discardShadowSessionAfterWorkerSuccess(uploadDrain));
        return workerResult;
      }
      await uploadDrain;
      uploadDrainStopwatch.stop();

      return await _finalizeWithMissingRecovery(
        capture: capture,
        context: context,
        childAge: childAge,
        vadSilenceMs: vadSilenceMs,
        uploadDrainMs: uploadDrainStopwatch.elapsedMilliseconds,
      );
    } finally {
      _closed = true;
      _finalizing = false;
      _retainedChunks.clear();
      _transportChunkByteLengths.clear();
      _ackedTransportSequences.clear();
      _retainedAudioBytes = 0;
      if (!_speculativePreviewController.isClosed) {
        await _speculativePreviewController.close();
      }
    }
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {
    if (_discarded) {
      return;
    }
    _discarded = true;
    _closed = true;
    _speculativePreviewTimer?.cancel();
    _speculativePreviewTimer = null;
    _transportBuffer.takeBytes();
    _retainedChunks.clear();
    _transportChunkByteLengths.clear();
    _ackedTransportSequences.clear();
    _retainedAudioBytes = 0;
    final uploads = List<Future<void>>.of(_pendingUploads);
    _pendingUploads.clear();
    unawaited(
      Future.wait<void>(
        uploads.map((upload) => upload.catchError((Object _) {})),
      ),
    );
    await _repository._discardAudioSession(
      audioSessionId,
      uploadToken: uploadToken,
      reason: reason,
    );
    if (!_speculativePreviewController.isClosed) {
      await _speculativePreviewController.close();
    }
  }
}

class _RetainedTransportChunk {
  _RetainedTransportChunk({
    required this.sequence,
    required Uint8List bytes,
    required this.filename,
  }) : bytes = Uint8List.fromList(bytes),
       sha256 = crypto.sha256.convert(bytes).toString();

  final int sequence;
  final Uint8List bytes;
  final String filename;
  final String sha256;
}

class ConversationApiException
    implements Exception, CodedConversationException {
  const ConversationApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.details,
    this.retryAfter,
  });

  @override
  final String message;
  final int? statusCode;
  @override
  final String? errorCode;
  final Map<String, dynamic>? details;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

bool _isRetryableConversationRequest(Object error) {
  if (error is TimeoutException || error is http.ClientException) {
    return true;
  }
  if (error is! ConversationApiException) {
    return false;
  }

  final statusCode = error.statusCode;
  return statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      (statusCode == 409 && error.errorCode == 'RATE_LIMITED') ||
      (statusCode != null && statusCode >= 500);
}

final math.Random _conversationRetryRandom = math.Random();

Duration _conversationRetryDelay({
  required Object? error,
  required int attempt,
  required int baseMs,
}) {
  if (error is ConversationApiException && error.retryAfter != null) {
    return error.retryAfter!;
  }
  final exponentialCap = math.min(2500, baseMs * (1 << (attempt - 1)));
  return Duration(
    milliseconds: _conversationRetryRandom.nextInt(exponentialCap + 1),
  );
}
