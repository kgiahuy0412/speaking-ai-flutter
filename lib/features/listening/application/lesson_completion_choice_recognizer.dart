import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/network/multipart_audio_file.dart';
import 'lesson_media_service.dart';

enum LessonCompletionChoice { restartLesson, nextLesson }

class LessonCompletionChoiceResolver {
  const LessonCompletionChoiceResolver();

  LessonCompletionChoice? resolve(String transcript) {
    final value = _normalize(transcript);
    if (value.isEmpty) {
      return null;
    }
    if (_contains(value, 'luyen lai tu dau') ||
        _contains(value, 'luyen lai') ||
        _contains(value, 'hoc lai tu dau') ||
        _contains(value, 'hoc lai')) {
      return LessonCompletionChoice.restartLesson;
    }
    if (_contains(value, 'bai tiep theo') ||
        _contains(value, 'hoc bai tiep') ||
        _contains(value, 'bai ke tiep') ||
        _contains(value, 'tiep theo')) {
      return LessonCompletionChoice.nextLesson;
    }
    return null;
  }

  static bool _contains(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

  static String _normalize(String value) {
    var normalized = value.trim().toLowerCase();
    const replacements = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

abstract interface class LessonCompletionChoiceRecognizer {
  Future<String> transcribe(LessonRecording recording);

  void dispose();
}

class BackendLessonCompletionChoiceRecognizer
    implements LessonCompletionChoiceRecognizer {
  BackendLessonCompletionChoiceRecognizer({
    AppConfig? config,
    http.Client? client,
  }) : _config = config ?? AppConfig.fromEnvironment(),
       _client = client ?? http.Client();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<String> transcribe(LessonRecording recording) async {
    Uint8List? webBytes;
    if (recording.filePath.startsWith('blob:')) {
      final blobResponse = await _client.get(Uri.parse(recording.filePath));
      if (blobResponse.statusCode < 200 || blobResponse.statusCode >= 300) {
        throw StateError('Không đọc được câu trả lời vừa ghi âm.');
      }
      webBytes = blobResponse.bodyBytes;
    }

    final extension = recording.filePath.startsWith('blob:') ? 'webm' : 'm4a';
    final request = http.MultipartRequest(
      'POST',
      _config.resolve('/api/listening/recognize-choice'),
    );
    request.files.add(
      await createAudioMultipartFile(
        field: 'audio',
        path: recording.filePath,
        filename: 'lesson-choice.$extension',
        bytes: webBytes,
      ),
    );

    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorPayload = decoded is Map<String, dynamic>
          ? decoded['error']
          : null;
      final message = errorPayload is Map<String, dynamic>
          ? errorPayload['message']
          : null;
      throw StateError(
        message is String && message.trim().isNotEmpty
            ? message
            : 'Chưa nhận ra lựa chọn của con.',
      );
    }
    final transcript = decoded is Map<String, dynamic>
        ? decoded['transcript']
        : null;
    if (transcript is! String || transcript.trim().isEmpty) {
      throw StateError('Chưa nhận ra lựa chọn của con.');
    }
    return transcript.trim();
  }

  @override
  void dispose() => _client.close();
}
