import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_completion_choice_recognizer.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const resolver = LessonCompletionChoiceResolver();

  test('recognizes restart lesson variants', () {
    expect(
      resolver.resolve('Con muốn luyện lại từ đầu ạ'),
      LessonCompletionChoice.restartLesson,
    );
    expect(resolver.resolve('học lại'), LessonCompletionChoice.restartLesson);
  });

  test('recognizes next lesson variants', () {
    expect(
      resolver.resolve('Bài tiếp theo'),
      LessonCompletionChoice.nextLesson,
    );
    expect(
      resolver.resolve('Học bài kế tiếp nhé'),
      LessonCompletionChoice.nextLesson,
    );
  });

  test('recognizes English translations returned by the legacy server', () {
    expect(
      resolver.resolve('I want to practice again'),
      LessonCompletionChoice.restartLesson,
    );
    expect(
      resolver.resolve('The next lesson'),
      LessonCompletionChoice.nextLesson,
    );
  });

  test('does not guess an unrelated answer', () {
    expect(resolver.resolve('Con chưa biết'), isNull);
  });

  test('falls back to the legacy audio API when the route is missing', () async {
    final audio = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lesson-choice-fallback-test.wav',
    );
    await audio.writeAsBytes(<int>[1, 2, 3, 4]);
    addTearDown(() async {
      if (await audio.exists()) {
        await audio.delete();
      }
    });
    final requestedPaths = <String>[];
    final recognizer = BackendLessonCompletionChoiceRecognizer(
      config: AppConfig(
        backendBaseUri: Uri.parse('https://example.test'),
        useDemoBackend: false,
        childAge: 6,
      ),
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        expect(
          latin1.decode(request.bodyBytes),
          contains('filename="lesson-choice.wav"'),
        );
        if (request.url.path == '/api/listening/recognize-choice') {
          return http.Response('<html>Not found</html>', 404);
        }
        expect(request.url.path, '/api/audio/translate');
        return http.Response(
          '{"englishText":"The next lesson"}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(recognizer.dispose);

    final transcript = await recognizer.transcribe(
      LessonRecording(
        filePath: audio.path,
        duration: const Duration(seconds: 1),
      ),
    );

    expect(transcript, 'The next lesson');
    expect(requestedPaths, <String>[
      '/api/listening/recognize-choice',
      '/api/audio/translate',
    ]);
  });

  test('returns a friendly error when both server routes return HTML', () async {
    final audio = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lesson-choice-test.m4a',
    );
    await audio.writeAsBytes(<int>[1, 2, 3, 4]);
    addTearDown(() async {
      if (await audio.exists()) {
        await audio.delete();
      }
    });
    final recognizer = BackendLessonCompletionChoiceRecognizer(
      config: AppConfig(
        backendBaseUri: Uri.parse('https://example.test'),
        useDemoBackend: false,
        childAge: 6,
      ),
      client: MockClient((request) async {
        expect(
          request.url.path,
          anyOf('/api/listening/recognize-choice', '/api/audio/translate'),
        );
        return http.Response('<html>Not found</html>', 404);
      }),
    );
    addTearDown(recognizer.dispose);

    await expectLater(
      recognizer.transcribe(
        LessonRecording(
          filePath: audio.path,
          duration: const Duration(seconds: 1),
        ),
      ),
      throwsA(
        isA<LessonCompletionRecognitionException>().having(
          (error) => error.toString(),
          'message',
          'Chưa nhận ra lựa chọn của con.',
        ),
      ),
    );
  });
}
