import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/pcm_speech_preprocessor.dart';
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
  final workerPrepareConfig = AppConfig(
    backendBaseUri: Uri.parse('https://api.example.com'),
    useDemoBackend: false,
    childAge: 6,
    enableWorkerAsrPilot: true,
    enableWorkerAsrPrepare: true,
    workerAsrPilotBaseUri: Uri.parse('https://worker.example'),
  );

  test(
    'does not create a persistent client id until backend work starts',
    () async {
      var providerCalls = 0;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: () async {
          providerCalls += 1;
          return 'android_test_device';
        },
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{'conversations': <dynamic>[]}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      expect(providerCalls, 0);
      await repository.fetchHistory();
      expect(providerCalls, 1);
      await repository.dispose();
    },
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
        'limit': 1500,
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

  test('rejects legacy Realtime locally without an HTTP request', () async {
    var requestCount = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      repository.startRealtimeTranscription(
        audioInputLabel: 'Mic điện thoại',
        bluetoothAudioInput: false,
      ),
      throwsA(
        isA<ConversationApiException>().having(
          (error) => error.message,
          'message',
          contains('Cloudflare Batch Chunks'),
        ),
      ),
    );
    expect(requestCount, 0);
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

  test('uploads a short recorded utterance directly in one request', () async {
    var requestCount = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/conversation');
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('name="clientId"'));
        expect(body, contains('android_test_device'));
        expect(body, contains('name="audio"; filename="utterance.wav"'));
        expect(body, contains('direct_multipart'));
        expect(body, contains('"clientVadApplied":false'));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'conversationId': 'conv_direct',
            'sessionId': 'sess_direct',
            'context': 'home',
            'vietnameseText': 'Con muốn uống nước.',
            'englishText': 'I want to drink water.',
            'audioUrl': '/api/audio/stream?text=water',
            'processingMode': 'ai',
            'textSource': 'cloudflare',
            'audioSource': 'cloudflare_tts',
            'asrMode': 'batch_chunks',
            'latency': <String, dynamic>{
              'asrMs': 500,
              'llmMs': 300,
              'ttsMs': 10,
              'timeToFirstAudioMs': 810,
            },
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await repository.processAudio(
      capture: AudioCapture(
        filePath: 'utterance.wav',
        mimeType: 'audio/wav',
        duration: const Duration(seconds: 2),
        inputLabel: 'Mic điện thoại',
        isBluetoothInput: false,
        initialNoiseRms: null,
        dataBytes: Uint8List.fromList(<int>[82, 73, 70, 70]),
      ),
      context: PracticeContext.home,
      childAge: 6,
      vadSilenceMs: 700,
    );

    expect(requestCount, 1);
    expect(result.conversationId, 'conv_direct');
    await repository.dispose();
  });

  test('archives streaming audio with conversation identity', () async {
    var requestCount = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/conversations/conv_streaming_audio/user-audio',
        );
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('name="clientId"'));
        expect(body, contains('android_test_device'));
        expect(body, contains('name="sessionId"'));
        expect(body, contains('sess_streaming_audio'));
        expect(body, contains('name="mimeType"'));
        expect(body, contains('audio/wav'));
        expect(body, contains('name="audio"; filename="utterance.wav"'));
        return http.Response(
          jsonEncode(<String, dynamic>{'saved': true}),
          201,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await repository.archiveUserAudio(
      result: ConversationResult(
        conversationId: 'conv_streaming_audio',
        sessionId: 'sess_streaming_audio',
        context: PracticeContext.home,
        vietnameseText: 'Con muốn uống nước',
        englishText: 'I want some water.',
        audioUri: null,
        processingMode: 'rule',
        textSource: 'phrase_rule',
        audioSource: 'cache',
        asrMode: 'android_streaming',
        latency: const ConversationLatency(
          asrMs: 10,
          llmMs: 1,
          ttsMs: 1,
          timeToFirstAudioMs: 12,
        ),
      ),
      capture: AudioCapture(
        filePath: 'streaming.wav',
        mimeType: 'audio/wav',
        duration: const Duration(seconds: 2),
        inputLabel: 'Mic điện thoại',
        isBluetoothInput: false,
        initialNoiseRms: null,
        dataBytes: Uint8List.fromList(<int>[82, 73, 70, 70, 1, 2, 3, 4]),
      ),
    );

    expect(requestCount, 1);
    await repository.dispose();
  });

  test(
    'defaults to PCM metadata finalize when create capabilities are omitted',
    () async {
      final uploadedSequences = <int>[];
      var finalized = false;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{'audioSessionId': 'audio_test'}),
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
            expect(benchmark['clientVadApplied'], isTrue);
            expect(benchmark['batchTransport'], 'streamed_pcm16_chunks');
            expect(benchmark['audioChunkCount'], 2);
            expect(benchmark['transportChunkCount'], 1);
            expect(benchmark['chunkIntervalMs'], 800);
            expect(benchmark['sourceChunkIntervalMs'], 200);
            expect(benchmark['maxConcurrentChunkUploads'], 2);
            expect(benchmark['uploadedAudioBytes'], 16000);
            expect(benchmark['wavHeaderStrategy'], 'finalize_metadata');
            expect(benchmark['platformNoiseSuppressionRequested'], isTrue);
            expect(benchmark['platformNoiseSuppressionApplied'], isTrue);
            expect(benchmark['pcmHighPassApplied'], isTrue);
            expect(benchmark['pcmAdaptiveNoiseGateApplied'], isTrue);
            expect(benchmark['estimatedSnrDb'], 14.5);
            expect(body['pcm16Wav'], <String, dynamic>{
              'sampleRate': 48000,
              'channelCount': 1,
              'bitsPerSample': 16,
              'pcmByteLength': 16000,
              'chunkCount': 1,
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
          audioProcessing: const AudioProcessingMetrics(
            platformNoiseSuppressionRequested: true,
            platformEchoCancellationRequested: true,
            platformAutoGainRequested: true,
            platformNoiseSuppressionApplied: true,
            pcmHighPassApplied: true,
            pcmAdaptiveNoiseGateApplied: true,
            estimatedSnrDb: 14.5,
          ),
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      expect(uploadedSequences, <int>[0]);
      expect(finalized, isTrue);
      expect(result.asrMode, 'batch_chunks');
      await repository.dispose();
    },
  );

  test(
    'uses 600 ms speculative Web chunks and forwards prefetchId on finalize',
    () async {
      final uploadedSequences = <int>[];
      Map<String, dynamic>? previewBody;
      Map<String, dynamic>? finalizeBody;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_prefetch',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
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
          if (request.url.path.endsWith('/preview')) {
            previewBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_1',
                'stabilityCount': 1,
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'phrase_rule',
                'audioUrl': '/api/audio/stream?text=water',
                'audioSource': 'cloudflare_tts',
                'snapshotChunkCount': 2,
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_prefetch',
                'sessionId': 'sess_prefetch',
                'context': 'home',
                'vietnameseText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/api/audio/stream?text=water',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cloudflare_tts',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 0,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 25,
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
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      final previewFuture = speculative.speculativePreviews.first;
      for (var index = 0; index < 6; index += 1) {
        upload.addAudioChunk(Uint8List(8000));
      }

      final preview = await previewFuture.timeout(const Duration(seconds: 2));
      expect(preview.englishText, 'Can I have some water, please?');
      expect(previewBody?['pcm16Wav'], <String, dynamic>{
        'sampleRate': 16000,
        'channelCount': 1,
        'bitsPerSample': 16,
        'pcmByteLength': 48000,
        'chunkCount': 2,
      });

      await upload.finalize(
        capture: AudioCapture(
          filePath: 'prefetch.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 1500),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 48000),
          streamedAudioBytes: 48000,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      expect(uploadedSequences, <int>[0, 1]);
      expect(finalizeBody?['prefetchId'], 'prefetch_1');
      final benchmark = finalizeBody?['benchmark'] as Map<String, dynamic>;
      expect(benchmark['chunkIntervalMs'], 600);
      await repository.dispose();
    },
  );

  test(
    'joins an unresolved Worker preparation without starting a duplicate pipeline',
    () async {
      var workerCalls = 0;
      var prepareCalls = 0;
      var commitCalls = 0;
      var conversationCalls = 0;
      var batchFinalizeCalled = false;
      Map<String, dynamic>? commitBody;
      http.Request? workerRequest;
      final shadowDiscarded = Completer<void>();
      final workerRequestStarted = Completer<void>();
      final releaseWorkerResponse = Completer<void>();
      final previewDeliveredBeforeCommit = Completer<void>();
      String? snapshotHash;
      final repository = NextConversationRepository(
        config: workerPrepareConfig,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_v2-worker-success',
                'uploadToken': 'scoped.payload.signature',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'chunkChecksumSha256': true,
                  'scopedUploadToken': true,
                  'uploadProtocolVersion': 2,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.host == 'worker.example') {
            workerCalls += 1;
            workerRequest = request;
            if (!workerRequestStarted.isCompleted) {
              workerRequestStarted.complete();
            }
            await releaseWorkerResponse.future;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'transcript': 'Con muốn uống nước',
                'timing': <String, dynamic>{'asrMs': 430, 'totalMs': 470},
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path.endsWith('/chunks') &&
              request.method == 'POST') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/conversation/prepare') {
            prepareCalls += 1;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            snapshotHash = body['snapshotHash'] as String;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'prepareId': 'prep_1234567890abcdef1234567890abcdef',
                'snapshotHash': snapshotHash,
                'result': <String, dynamic>{
                  'conversationId': 'conv_worker_prepared',
                  'sessionId': 'audio_v2-worker-success',
                  'context': 'home',
                  'vietnameseText': 'Con muốn uống nước',
                  'englishText': 'Can I have some water, please?',
                  'audioUrl': '/generated-audio/water.mp3',
                  'processingMode': 'rule',
                  'textSource': 'phrase_rule',
                  'audioSource': 'cache',
                  'asrMode': 'browser_streaming',
                  'latency': <String, dynamic>{
                    'asrMs': 430,
                    'llmMs': 0,
                    'ttsMs': 0,
                    'timeToFirstAudioMs': 500,
                  },
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path == '/api/conversation/prepare/commit') {
            commitCalls += 1;
            expect(previewDeliveredBeforeCommit.isCompleted, isTrue);
            commitBody = jsonDecode(request.body) as Map<String, dynamic>;
            expect(commitBody?['snapshotHash'], snapshotHash);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_worker_prepared',
                'sessionId': 'audio_v2-worker-success',
                'context': 'home',
                'vietnameseText': 'Con muốn uống nước',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/generated-audio/water.mp3',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'browser_streaming',
                'latency': <String, dynamic>{
                  'asrMs': 430,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 500,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path == '/api/conversation') {
            conversationCalls += 1;
            return http.Response('{}', 500);
          }
          if (request.url.path.endsWith('/finalize')) {
            batchFinalizeCalled = true;
            return http.Response('{}', 500);
          }
          if (request.url.path.endsWith('/chunks') &&
              request.method == 'DELETE') {
            if (!shadowDiscarded.isCompleted) {
              shadowDiscarded.complete();
            }
            return http.Response(
              jsonEncode(<String, dynamic>{'discarded': true}),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      final previewSubscription = speculative.speculativePreviews.listen((
        preview,
      ) {
        expect(preview.audioUri?.path, '/generated-audio/water.mp3');
        if (!previewDeliveredBeforeCommit.isCompleted) {
          previewDeliveredBeforeCommit.complete();
        }
      });
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      upload.addAudioChunk(Uint8List(6400));
      speculative.markSpeculativeVoiceInactive();
      speculative.requestTerminalSpeculativePreview();
      await workerRequestStarted.future.timeout(const Duration(seconds: 2));
      final resultFuture = upload.finalize(
        capture: AudioCapture(
          filePath: 'worker-success.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 200),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 6400),
          streamedAudioBytes: 6400,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );
      await Future<void>.delayed(Duration.zero);
      releaseWorkerResponse.complete();
      final result = await resultFuture;

      await shadowDiscarded.future.timeout(const Duration(seconds: 2));
      await previewSubscription.cancel();
      expect(workerCalls, 1);
      expect(prepareCalls, 1);
      expect(commitCalls, 1);
      expect(conversationCalls, 0);
      expect(batchFinalizeCalled, isFalse);
      expect(workerRequest?.url.path, '/v1/asr/transcribe');
      expect(
        workerRequest?.headers['authorization'],
        'Bearer scoped.payload.signature',
      );
      expect(
        workerRequest?.headers['x-audio-session-id'],
        'audio_v2-worker-success',
      );
      expect(workerRequest?.headers['x-audio-sample-rate'], '16000');
      expect(workerRequest?.bodyBytes, hasLength(6400));
      final benchmark = commitBody?['benchmark'] as Map<String, dynamic>;
      expect(benchmark['requestedAsrMode'], 'browser_streaming');
      expect(benchmark['workerAsrPilotAsrMs'], 430);
      expect(benchmark['workerAsrPilotAudioBytes'], 6400);
      expect(benchmark['workerPrepareJoinedAtFinalize'], isTrue);
      expect(benchmark['workerPrepareSkippedLowLead'], isFalse);
      expect(benchmark['workerPrepareAbandonedAtFinalize'], isFalse);
      expect(benchmark['workerPreparedCommit'], isTrue);
      expect(result.conversationId, 'conv_worker_prepared');
      expect(result.audioUri?.path, '/generated-audio/water.mp3');
      expect(result.asrMode, 'browser_streaming');
      await repository.dispose();
    },
  );

  test(
    'falls back to the existing Batch finalize when Worker quota is exhausted',
    () async {
      Map<String, dynamic>? finalizeBody;
      var workerCalls = 0;
      final workerFailureSeen = Completer<void>();
      final repository = NextConversationRepository(
        config: workerPrepareConfig,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_v2-worker-fallback',
                'uploadToken': 'scoped.payload.signature',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'chunkChecksumSha256': true,
                  'scopedUploadToken': true,
                  'uploadProtocolVersion': 2,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.host == 'worker.example') {
            workerCalls += 1;
            if (!workerFailureSeen.isCompleted) {
              workerFailureSeen.complete();
            }
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error': 'workers_ai_quota_exhausted',
              }),
              429,
            );
          }
          if (request.url.path.endsWith('/chunks') &&
              request.method == 'POST') {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_batch_fallback',
                'sessionId': 'sess_batch_fallback',
                'context': 'home',
                'vietnameseText': 'Con muốn uống nước',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/generated-audio/water.mp3',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 700,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 750,
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
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      upload.addAudioChunk(Uint8List(6400));
      speculative.markSpeculativeVoiceInactive();
      speculative.requestTerminalSpeculativePreview();
      await workerFailureSeen.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      final result = await upload.finalize(
        capture: AudioCapture(
          filePath: 'worker-fallback.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 200),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 6400),
          streamedAudioBytes: 6400,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      final benchmark = finalizeBody?['benchmark'] as Map<String, dynamic>;
      expect(benchmark['workerAsrPilotAttempted'], isTrue);
      expect(
        benchmark['workerAsrPilotFallbackCode'],
        'workers_ai_quota_exhausted',
      );
      expect(workerCalls, 1);
      expect(result.asrMode, 'batch_chunks');
      await repository.dispose();
    },
  );

  test(
    'prepares Worker transcript during silence and commits without Batch or duplicate ASR',
    () async {
      var workerCalls = 0;
      var prepareCalls = 0;
      var commitCalls = 0;
      var batchPreviewCalls = 0;
      var batchFinalizeCalls = 0;
      final seenRequests = <String>[];
      final shadowDiscarded = Completer<void>();
      final workerRequestStarted = Completer<void>();
      final releaseWorkerResponse = Completer<void>();
      String? preparedSnapshotHash;
      final repository = NextConversationRepository(
        config: workerPrepareConfig,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          seenRequests.add('${request.method} ${request.url}');
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_worker_prepare_01',
                'uploadToken': 'scoped.payload.signature',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                  'chunkChecksumSha256': true,
                  'scopedUploadToken': true,
                  'uploadProtocolVersion': 2,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.host == 'worker.example') {
            workerCalls += 1;
            if (!workerRequestStarted.isCompleted) {
              workerRequestStarted.complete();
            }
            await releaseWorkerResponse.future;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'transcript': 'Con muốn uống nước',
                'timing': <String, dynamic>{'asrMs': 410, 'totalMs': 450},
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path.endsWith('/chunks') &&
              request.method == 'POST') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/conversation/prepare') {
            prepareCalls += 1;
            expect(
              request.headers['authorization'],
              'Bearer scoped.payload.signature',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            preparedSnapshotHash = body['snapshotHash'] as String;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'prepareId': 'prep_1234567890abcdef1234567890abcdef',
                'snapshotHash': preparedSnapshotHash,
                'result': <String, dynamic>{
                  'conversationId': 'conv_prepared',
                  'sessionId': 'audio_worker_prepare_01',
                  'context': 'home',
                  'vietnameseText': 'Con muốn uống nước',
                  'englishText': 'Can I have some water, please?',
                  'audioUrl': '/generated-audio/water.mp3',
                  'processingMode': 'rule',
                  'textSource': 'phrase_rule',
                  'audioSource': 'cache',
                  'asrMode': 'browser_streaming',
                  'latency': <String, dynamic>{
                    'asrMs': 410,
                    'llmMs': 0,
                    'ttsMs': 0,
                    'timeToFirstAudioMs': 450,
                  },
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path == '/api/conversation/prepare/commit') {
            commitCalls += 1;
            expect(
              request.headers['authorization'],
              'Bearer scoped.payload.signature',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['snapshotHash'], preparedSnapshotHash);
            final benchmark = body['benchmark'] as Map<String, dynamic>;
            expect(benchmark['workerPreparedCommit'], isTrue);
            expect(benchmark['workerPrepareJoinedAtFinalize'], isTrue);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_prepared',
                'sessionId': 'audio_worker_prepare_01',
                'context': 'home',
                'vietnameseText': 'Con muốn uống nước',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/generated-audio/water.mp3',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'browser_streaming',
                'latency': <String, dynamic>{
                  'asrMs': 410,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 450,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.url.path.endsWith('/preview')) {
            batchPreviewCalls += 1;
            return http.Response('{}', 500);
          }
          if (request.url.path.endsWith('/finalize')) {
            batchFinalizeCalls += 1;
            return http.Response('{}', 500);
          }
          if (request.url.path.endsWith('/chunks') &&
              request.method == 'DELETE') {
            if (!shadowDiscarded.isCompleted) shadowDiscarded.complete();
            return http.Response('{}', 200);
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      upload.addAudioChunk(Uint8List(6400));
      speculative.markSpeculativeVoiceInactive();
      final previewFuture = speculative.speculativePreviews.first;
      speculative.requestTerminalSpeculativePreview();
      await workerRequestStarted.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 320));

      releaseWorkerResponse.complete();
      final preview = await previewFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('No prepared preview. Requests: $seenRequests'),
      );

      final resultFuture = upload.finalize(
        capture: AudioCapture(
          filePath: 'worker-prepare.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 200),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 6400),
          streamedAudioBytes: 6400,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 900,
      );
      expect(preview.audioUri?.path, '/generated-audio/water.mp3');
      final result = await resultFuture;

      await shadowDiscarded.future.timeout(const Duration(seconds: 2));
      expect(result.conversationId, 'conv_prepared');
      expect(workerCalls, 1);
      expect(prepareCalls, 1);
      expect(commitCalls, 1);
      expect(batchPreviewCalls, 0);
      expect(batchFinalizeCalls, 0);
      await repository.dispose();
    },
  );

  test(
    'retries a transient speculative preview on the same PCM snapshot',
    () async {
      var previewCalls = 0;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_prefetch_retry',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            previewCalls += 1;
            if (previewCalls == 1) {
              return http.Response(
                jsonEncode(<String, dynamic>{
                  'error': <String, dynamic>{
                    'code': 'PROVIDER_UNAVAILABLE',
                    'message': 'Cloudflare is temporarily unavailable.',
                  },
                }),
                503,
              );
            }
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_after_retry',
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'phrase_rule',
                'audioUrl': '/api/audio/stream?text=water',
                'snapshotChunkCount': 2,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/discard')) {
            return http.Response('{}', 200);
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      final previewFuture = speculative.speculativePreviews.first;
      for (var index = 0; index < 6; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }

      final preview = await previewFuture.timeout(const Duration(seconds: 3));
      expect(preview.englishText, 'Can I have some water, please?');
      expect(previewCalls, 2);
      await upload.discard();
      await repository.dispose();
    },
  );

  test(
    'sends finalize immediately without waiting for terminal preview',
    () async {
      Map<String, dynamic>? finalizeBody;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_terminal_prefetch',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_terminal',
                'stabilityCount': 1,
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'cloudflare',
                'audioUrl': '/api/audio/stream?text=water',
                'audioSource': 'cloudflare_tts',
                'snapshotChunkCount': 2,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_terminal_prefetch',
                'sessionId': 'sess_terminal_prefetch',
                'context': 'home',
                'vietnameseText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/api/audio/stream?text=water',
                'processingMode': 'ai',
                'textSource': 'cloudflare',
                'audioSource': 'cloudflare_tts',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 0,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 25,
                },
              }),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      for (var index = 0; index < 4; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      speculative.markSpeculativeVoiceInactive();

      final finalizeStopwatch = Stopwatch()..start();
      await upload.finalize(
        capture: AudioCapture(
          filePath: 'terminal-prefetch.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 800),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 25600),
          streamedAudioBytes: 25600,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );
      finalizeStopwatch.stop();

      expect(finalizeBody?['prefetchId'], isNull);
      expect(finalizeStopwatch.elapsedMilliseconds, lessThan(700));
      await repository.dispose();
    },
  );

  test(
    'promotes the same regular snapshot to terminal without duplicate ASR',
    () async {
      final previewBodies = <Map<String, dynamic>>[];
      var previewCalls = 0;
      final releaseRegularPreview = Completer<void>();
      final terminalPreviewStarted = Completer<void>();
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_terminal_snapshot',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            previewCalls += 1;
            final callIndex = previewCalls;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            previewBodies.add(body);
            if (body['terminal'] == true) {
              if (!terminalPreviewStarted.isCompleted) {
                terminalPreviewStarted.complete();
              }
            } else {
              await releaseRegularPreview.future;
            }
            final pcm = body['pcm16Wav'] as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_terminal_$callIndex',
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'phrase_rule',
                'audioUrl': '/api/audio/cache/terminal.mp3',
                'audioSource': 'cache',
                'snapshotChunkCount': pcm['chunkCount'],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/discard')) {
            return http.Response('{}', 200);
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      final preview = speculative.speculativePreviews.first;

      for (var index = 0; index < 6; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      // The regular request already owns transport chunk 2. Terminal must
      // still send terminal=true for that exact snapshot so backend can join
      // the existing ASR -> translation -> audio flight.
      speculative.requestTerminalSpeculativePreview();

      await terminalPreviewStarted.future.timeout(
        const Duration(milliseconds: 500),
      );
      final terminalResult = await preview.timeout(const Duration(seconds: 3));
      // stop() asks once more after the recorder flush. With no renewed voice,
      // that request must preserve the early terminal instead of replacing it.
      speculative.requestTerminalSpeculativePreview();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      releaseRegularPreview.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(previewBodies, hasLength(2));
      expect(previewBodies.first['terminal'], isFalse);
      expect(previewBodies.last['terminal'], isTrue);
      expect(terminalResult.audioUri?.path, '/api/audio/cache/terminal.mp3');
      expect(
        (previewBodies.first['pcm16Wav'] as Map<String, dynamic>)['chunkCount'],
        2,
      );
      expect(
        (previewBodies.last['pcm16Wav'] as Map<String, dynamic>)['chunkCount'],
        2,
      );
      await upload.discard();
      await repository.dispose();
    },
  );

  test(
    'keeps late preview HTTP work alive without delaying finalize',
    () async {
      Map<String, dynamic>? finalizeBody;
      final finalizeStarted = Completer<void>();
      final previewRequestCompleted = Completer<void>();
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_late_prefetch',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            await Future<void>.delayed(const Duration(milliseconds: 1700));
            if (!previewRequestCompleted.isCompleted) {
              previewRequestCompleted.complete();
            }
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_late',
                'stabilityCount': 1,
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'cloudflare',
                'audioUrl': '/api/audio/stream?text=late-water',
                'audioSource': 'cloudflare_tts',
                'snapshotChunkCount': 2,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            if (!finalizeStarted.isCompleted) {
              finalizeStarted.complete();
            }
            await Future<void>.delayed(const Duration(milliseconds: 900));
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_late_prefetch',
                'sessionId': 'sess_late_prefetch',
                'context': 'home',
                'vietnameseText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'audioUrl': '/api/audio/stream?text=late-water',
                'processingMode': 'ai',
                'textSource': 'cloudflare',
                'audioSource': 'cloudflare_tts',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 0,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 25,
                },
              }),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();
      for (var index = 0; index < 4; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      speculative.markSpeculativeVoiceInactive();
      // _AdaptiveWebChunkUpload normally sends this after 300 ms of stable
      // silence; the repository test triggers that boundary explicitly.
      speculative.requestTerminalSpeculativePreview();

      final finalizeFuture = upload.finalize(
        capture: AudioCapture(
          filePath: 'late-prefetch.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 800),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 25600),
          streamedAudioBytes: 25600,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 700,
      );

      await finalizeFuture;
      expect(finalizeStarted.isCompleted, isTrue);
      await previewRequestCompleted.future.timeout(const Duration(seconds: 3));
      // The request started before the client received the late prefetch ID.
      // Backend finalize now joins this preview by audioSessionId.
      expect(finalizeBody?['prefetchId'], isNull);
      await repository.dispose();
    },
  );

  test(
    'starts a pending terminal preview when the next silence chunk is flushed',
    () async {
      final previewBodies = <Map<String, dynamic>>[];
      final terminalPreviewStarted = Completer<void>();
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_pending_terminal',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            previewBodies.add(body);
            if (body['terminal'] == true &&
                !terminalPreviewStarted.isCompleted) {
              terminalPreviewStarted.complete();
            }
            final pcm = body['pcm16Wav'] as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': 'prefetch_pending_terminal',
                'sourceText': 'Con muon uong nuoc',
                'englishText': 'Can I have some water, please?',
                'textSource': 'phrase_rule',
                'audioUrl': '/api/audio/cache/pending-terminal.mp3',
                'audioSource': 'cache',
                'snapshotChunkCount': pcm['chunkCount'],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/discard')) {
            return http.Response('{}', 200);
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();

      // Three 200 ms source chunks create only one transport chunk, so the
      // terminal request must remain pending instead of being discarded.
      for (var index = 0; index < 3; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      speculative.markSpeculativeVoiceInactive();
      speculative.requestTerminalSpeculativePreview();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(previewBodies, isEmpty);

      // The next silence transport chunk reaches the backend before stop().
      for (var index = 0; index < 3; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      await terminalPreviewStarted.future.timeout(
        const Duration(milliseconds: 500),
      );
      expect(previewBodies, hasLength(1));
      expect(previewBodies.single['terminal'], isTrue);
      expect(
        (previewBodies.single['pcm16Wav']
            as Map<String, dynamic>)['chunkCount'],
        2,
      );
      expect(
        previewBodies.single['benchmark'],
        containsPair('batchTerminalPipelineStartedAtSessionMs', isA<int>()),
      );

      await upload.discard();
      await repository.dispose();
    },
  );

  test(
    'terminal uses the ACKed snapshot and suppresses a duplicate while the tail uploads',
    () async {
      final previewBodies = <Map<String, dynamic>>[];
      Map<String, dynamic>? finalizeBody;
      final regularPreviewStarted = Completer<void>();
      final terminalPreviewStarted = Completer<void>();
      final thirdUploadStarted = Completer<void>();
      final releaseThirdUpload = Completer<void>();
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_acked_terminal',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'batchPrefetch': true,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            final body = latin1.decode(request.bodyBytes);
            final sequence = int.parse(
              RegExp(
                r'name="sequence"\r\n\r\n(\d+)',
              ).firstMatch(body)!.group(1)!,
            );
            if (sequence == 2) {
              if (!thirdUploadStarted.isCompleted) {
                thirdUploadStarted.complete();
              }
              await releaseThirdUpload.future;
            }
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/preview')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            previewBodies.add(body);
            final terminal = body['terminal'] == true;
            if (terminal) {
              if (!terminalPreviewStarted.isCompleted) {
                terminalPreviewStarted.complete();
              }
            } else if (!regularPreviewStarted.isCompleted) {
              regularPreviewStarted.complete();
            }
            final pcm = body['pcm16Wav'] as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'eligible': true,
                'prefetchId': terminal
                    ? 'prefetch_acked_terminal'
                    : 'prefetch_acked_regular',
                'sourceText': 'Con muon di ve sinh',
                'englishText': 'I need to use the bathroom.',
                'textSource': 'phrase_rule',
                'audioUrl': '/api/audio/cache/acked-terminal.mp3',
                'audioSource': 'cache',
                'snapshotChunkCount': pcm['chunkCount'],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_acked_terminal',
                'sessionId': 'sess_acked_terminal',
                'context': 'home',
                'vietnameseText': 'Con muon di ve sinh',
                'englishText': 'I need to use the bathroom.',
                'audioUrl': '/api/audio/cache/acked-terminal.mp3',
                'processingMode': 'rule',
                'textSource': 'phrase_rule',
                'audioSource': 'cache',
                'asrMode': 'batch_chunks',
                'latency': <String, dynamic>{
                  'asrMs': 0,
                  'llmMs': 0,
                  'ttsMs': 0,
                  'timeToFirstAudioMs': 20,
                },
              }),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final upload = await repository.startBatchChunkUpload();
      final speculative = upload as SpeculativeBatchChunkUploadSession;
      speculative.configureSpeculativePreview(
        context: PracticeContext.home,
        childAge: 6,
      );
      speculative.markSpeculativeSpeechDetected();
      speculative.markSpeculativeVoiceActive();

      for (var index = 0; index < 6; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      await regularPreviewStarted.future.timeout(
        const Duration(milliseconds: 500),
      );

      speculative.markSpeculativeVoiceInactive();
      for (var index = 0; index < 3; index += 1) {
        upload.addAudioChunk(Uint8List(6400));
      }
      await thirdUploadStarted.future.timeout(
        const Duration(milliseconds: 500),
      );

      speculative.requestTerminalSpeculativePreview();
      await terminalPreviewStarted.future.timeout(
        const Duration(milliseconds: 500),
      );
      final terminalBodies = previewBodies
          .where((body) => body['terminal'] == true)
          .toList(growable: false);
      expect(terminalBodies, hasLength(1));
      expect(
        (terminalBodies.single['pcm16Wav']
            as Map<String, dynamic>)['chunkCount'],
        2,
      );
      expect(
        terminalBodies.single['benchmark'],
        containsPair('batchTerminalSnapshotAckedChunkCount', 2),
      );

      // A second stop boundary for the same speech/snapshot must not create a
      // second terminal HTTP request.
      speculative.requestTerminalSpeculativePreview();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        previewBodies.where((body) => body['terminal'] == true),
        hasLength(1),
      );

      releaseThirdUpload.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(previewBodies, hasLength(2));
      await upload.finalize(
        capture: AudioCapture(
          filePath: 'acked-terminal.wav',
          mimeType: 'audio/wav',
          duration: const Duration(milliseconds: 1800),
          inputLabel: 'Web mic',
          isBluetoothInput: false,
          initialNoiseRms: null,
          streamHeaderBytes: buildPcm16WavHeader(pcmByteLength: 57600),
          streamedAudioBytes: 57600,
          recordingSampleRate: 16000,
        ),
        context: PracticeContext.home,
        childAge: 6,
        vadSilenceMs: 900,
      );

      final benchmark = finalizeBody?['benchmark'] as Map<String, dynamic>;
      expect(benchmark['batchTerminalDuplicateSuppressed'], greaterThan(0));
      expect(benchmark['batchTerminalSnapshotAckedChunkCount'], 2);
      expect(benchmark['batchFinalSnapshotChunkCount'], 3);
      await repository.dispose();
    },
  );

  test(
    'uses finalize metadata when the backend omits optional capabilities',
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

      expect(uploadedSequences, <int>[0]);
      expect(finalizeBody!['pcm16Wav'], <String, dynamic>{
        'sampleRate': 24000,
        'channelCount': 1,
        'bitsPerSample': 16,
        'pcmByteLength': 8000,
        'chunkCount': 1,
      });
      expect(
        (finalizeBody!['benchmark']
            as Map<String, dynamic>)['wavHeaderStrategy'],
        'finalize_metadata',
      );
      expect(
        (finalizeBody!['benchmark']
            as Map<String, dynamic>)['clientVadApplied'],
        isTrue,
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
                  'code': 'RATE_LIMITED',
                  'message': 'Backend đang bận.',
                },
              }),
              409,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
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

  test(
    'uses scoped checksum headers and resends only missing chunks',
    () async {
      final chunkAttempts = <int, int>{};
      var finalizeAttempts = 0;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final audio = body['audio'] as Map<String, dynamic>;
            expect(body['protocolVersion'], 2);
            expect(audio['encoding'], 'pcm_s16le');
            expect(audio['sourceChunkDurationMs'], 200);
            expect(audio['maxDurationMs'], 12000);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_v2-test',
                'uploadToken': 'scoped-token',
                'capabilities': <String, dynamic>{
                  'pcm16WavFinalize': true,
                  'chunkChecksumSha256': true,
                  'missingChunkRecovery': true,
                  'scopedUploadToken': true,
                  'uploadProtocolVersion': 2,
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            final body = latin1.decode(request.bodyBytes);
            final match = RegExp(
              r'name="sequence"\r\n\r\n(\d+)',
            ).firstMatch(body);
            final sequence = int.parse(match!.group(1)!);
            chunkAttempts.update(
              sequence,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
            final checksum = request.headers['x-chunk-sha256'];
            expect(request.headers['authorization'], 'Bearer scoped-token');
            expect(
              request.headers['idempotency-key'],
              'chunk:audio_v2-test:$sequence',
            );
            expect(checksum, matches(RegExp(r'^[a-f0-9]{64}$')));
            return http.Response(
              jsonEncode(<String, dynamic>{
                'uploaded': true,
                'sequence': sequence,
                'sha256': checksum,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeAttempts += 1;
            expect(request.headers['authorization'], 'Bearer scoped-token');
            if (finalizeAttempts == 1) {
              return http.Response(
                jsonEncode(<String, dynamic>{
                  'error': <String, dynamic>{
                    'code': 'AUDIO_CHUNKS_MISSING',
                    'message': 'Audio session thiếu chunk.',
                    'details': <String, dynamic>{
                      'missingSequences': <int>[0],
                    },
                  },
                }),
                409,
                headers: const <String, String>{
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final benchmark = body['benchmark'] as Map<String, dynamic>;
            expect(benchmark['missingChunkCount'], 1);
            expect(benchmark['recoveryUploadCount'], 1);
            expect(benchmark['scopedUploadToken'], isTrue);
            expect((body['pcm16Wav'] as Map<String, dynamic>)['chunkCount'], 1);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'conversationId': 'conv_recovered',
                'sessionId': 'sess_recovered',
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
      upload.addAudioChunk(Uint8List.fromList(List<int>.filled(8000, 1)));
      final result = await upload.finalize(
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

      expect(chunkAttempts, <int, int>{0: 2});
      expect(finalizeAttempts, 2);
      expect(result.conversationId, 'conv_recovered');
      await repository.dispose();
    },
  );

  test('does not retry a permanent chunk upload error', () async {
    var chunkAttempts = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        if (request.url.path == '/api/audio-sessions') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'audioSessionId': 'audio_bad_chunk',
              'capabilities': <String, dynamic>{'pcm16WavFinalize': true},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chunks')) {
          chunkAttempts += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'code': 'BAD_REQUEST',
                'message': 'Chunk không hợp lệ.',
              },
            }),
            400,
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

    await expectLater(
      upload.finalize(
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
      ),
      throwsA(
        isA<ConversationApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.errorCode, 'errorCode', 'BAD_REQUEST'),
      ),
    );

    expect(chunkAttempts, 1);
    await repository.dispose();
  });

  test('does not retry a permanent finalize conflict', () async {
    var finalizeAttempts = 0;
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        if (request.url.path == '/api/audio-sessions') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'audioSessionId': 'audio_missing_chunk',
              'capabilities': <String, dynamic>{'pcm16WavFinalize': true},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chunks')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/finalize')) {
          finalizeAttempts += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'code': 'MISSING_CHUNKS',
                'message': 'Audio session thiếu chunk.',
              },
            }),
            409,
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

    await expectLater(
      upload.finalize(
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
      ),
      throwsA(
        isA<ConversationApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.errorCode, 'errorCode', 'MISSING_CHUNKS'),
      ),
    );

    expect(finalizeAttempts, 1);
    await repository.dispose();
  });

  test(
    'preserves ASR_LOW_CONFIDENCE from finalize for the child retry prompt',
    () async {
      var finalizeAttempts = 0;
      final repository = NextConversationRepository(
        config: config,
        clientIdProvider: clientIdProvider,
        client: MockClient((request) async {
          if (request.url.path == '/api/audio-sessions') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'audioSessionId': 'audio_unclear_speech',
                'capabilities': <String, dynamic>{'pcm16WavFinalize': true},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/chunks')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/finalize')) {
            finalizeAttempts += 1;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error': <String, dynamic>{
                  'code': 'ASR_LOW_CONFIDENCE',
                  'message':
                      'Mình chưa nghe rõ. Con đưa micro lại gần và nói rõ hơn nhé.',
                },
              }),
              422,
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

      await expectLater(
        upload.finalize(
          capture: AudioCapture(
            filePath: 'unclear.wav',
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
        ),
        throwsA(
          isA<ConversationApiException>()
              .having((error) => error.statusCode, 'statusCode', 422)
              .having(
                (error) => error.errorCode,
                'errorCode',
                'ASR_LOW_CONFIDENCE',
              )
              .having(
                (error) => error.message,
                'message',
                contains('đưa micro lại gần'),
              ),
        ),
      );

      expect(finalizeAttempts, 1);
      await repository.dispose();
    },
  );

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
        expect(latency['responseToPlaybackMs'], 85);
        expect(latency['audioPreloadLoadedData'], isTrue);
        expect(latency['audioPreloadCanPlay'], isFalse);
        expect(latency['audioPreloadLoadedDataMs'], 310);
        expect(latency['audioPreloadCanPlayMs'], isNull);
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
      responseToPlaybackMs: 85,
      audioPreloadLoadedData: true,
      audioPreloadCanPlay: false,
      audioPreloadLoadedDataMs: 310,
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
                'hasUserAudio': true,
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
    expect(items.single.hasUserAudio, true);
    await repository.dispose();
  });

  test('requests a short-lived authenticated user-audio URL', () async {
    final repository = NextConversationRepository(
      config: config,
      clientIdProvider: clientIdProvider,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/conversations/conv_audio_1/user-audio');
        expect(request.url.queryParameters['clientId'], 'android_test_device');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'conversationId': 'conv_audio_1',
            'audioUrl':
                'https://api.cloudinary.com/v1_1/demo/video/download?signed=1',
            'expiresInSeconds': 60,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final audioUri = await repository.fetchUserAudioPlaybackUri('conv_audio_1');

    expect(
      audioUri,
      Uri.parse('https://api.cloudinary.com/v1_1/demo/video/download?signed=1'),
    );
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
        expect(request.url.queryParameters['deleteRelatedData'], 'true');
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
