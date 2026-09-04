import 'dart:convert';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_audio_format.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_attempt_evaluator.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_storage.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'returns good only when backend confirms the target English words',
    () async {
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: _lessonAttemptClient(matched: true),
      );

      final outcome = await _evaluate(evaluator);

      expect(outcome, LessonAttemptOutcome.good);
      evaluator.dispose();
    },
  );

  test(
    'returns retry when recognized speech does not match the lesson',
    () async {
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: _lessonAttemptClient(
          matched: false,
          transcript: 'I want to eat rice',
        ),
      );

      final outcome = await _evaluate(evaluator);

      expect(outcome, LessonAttemptOutcome.retry);
      evaluator.dispose();
    },
  );

  test(
    'accepts a matching recognizer transcript after a stale backend false negative',
    () async {
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: _lessonAttemptClient(matched: false, transcript: 'Make calls.'),
      );

      expect(
        await _evaluate(evaluator, expectedEnglish: 'Make calls.'),
        LessonAttemptOutcome.good,
      );
      evaluator.dispose();
    },
  );

  test('keeps unclear or silent audio separate from a wrong answer', () async {
    final evaluator = BackendLessonAttemptEvaluator(
      config: _config,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        return _jsonResponse(<String, Object?>{
          'error': <String, Object?>{
            'code': 'ASR_LOW_CONFIDENCE',
            'message': 'Chưa nghe rõ.',
          },
        }, 422);
      }),
    );

    expect(await _evaluate(evaluator), LessonAttemptOutcome.unclear);
    evaluator.dispose();
  });

  test('hides connection details behind a child-friendly message', () async {
    final evaluator = BackendLessonAttemptEvaluator(
      config: _config,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    await expectLater(
      _evaluate(evaluator),
      throwsA(
        isA<LessonAttemptEvaluationException>()
            .having(
              (error) => error.toString(),
              'message',
              'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
            )
            .having(
              (error) => error.backendUnavailable,
              'backend unavailable',
              isTrue,
            ),
      ),
    );
    evaluator.dispose();
  });

  test(
    'falls back to the production audio recognizer when route is missing',
    () async {
      final requestedPaths = <String>[];
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(<int>[1, 2, 3], 200);
          }
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/listening/evaluate-attempt') {
            return http.Response('<html>Not Found</html>', 404);
          }
          expect(request.url.path, '/api/audio/translate');
          return _jsonResponse(<String, Object?>{
            'englishText': 'I am Ann.',
          }, 200);
        }),
      );

      expect(await _evaluate(evaluator), LessonAttemptOutcome.good);
      expect(requestedPaths, <String>[
        '/api/listening/evaluate-attempt',
        '/api/audio/translate',
      ]);
      evaluator.dispose();
    },
  );

  test(
    'fallback rejects speech that differs from the lesson sentence',
    () async {
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(<int>[1, 2, 3], 200);
          }
          if (request.url.path == '/api/listening/evaluate-attempt') {
            return http.Response('<html>Not Found</html>', 404);
          }
          return _jsonResponse(<String, Object?>{
            'englishText': 'I want to eat rice',
          }, 200);
        }),
      );

      expect(await _evaluate(evaluator), LessonAttemptOutcome.retry);
      evaluator.dispose();
    },
  );

  test(
    'fallback accepts the observed Amen transcription for I am An',
    () async {
      final evaluator = BackendLessonAttemptEvaluator(
        config: _config,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(<int>[1, 2, 3], 200);
          }
          if (request.url.path == '/api/listening/evaluate-attempt') {
            return http.Response('<html>Not Found</html>', 404);
          }
          return _jsonResponse(<String, Object?>{'englishText': 'Amen.'}, 200);
        }),
      );

      expect(await _evaluate(evaluator), LessonAttemptOutcome.good);
      evaluator.dispose();
    },
  );

  test('V4 fallback requires the complete Alphabet target', () async {
    final evaluator = BackendLessonAttemptEvaluator(
      config: _config,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        if (request.url.path == '/api/listening/evaluate-attempt') {
          return http.Response('<html>Not Found</html>', 404);
        }
        return _jsonResponse(<String, Object?>{'englishText': 'Apple.'}, 200);
      }),
    );

    expect(
      await _evaluate(
        evaluator,
        expectedEnglish: 'A. Apple.',
        requireAllExpectedTokens: true,
      ),
      LessonAttemptOutcome.retry,
    );
    evaluator.dispose();
  });

  test('fallback keeps an ASR failure separate from a wrong answer', () async {
    final evaluator = BackendLessonAttemptEvaluator(
      config: _config,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        if (request.url.path == '/api/listening/evaluate-attempt') {
          return http.Response('<html>Not Found</html>', 404);
        }
        return _jsonResponse(<String, Object?>{
          'error': <String, Object?>{
            'code': 'ASR_FAILED',
            'message': 'Cloudflare Workers AI không dịch được đoạn ghi âm này.',
          },
        }, 502);
      }),
    );

    expect(await _evaluate(evaluator), LessonAttemptOutcome.unclear);
    evaluator.dispose();
  });

  test('handles a non-JSON server error without FormatException', () async {
    final evaluator = BackendLessonAttemptEvaluator(
      config: _config,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        return http.Response('Internal server error.', 500);
      }),
    );

    await expectLater(
      _evaluate(evaluator),
      throwsA(
        isA<LessonAttemptEvaluationException>().having(
          (error) => error.toString(),
          'message',
          'Máy chủ chưa xử lý được câu nói. Con thử lại sau nhé.',
        ),
      ),
    );
    evaluator.dispose();
  });

  group('basic Apple Speech lesson matching', () {
    test('accepts exact speech and common contraction/name variants', () {
      expect(matchesRecognizedLessonEnglish('I am An', "I'm Anne"), isTrue);
      expect(matchesRecognizedLessonEnglish("I'm An", 'Amen'), isTrue);
    });

    test('allows a short recognizer prefix around the target sentence', () {
      expect(
        matchesRecognizedLessonEnglish('I am hungry', 'Okay I am hungry'),
        isTrue,
      );
    });

    test('keeps silence and a different sentence out of the pass result', () {
      expect(matchesRecognizedLessonEnglish('I am hungry', ''), isFalse);
      expect(
        matchesRecognizedLessonEnglish('I am hungry', 'I want the bathroom'),
        isFalse,
      );
    });
  });

  group('Android backend-first offline fallback', () {
    test(
      'keeps the normal backend result without calling on-device ASR',
      () async {
        final backend = _FakeAttemptEvaluator.outcome(
          LessonAttemptOutcome.good,
        );
        final recognizer = _FakeLessonRecordedSpeechRecognizer(
          const LessonRecordedSpeechRecognition(transcript: 'wrong answer'),
        );
        final evaluator = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: backend,
          recognizer: recognizer,
        );

        expect(
          await _evaluateBackendFirst(evaluator),
          LessonAttemptOutcome.good,
        );
        expect(backend.calls, 1);
        expect(recognizer.calls, 0);
      },
    );

    test(
      'uses strict English on-device ASR only after connectivity failure',
      () async {
        final backend = _FakeAttemptEvaluator.error(
          const LessonAttemptEvaluationException(
            'offline',
            backendUnavailable: true,
          ),
        );
        final recognizer = _FakeLessonRecordedSpeechRecognizer(
          const LessonRecordedSpeechRecognition(transcript: "I'm ready!"),
        );
        final evaluator = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: backend,
          recognizer: recognizer,
        );

        expect(
          await _evaluateBackendFirst(
            evaluator,
            expectedEnglish: 'I am ready.',
          ),
          LessonAttemptOutcome.good,
        );
        expect(recognizer.calls, 1);
        expect(recognizer.lastPath, endsWith('.wav'));
        expect(recognizer.lastLocale, 'en-US');
        expect(recognizer.lastPreferOnDevice, isTrue);
        expect(recognizer.lastRequireOnDevice, isTrue);
      },
    );

    test(
      'accepts alternatives and returns retry for different speech',
      () async {
        final matching = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: _offlineBackend(),
          recognizer: _FakeLessonRecordedSpeechRecognizer(
            const LessonRecordedSpeechRecognition(
              transcript: 'I want rice',
              alternatives: <String>['I am ready'],
            ),
          ),
        );
        expect(
          await _evaluateBackendFirst(matching, expectedEnglish: "I'm ready"),
          LessonAttemptOutcome.good,
        );

        final different = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: _offlineBackend(),
          recognizer: _FakeLessonRecordedSpeechRecognizer(
            const LessonRecordedSpeechRecognition(transcript: 'I want rice'),
          ),
        );
        expect(
          await _evaluateBackendFirst(different, expectedEnglish: 'I am ready'),
          LessonAttemptOutcome.retry,
        );
      },
    );

    test('maps silence, no match, and timeout to unclear', () async {
      final empty = BackendFirstLessonAttemptEvaluator(
        backendEvaluator: _offlineBackend(),
        recognizer: _FakeLessonRecordedSpeechRecognizer(
          const LessonRecordedSpeechRecognition(transcript: ''),
        ),
      );
      expect(await _evaluateBackendFirst(empty), LessonAttemptOutcome.unclear);

      for (final code in <String>['SPEECH_NO_MATCH', 'SPEECH_TIMEOUT']) {
        final evaluator = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: _offlineBackend(),
          recognizer: _FakeLessonRecordedSpeechRecognizer.error(code),
        );
        expect(
          await _evaluateBackendFirst(evaluator),
          LessonAttemptOutcome.unclear,
        );
      }
    });

    test(
      'preserves backend error when local model or WAV is unavailable',
      () async {
        for (final code in <String>[
          'ON_DEVICE_SPEECH_UNAVAILABLE',
          'RECORDED_AUDIO_FILE_INVALID',
        ]) {
          final backendError = const LessonAttemptEvaluationException(
            'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
            backendUnavailable: true,
          );
          final evaluator = BackendFirstLessonAttemptEvaluator(
            backendEvaluator: _FakeAttemptEvaluator.error(backendError),
            recognizer: _FakeLessonRecordedSpeechRecognizer.error(code),
          );
          await expectLater(
            _evaluateBackendFirst(evaluator),
            throwsA(
              isA<LessonAttemptEvaluationException>().having(
                (error) => error.message,
                'message',
                backendError.message,
              ),
            ),
          );
        }
      },
    );

    test(
      'does not use local ASR for a non-connectivity backend failure',
      () async {
        final recognizer = _FakeLessonRecordedSpeechRecognizer(
          const LessonRecordedSpeechRecognition(transcript: 'I am ready'),
        );
        final evaluator = BackendFirstLessonAttemptEvaluator(
          backendEvaluator: _FakeAttemptEvaluator.error(
            const LessonAttemptEvaluationException('server rejected request'),
          ),
          recognizer: recognizer,
        );

        await expectLater(
          _evaluateBackendFirst(evaluator),
          throwsA(isA<LessonAttemptEvaluationException>()),
        );
        expect(recognizer.calls, 0);
      },
    );
  });

  test('uses WAV on Android and preserves existing backend extensions', () {
    expect(
      lessonRecordingFileExtension(platform: TargetPlatform.android),
      'wav',
    );
    expect(lessonRecordingFileExtension(platform: TargetPlatform.iOS), 'm4a');
    expect(lessonAudioExtensionForPath(r'C:\recordings\answer.WAV'), 'wav');
    expect(lessonAudioExtensionForPath('/recordings/legacy.m4a'), 'm4a');
    expect(
      lessonAudioExtensionForPath('blob:https://example.test/attempt'),
      'webm',
    );
  });

  test('default Android evaluator is backend-first with offline fallback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final evaluator = createDefaultLessonAttemptEvaluator();
    expect(evaluator, isA<BackendFirstLessonAttemptEvaluator>());
    (evaluator as DisposableLessonAttemptEvaluator).dispose();
  });
}

Future<LessonAttemptOutcome> _evaluateBackendFirst(
  LessonAttemptEvaluator evaluator, {
  String expectedEnglish = 'I am ready',
}) => evaluator.evaluate(
  lessonCode: 'A035_T01_L01',
  sentenceId: 'A035_T01_L01_S01',
  expectedEnglish: expectedEnglish,
  recordingPath: r'C:\recordings\attempt.wav',
  recordingDuration: const Duration(seconds: 2),
  attemptNumber: 1,
  childAge: 4,
);

Future<LessonAttemptOutcome> _evaluate(
  BackendLessonAttemptEvaluator evaluator, {
  String expectedEnglish = "I'm An",
  bool requireAllExpectedTokens = false,
}) {
  return evaluator.evaluate(
    lessonCode: 'A035_T01_L01',
    sentenceId: 'A035_T01_L01_S01',
    expectedEnglish: expectedEnglish,
    recordingPath: 'blob:https://example.test/attempt',
    recordingDuration: const Duration(seconds: 2),
    attemptNumber: 1,
    childAge: 4,
    requireAllExpectedTokens: requireAllExpectedTokens,
  );
}

MockClient _lessonAttemptClient({
  required bool matched,
  String transcript = "I'm An",
}) {
  return MockClient((request) async {
    if (request.method == 'GET') {
      return http.Response.bytes(<int>[1, 2, 3], 200);
    }
    expect(
      request.url,
      Uri.parse('https://api.example.com/api/listening/evaluate-attempt'),
    );
    expect(request.headers['content-type'], startsWith('multipart/form-data;'));
    return _jsonResponse(<String, Object?>{
      'transcript': transcript,
      'matched': matched,
    }, 200);
  });
}

http.Response _jsonResponse(Map<String, Object?> payload, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(payload)),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

final AppConfig _config = AppConfig(
  backendBaseUri: Uri.parse('https://api.example.com'),
  useDemoBackend: false,
  childAge: 4,
);

_FakeAttemptEvaluator _offlineBackend() => _FakeAttemptEvaluator.error(
  const LessonAttemptEvaluationException('offline', backendUnavailable: true),
);

class _FakeLessonRecordedSpeechRecognizer
    implements LessonRecordedSpeechRecognizer {
  _FakeLessonRecordedSpeechRecognizer(this.result) : errorCode = null;

  _FakeLessonRecordedSpeechRecognizer.error(this.errorCode) : result = null;

  final LessonRecordedSpeechRecognition? result;
  final String? errorCode;
  int calls = 0;
  String? lastPath;
  String? lastLocale;
  bool? lastPreferOnDevice;
  bool? lastRequireOnDevice;

  @override
  Future<LessonRecordedSpeechRecognition> recognizeFile({
    required String path,
    String locale = 'vi-VN',
    bool preferOnDevice = false,
    bool requireOnDevice = false,
  }) async {
    calls += 1;
    lastPath = path;
    lastLocale = locale;
    lastPreferOnDevice = preferOnDevice;
    lastRequireOnDevice = requireOnDevice;
    final code = errorCode;
    if (code != null) {
      throw LessonRecordedSpeechRecognitionException(code, code);
    }
    return result!;
  }
}

class _FakeAttemptEvaluator implements LessonAttemptEvaluator {
  _FakeAttemptEvaluator.outcome(this.result) : error = null;

  _FakeAttemptEvaluator.error(this.error) : result = null;

  final LessonAttemptOutcome? result;
  final Object? error;
  int calls = 0;

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async {
    calls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }
}
