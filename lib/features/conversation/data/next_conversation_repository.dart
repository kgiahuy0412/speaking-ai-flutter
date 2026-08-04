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
            'limit': 200,
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
      clientVadApplied: true,
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
    Map<String, dynamic> batchTelemetry = const <String, dynamic>{},
  }) async {
    final benchmark = ConversationBenchmark(
      utteranceDurationMs: capture.duration.inMilliseconds,
      vadSilenceMs: vadSilenceMs,
      requestedAsrMode: AsrMode.batchChunks,
      audioInputLabel: capture.inputLabel,
      bluetoothAudioInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      clientVadApplied: true,
    );
    final uri = _config.resolve('/api/audio-sessions/$audioSessionId/finalize');
    final body = jsonEncode(<String, dynamic>{
      'clientId': clientId,
      'context': context.apiValue,
      'childAge': childAge,
      'asrMode': 'batch_chunks',
      'mimeType': capture.mimeType,
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
      uploadProtocolVersion: uploadProtocolVersion is num
          ? uploadProtocolVersion.toInt()
          : 1,
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
    required this.uploadProtocolVersion,
  });

  final String id;
  final bool supportsPcm16WavFinalize;
  final String? uploadToken;
  final bool supportsChunkChecksum;
  final bool supportsMissingChunkRecovery;
  final int uploadProtocolVersion;
}

class _NextBatchChunkUploadSession implements BatchChunkUploadSession {
  _NextBatchChunkUploadSession({
    required NextConversationRepository repository,
    required this.audioSessionId,
    required this.sessionCreateMs,
    required this.supportsPcm16WavFinalize,
    required this.uploadToken,
    required this.supportsChunkChecksum,
    required this.supportsMissingChunkRecovery,
    required this.uploadProtocolVersion,
  }) : _repository = repository,
       _uploadLanes = List<Future<void>>.generate(
         _maxConcurrentUploads,
         (_) => Future<void>.value(),
       ) {
    _sessionStopwatch.start();
  }

  static const _sourceChunksPerTransportUpload = 5;
  static const _maxConcurrentUploads = 2;
  static const _maxMissingRecoveryRounds = 2;
  static const _maxRetainedAudioBytes = 2 * 1024 * 1024;

  final NextConversationRepository _repository;
  final String audioSessionId;
  final int sessionCreateMs;
  final bool supportsPcm16WavFinalize;
  final String? uploadToken;
  final bool supportsChunkChecksum;
  final bool supportsMissingChunkRecovery;
  final int uploadProtocolVersion;
  final List<Future<void>> _pendingUploads = <Future<void>>[];
  final List<Future<void>> _uploadLanes;
  final BytesBuilder _transportBuffer = BytesBuilder(copy: false);
  final Map<int, _RetainedTransportChunk> _retainedChunks =
      <int, _RetainedTransportChunk>{};
  final List<int> _chunkUploadDurationsMs = <int>[];
  final Stopwatch _sessionStopwatch = Stopwatch();
  late var _nextSequence = supportsPcm16WavFinalize ? 0 : 1;
  var _nextUploadLane = 0;
  var _sourceChunkCount = 0;
  var _transportChunkCount = 0;
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
  var _discarded = false;

  @override
  void addAudioChunk(Uint8List bytes) {
    if (_closed || bytes.isEmpty) {
      return;
    }
    final immutableBytes = Uint8List.fromList(bytes);
    _audioByteCount += immutableBytes.length;
    _sourceChunkCount += 1;
    _transportBuffer.add(immutableBytes);
    if (_sourceChunkCount % _sourceChunksPerTransportUpload == 0) {
      _flushTransportBuffer();
    }
  }

  void _flushTransportBuffer() {
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

  Future<void> _drainPendingUploads() async {
    if (_pendingUploads.isEmpty) {
      return;
    }
    final pending = List<Future<void>>.of(_pendingUploads);
    _pendingUploads.clear();
    await Future.wait<void>(pending);
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
        return await _repository._finalizeAudioSession(
          clientId: await _repository._clientId,
          audioSessionId: audioSessionId,
          uploadToken: uploadToken,
          capture: capture,
          context: context,
          childAge: childAge,
          vadSilenceMs: vadSilenceMs,
          assemblePcmWav: supportsPcm16WavFinalize,
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
    if (_closed) {
      throw const ConversationApiException(
        'Audio session đã được hoàn tất hoặc hủy.',
      );
    }
    _closed = true;
    _flushTransportBuffer();
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
    await _drainPendingUploads();
    uploadDrainStopwatch.stop();

    final result = await _finalizeWithMissingRecovery(
      capture: capture,
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
      uploadDrainMs: uploadDrainStopwatch.elapsedMilliseconds,
    );
    _retainedChunks.clear();
    _retainedAudioBytes = 0;
    return result;
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) async {
    if (_discarded) {
      return;
    }
    _discarded = true;
    _closed = true;
    _transportBuffer.takeBytes();
    _retainedChunks.clear();
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
