import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

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
  }) async {
    final clientId = await _clientId;
    final audioSession = await _createAudioSession();
    final audioSessionId = audioSession.id;
    await _uploadAudio(audioSessionId: audioSessionId, capture: capture);

    return _finalizeAudioSession(
      clientId: clientId,
      audioSessionId: audioSessionId,
      capture: capture,
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
    );
  }

  Future<ConversationResult> _finalizeAudioSession({
    required String clientId,
    required String audioSessionId,
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
              },
              body: body,
            )
            .timeout(const Duration(seconds: 35));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return ConversationResult.fromJson(
            _decodeResponse(response),
            backendBaseUri: _config.backendBaseUri,
          );
        }

        if (response.statusCode != 409 && response.statusCode < 500) {
          _decodeResponse(response);
        }

        lastError = ConversationApiException(
          'Finalize tạm thời chưa hoàn tất (${response.statusCode}).',
        );
      } catch (error) {
        lastError = error;
      }

      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
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
    );
  }

  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription({
    required String audioInputLabel,
    required bool bluetoothAudioInput,
  }) async {
    final sessionStartedAt = DateTime.now();
    final sessionStopwatch = Stopwatch()..start();
    final clientId = await _clientId;
    final response = await _client
        .post(
          _config.resolve('/api/realtime/transcription-session'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'clientId': clientId,
            'bluetoothAudioInput': bluetoothAudioInput,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final json = _decodeResponse(response);
    final clientSecret = json['clientSecret'];
    final websocketUrl = json['websocketUrl'];
    final sampleRate = json['sampleRate'];

    if (clientSecret is! String ||
        clientSecret.isEmpty ||
        websocketUrl is! String ||
        websocketUrl.isEmpty ||
        sampleRate != 24000) {
      throw const ConversationApiException(
        'Backend không trả về cấu hình OpenAI Realtime hợp lệ.',
      );
    }

    sessionStopwatch.stop();
    final websocketStopwatch = Stopwatch()..start();
    final socket = await connectRealtimeSocket(
      websocketUrl,
      headers: <String, String>{'authorization': 'Bearer $clientSecret'},
    ).timeout(const Duration(seconds: 12));
    websocketStopwatch.stop();

    return _OpenAiRealtimeTranscriptionSession(
      socket: socket,
      audioInputLabel: audioInputLabel,
      bluetoothAudioInput: bluetoothAudioInput,
      sessionStartedAt: sessionStartedAt,
      connectedAt: DateTime.now(),
      sessionCreateMs: sessionStopwatch.elapsedMilliseconds,
      websocketConnectMs: websocketStopwatch.elapsedMilliseconds,
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

  Future<_AudioSessionDescriptor> _createAudioSession() async {
    final response = await _client
        .post(_config.resolve('/api/audio-sessions'))
        .timeout(const Duration(seconds: 10));
    final json = _decodeResponse(response);
    final audioSessionId = json['audioSessionId'];

    if (audioSessionId is! String || audioSessionId.isEmpty) {
      throw const ConversationApiException(
        'Backend không trả về audioSessionId.',
      );
    }
    final capabilities = json['capabilities'];
    return _AudioSessionDescriptor(
      id: audioSessionId,
      supportsPcm16WavFinalize:
          capabilities is Map<String, dynamic> &&
          capabilities['pcm16WavFinalize'] == true,
    );
  }

  Future<void> _uploadAudio({
    required String audioSessionId,
    required AudioCapture capture,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _config.resolve('/api/audio-sessions/$audioSessionId/chunks'),
          )
          ..fields['sequence'] = '0'
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
    _decodeResponse(response);
  }

  Future<void> _uploadAudioBytes({
    required String audioSessionId,
    required int sequence,
    required Uint8List bytes,
    required String filename,
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
    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamedResponse);
    _decodeResponse(response);
  }

  Future<void> _discardAudioSession(String audioSessionId) async {
    final response = await _client
        .delete(_config.resolve('/api/audio-sessions/$audioSessionId/chunks'))
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
      final requestId = response.headers['x-request-id']?.trim();
      final supportCode = requestId == null || requestId.isEmpty
          ? ''
          : ' Mã hỗ trợ: $requestId.';
      throw ConversationApiException(
        '${message ?? 'Backend trả về lỗi ${response.statusCode}.'}$supportCode',
      );
    }

    if (decodeError != null) {
      throw const ConversationApiException(
        'Backend trả về dữ liệu không hợp lệ.',
      );
    }

    return json;
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

class _OpenAiRealtimeTranscriptionSession
    implements RealtimeTranscriptionSession {
  _OpenAiRealtimeTranscriptionSession({
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
          message ?? 'OpenAI Realtime không thể nhận diện âm thanh.',
        ),
      );
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (!_completed.isCompleted) {
      _completed.completeError(
        ConversationApiException('Kết nối OpenAI Realtime bị lỗi: $error'),
        stackTrace,
      );
    }
  }

  void _handleDone() {
    if (!_closed && !_completed.isCompleted) {
      _completed.completeError(
        const ConversationApiException(
          'Kết nối OpenAI Realtime đã đóng trước khi có kết quả.',
        ),
      );
    }
  }

  @override
  Future<StreamingSpeechCapture> finalize() async {
    if (_closed) {
      throw const ConversationApiException(
        'Lượt OpenAI Realtime đã được hoàn tất hoặc hủy.',
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
  });

  final String id;
  final bool supportsPcm16WavFinalize;
}

class _NextBatchChunkUploadSession implements BatchChunkUploadSession {
  _NextBatchChunkUploadSession({
    required NextConversationRepository repository,
    required this.audioSessionId,
    required this.sessionCreateMs,
    required this.supportsPcm16WavFinalize,
  }) : _repository = repository,
       _uploadLanes = List<Future<void>>.generate(
         _maxConcurrentUploads,
         (_) => Future<void>.value(),
       );

  static const _sourceChunksPerTransportUpload = 5;
  static const _maxConcurrentUploads = 2;

  final NextConversationRepository _repository;
  final String audioSessionId;
  final int sessionCreateMs;
  final bool supportsPcm16WavFinalize;
  final List<Future<void>> _pendingUploads = <Future<void>>[];
  final List<Future<void>> _uploadLanes;
  final BytesBuilder _transportBuffer = BytesBuilder(copy: false);
  late var _nextSequence = supportsPcm16WavFinalize ? 0 : 1;
  var _nextUploadLane = 0;
  var _sourceChunkCount = 0;
  var _transportChunkCount = 0;
  var _audioByteCount = 0;
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
    _scheduleUpload(
      sequence: sequence,
      bytes: bytes,
      filename: 'chunk-$sequence.pcm',
    );
  }

  void _scheduleUpload({
    required int sequence,
    required Uint8List bytes,
    required String filename,
  }) {
    final laneIndex = _nextUploadLane;
    _nextUploadLane = (_nextUploadLane + 1) % _uploadLanes.length;
    final previousLane = _uploadLanes[laneIndex].then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final upload = previousLane.then<void>(
      (_) => _uploadWithRetry(
        sequence: sequence,
        bytes: bytes,
        filename: filename,
      ),
    );
    _uploadLanes[laneIndex] = upload;
    _pendingUploads.add(upload);
    unawaited(upload.catchError((Object _) {}));
  }

  Future<void> _uploadWithRetry({
    required int sequence,
    required Uint8List bytes,
    required String filename,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        await _repository._uploadAudioBytes(
          audioSessionId: audioSessionId,
          sequence: sequence,
          bytes: bytes,
          filename: filename,
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
        }
      }
    }
    throw ConversationApiException(
      'Không upload được audio chunk $sequence: $lastError',
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
      _scheduleUpload(
        sequence: 0,
        bytes: streamHeaderBytes!,
        filename: 'header.wav',
      );
    }
    final uploadDrainStopwatch = Stopwatch()..start();
    await Future.wait<void>(_pendingUploads);
    uploadDrainStopwatch.stop();

    return _repository._finalizeAudioSession(
      clientId: await _repository._clientId,
      audioSessionId: audioSessionId,
      capture: capture,
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
      assemblePcmWav: supportsPcm16WavFinalize,
      batchTelemetry: <String, dynamic>{
        'batchTransport': 'streamed_pcm16_chunks',
        'chunkIntervalMs': pcmChunkDurationMs * _sourceChunksPerTransportUpload,
        'sourceChunkIntervalMs': pcmChunkDurationMs,
        'audioChunkCount': _sourceChunkCount,
        'transportChunkCount': _transportChunkCount,
        'maxConcurrentChunkUploads': _maxConcurrentUploads,
        'uploadedAudioBytes': _audioByteCount,
        if (capture.recordingSampleRate != null)
          'recordingSampleRate': capture.recordingSampleRate,
        'wavHeaderStrategy': supportsPcm16WavFinalize
            ? 'finalize_metadata'
            : 'uploaded_chunk',
        'sessionCreateMs': sessionCreateMs,
        'uploadDrainAfterStopMs': uploadDrainStopwatch.elapsedMilliseconds,
      },
    );
  }

  @override
  Future<void> discard() async {
    if (_discarded) {
      return;
    }
    _discarded = true;
    _closed = true;
    await Future.wait<void>(
      _pendingUploads.map((upload) => upload.catchError((Object _) {})),
    );
    await _repository._discardAudioSession(audioSessionId);
  }
}

class ConversationApiException implements Exception {
  const ConversationApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
