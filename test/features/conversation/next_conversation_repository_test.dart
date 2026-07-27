import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/next_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<String> clientIdProvider() async => 'android_test_device';

  final config = AppConfig(
    backendBaseUri: Uri.parse('https://api.example.com'),
    useDemoBackend: false,
    childAge: 6,
  );

  test('requests a non-blocking all-context warm-up on app startup', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://api.example.com/api/cache/warmup'),
      );
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), <String, dynamic>{
        'clientId': 'android_test_device',
        'context': 'all',
        'background': true,
      });

      return http.Response(
        jsonEncode(<String, dynamic>{'accepted': true, 'context': 'all'}),
        202,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: client,
    );

    await repository.warmAudioCache();
    await repository.dispose();
  });

  test('previews a fast rule without creating a conversation', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/conversation/preview');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['clientId'], 'android_test_device');
        expect(body['sourceText'], 'Con muốn uống nước');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'matched': true,
            'sourceText': body['sourceText'],
            'englishText': 'Can I have some water, please?',
            'textSource': 'phrase_rule',
            'audioUrl': '/generated-audio/water.mp3',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final preview = await repository.previewStreamingText(
      sourceText: 'Con muốn uống nước',
      context: PracticeContext.home,
      childAge: 6,
    );

    expect(preview?.textSource, 'phrase_rule');
    expect(
      preview?.audioUri,
      Uri.parse('https://api.example.com/generated-audio/water.mp3'),
    );
    await repository.dispose();
  });

  test(
    'sends one final Realtime transcript through the existing pipeline',
    () async {
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/conversation');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final benchmark = body['benchmark'] as Map<String, dynamic>;
          expect(body['sourceText'], 'Con muốn đi công viên');
          expect(body['asrMode'], 'openai_realtime');
          expect(benchmark['requestedAsrMode'], 'openai_realtime');
          expect(benchmark['asrFirstDeltaMs'], 510);
          expect(benchmark['asrFinalAfterStopMs'], 140);
          expect(benchmark['realtimeSessionCreateMs'], 120);
          expect(benchmark['realtimeWebSocketConnectMs'], 80);
          expect(benchmark['realtimeWebSocketOpenAfterRecordingMs'], 200);
          expect(benchmark['realtimeChunkDurationMs'], 200);

          return http.Response(
            jsonEncode(<String, dynamic>{
              'conversationId': 'conv_realtime',
              'sessionId': 'sess_realtime',
              'context': 'outside',
              'vietnameseText': 'Con muốn đi công viên',
              'englishText': 'I want to go to the park.',
              'audioUrl': '/generated-audio/park.mp3',
              'processingMode': 'rule',
              'textSource': 'phrase_rule',
              'audioSource': 'cache',
              'asrMode': 'openai_realtime',
              'latency': <String, dynamic>{
                'asrMs': 0,
                'llmMs': 1,
                'ttsMs': 1,
                'timeToFirstAudioMs': 240,
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final result = await repository.processStreamingText(
        capture: const StreamingSpeechCapture(
          sourceText: 'Con muốn đi công viên',
          duration: Duration(milliseconds: 1800),
          inputLabel: 'Mic điện thoại',
          confidence: null,
          firstResultMs: 510,
          finalAfterStopMs: 140,
          asrMode: 'openai_realtime',
          realtimeSessionCreateMs: 120,
          realtimeWebSocketConnectMs: 80,
          realtimeWebSocketOpenAfterRecordingMs: 200,
          realtimeChunkDurationMs: 200,
        ),
        context: PracticeContext.outside,
        childAge: 6,
        vadSilenceMs: 700,
      );

      expect(result.asrMode, 'openai_realtime');
      await repository.dispose();
    },
  );

  test('batches PCM transport chunks and finalizes one WAV', () async {
    final uploadedSequences = <int>[];
    var finalized = false;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        if (request.url.path == '/api/audio-sessions') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'audioSessionId': 'audio_test',
              'capabilities': <String, dynamic>{'pcm16WavFinalize': true},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chunks')) {
          final body = latin1.decode(request.bodyBytes);
          final match = RegExp(
            r'name="sequence"\r\n\r\n(\d+)',
          ).firstMatch(body);
          expect(match, isNotNull);
          uploadedSequences.add(int.parse(match!.group(1)!));
          return http.Response(
            jsonEncode(<String, dynamic>{'uploaded': true}),
            200,
          );
        }
        if (request.url.path.endsWith('/finalize')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final benchmark = body['benchmark'] as Map<String, dynamic>;
          expect(body['mimeType'], 'audio/wav');
          expect(benchmark['batchTransport'], 'streamed_pcm16_chunks');
          expect(benchmark['audioChunkCount'], 2);
          expect(benchmark['transportChunkCount'], 1);
          expect(benchmark['chunkIntervalMs'], 1000);
          expect(benchmark['sourceChunkIntervalMs'], 200);
          expect(benchmark['maxConcurrentChunkUploads'], 2);
          expect(benchmark['uploadedAudioBytes'], 16000);
          expect(benchmark['wavHeaderStrategy'], 'finalize_metadata');
          expect(body['pcm16Wav'], <String, dynamic>{
            'sampleRate': 48000,
            'channelCount': 1,
            'bitsPerSample': 16,
            'pcmByteLength': 16000,
          });
          finalized = true;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'conversationId': 'conv_batch',
              'sessionId': 'sess_batch',
              'context': 'home',
              'vietnameseText': 'Con muốn uống nước',
              'englishText': 'Can I have some water, please?',
              'audioUrl': '/generated-audio/water.mp3',
              'processingMode': 'rule',
              'textSource': 'phrase_rule',
              'audioSource': 'cache',
              'asrMode': 'batch_chunks',
              'latency': <String, dynamic>{
                'asrMs': 500,
                'llmMs': 0,
                'ttsMs': 1,
                'timeToFirstAudioMs': 520,
              },
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final upload = await repository.startBatchChunkUpload();
    upload.addAudioChunk(Uint8List(8000));
    upload.addAudioChunk(Uint8List(8000));
    final header = buildPcm16WavHeader(pcmByteLength: 16000);
    final result = await upload.finalize(
      capture: AudioCapture(
        filePath: 'fallback.wav',
        mimeType: 'audio/wav',
        duration: const Duration(milliseconds: 500),
        inputLabel: 'Mic điện thoại',
        isBluetoothInput: false,
        initialNoiseRms: null,
        streamHeaderBytes: header,
        streamedAudioBytes: 16000,
        recordingSampleRate: 48000,
      ),
      context: PracticeContext.home,
      childAge: 6,
      vadSilenceMs: 700,
    );

    expect(uploadedSequences, <int>[0]);
    expect(finalized, isTrue);
    expect(result.asrMode, 'batch_chunks');
    await repository.dispose();
  });

  test(
    'keeps legacy header upload when backend lacks the capability',
    () async {
      final uploadedSequences = <int>[];
      Map<String, dynamic>? finalizeBody;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{'audioSessionId': 'audio_legacy'}),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            final body = latin1.decode(request.bodyBytes);
            final match = RegExp(
              r'name="sequence"\r\n\r\n(\d+)',
            ).firstMatch(body);
            uploadedSequences.add(int.parse(match!.group(1)!));
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_legacy',
                'sessionId': 'sess_legacy',
                'context': 'home',
                'vietnameseText': 'Con muốn uống nước',
                'englishText': 'I want to drink water.',
                'audioUrl': '/generated-audio/water.mp3',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 1,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 1,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      upload.addAudioChunk(Uint8List(8000));
      await upload.finalize(
        capture: AudioCapture(
          filePath: 'fallback.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 500),
          inputLabel: 'Mic điện thoại',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 8000),
          streamedAudioBytes: 8000,
          recordingSampleRate: 24000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      expect(uploadedSequences..sort(), <int>[0, 1]);
      expect(finalizeBody!.containsKey('pcm16Wav'), isFalse);
      expect(
        (finalizeBody!['benchmark']
            as Map<String, dynamic>)['wavHeaderStrategy'],
        'uploaded_chunk',
      );
      await repository.dispose();
    },
  );

  test('retries finalize with a stable idempotency key', () async {
    var finalizeAttempts = 0;
    final idempotencyKeys = <String>[];
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        if (request.url.path == '/api/audio-sessions') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'audioSessionId': 'audio_retry',
              'capabilities': <String, dynamic>{'pcm16WavFinalize': true},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chunks')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'uploaded': true}),
            200,
          );
        }
        if (request.url.path.endsWith('/finalize')) {
          finalizeAttempts += 1;
          idempotencyKeys.add(request.headers['idempotency-key'] ?? '');
          if (finalizeAttempts == 1) {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error': <String, dynamic>{
                  'code': 'TEMPORARY',
                  'message': 'Backend đang bận.',
                },
              }),
              503,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'conversationId': 'conv_retry',
              'sessionId': 'sess_retry',
              'context': 'home',
              'vietnameseText': 'Con muốn uống nước',
              'englishText': 'Can I have some water, please?',
              'audioUrl': '/generated-audio/water.mp3',
              'processingMode': 'rule',
              'textSource': 'phrase_rule',
              'audioSource': 'cache',
              'asrMode': 'batch_chunks',
              'latency': <String, dynamic>{
                'asrMs': 500,
                'llmMs': 0,
                'ttsMs': 1,
                'timeToFirstAudioMs': 520,
              },
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final upload = await repository.startBatchChunkUpload();
    upload.addAudioChunk(Uint8List(8000));
    await upload.finalize(
      capture: AudioCapture(
        filePath: 'fallback.wav',
        mimeType: 'audio/wav',
        duration: const Duration(milliseconds: 500),
        inputLabel: 'Mic điện thoại',
        isBluetoothInput: false,
        initialNoiseRms: null,
        streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 8000),
        streamedAudioBytes: 8000,
        recordingSampleRate: 24000,
      ),
      context: PracticeContext.home,
      childAge: 6,
      vadSilenceMs: 700,
    );

    expect(finalizeAttempts, 2);
    expect(idempotencyKeys, <String>[
      'finalize:audio_retry',
      'finalize:audio_retry',
    ]);
    await repository.dispose();
  });

  test('discards an unfinished chunk session', () async {
    var discarded = false;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        if (request.url.path == '/api/audio-sessions') {
          return http.Response(
            jsonEncode(<String, dynamic>{'audioSessionId': 'audio_cancel'}),
            200,
          );
        }
        if (request.method == 'DELETE' &&
            request.url.path.endsWith('/chunks')) {
          discarded = true;
          return http.Response(
            jsonEncode(<String, dynamic>{'discarded': true}),
            200,
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final BatchChunkUploadSession upload = await repository
        .startBatchChunkUpload();
    await upload.discard();

    expect(discarded, isTrue);
    await repository.dispose();
  });

  test('reports actual audio load time and device cache usage', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final latency = body['latency'] as Map<String, dynamic>;
        expect(latency['audioLoadMs'], 42);
        expect(latency['audioFromDeviceCache'], isTrue);
        expect(latency.containsKey('ttsFirstByteMs'), isFalse);
        return http.Response(
          jsonEncode(<String, dynamic>{'conversation': <String, dynamic>{}}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await repository.patchPlaybackLatency(
      conversationId: 'conv_telemetry',
      timeToFirstAudioMs: 650,
      audioLoadMs: 42,
      audioFromDeviceCache: true,
    );
    await repository.dispose();
  });

  test('retries playback telemetry without blocking playback', () async {
    var attempts = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        attempts += 1;
        if (attempts == 1) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'code': 'TEMPORARY',
                'message': 'Thử lại.',
              },
            }),
            503,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'conversation': <String, dynamic>{}}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await repository.patchPlaybackLatency(
      conversationId: 'conv_telemetry_retry',
      timeToFirstAudioMs: 700,
      audioLoadMs: 50,
      audioFromDeviceCache: false,
    );

    expect(attempts, 2);
    await repository.dispose();
  });

  test('reports a friendly error when backend returns invalid JSON', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient(
        (_) async => http.Response('<html>proxy error</html>', 200),
      ),
    );

    expect(
      repository.fetchHistory,
      throwsA(
        isA<ConversationApiException>().having(
          (error) => error.message,
          'message',
          'Backend trả về dữ liệu không hợp lệ.',
        ),
      ),
    );
    await repository.dispose();
  });

  test('includes backend request id in API errors for support', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{
              'code': 'BAD_REQUEST',
              'message': 'Dữ liệu không hợp lệ.',
            },
          }),
          400,
          headers: const <String, String>{
            'content-type': 'application/json',
            'x-request-id': 'request-test-1234',
          },
        ),
      ),
    );

    expect(
      repository.fetchHistory,
      throwsA(
        isA<ConversationApiException>().having(
          (error) => error.message,
          'message',
          contains('Mã hỗ trợ: request-test-1234'),
        ),
      ),
    );
    await repository.dispose();
  });

  test('loads rich history and requests the latest 100 items', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/history');
        expect(request.url.queryParameters['limit'], '100');
        expect(request.url.queryParameters['clientId'], 'android_test_device');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'conversations': <Map<String, dynamic>>[
              <String, dynamic>{
                'conversationId': 'conv_1',
                'context': 'home',
                'vietnameseText': 'Con muốn uống nước.',
                'englishText': 'Can I have some water?',
                'audioUrl': '/generated-audio/water.mp3',
                'createdAt': '2026-07-20T13:35:21.399Z',
                'qualityApproved': false,
                'promotedToRule': false,
                'learningStatus': 'observing',
                'learningUseCount': 2,
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'batch_chunks',
                'inputMode': 'audio',
                'latency': <String, dynamic>{
                  'asrMs': 800,
                  'llmMs': 0,
                  'ttsMs': 1,
                  'timeToFirstAudioMs': 1400,
                },
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final items = await repository.fetchHistory();

    expect(items, hasLength(1));
    expect(items.single.reviewStatus, HistoryReviewStatus.rejected);
    expect(
      items.single.audioUri,
      Uri.parse('https://api.example.com/generated-audio/water.mp3'),
    );
    expect(items.single.latency.timeToFirstAudioMs, 1400);
    expect(items.single.learningStatus, 'observing');
    expect(items.single.learningUseCount, 2);
    await repository.dispose();
  });

  test('deletes one history item with its conversation id', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/history');
        expect(request.url.queryParameters['conversationId'], 'conv_delete');
        expect(request.url.queryParameters['clientId'], 'android_test_device');
        return http.Response(
          jsonEncode(<String, dynamic>{'deleted': true}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await repository.deleteHistoryItem('conv_delete');
    await repository.dispose();
  });

  test('returns the automatic learning result after a review', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['clientId'], 'android_test_device');
        expect(body['conversationId'], 'conv_review');
        expect(body['qualityApproved'], true);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'conversation': <String, dynamic>{},
            'learning': <String, dynamic>{
              'status': 'promoted',
              'promoted': true,
              'useCount': 3,
              'threshold': 3,
              'message': 'Đã tối ưu câu này.',
            },
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final learning = await repository.review(
      conversationId: 'conv_review',
      approved: true,
    );

    expect(learning.status, 'promoted');
    expect(learning.promoted, isTrue);
    expect(learning.message, 'Đã tối ưu câu này.');
    await repository.dispose();
  });
}
