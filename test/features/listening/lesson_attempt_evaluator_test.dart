import 'dart:convert';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_attempt_evaluator.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
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
        isA<LessonAttemptEvaluationException>().having(
          (error) => error.toString(),
          'message',
          'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
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
}

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
