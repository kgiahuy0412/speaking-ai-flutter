import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/network/multipart_audio_file.dart';
import 'lesson_audio_format.dart';
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
        _contains(value, 'hoc lai') ||
        _contains(value, 'practice again') ||
        _contains(value, 'learn again') ||
        _contains(value, 'start over') ||
        _contains(value, 'restart lesson') ||
        _contains(value, 'repeat lesson')) {
      return LessonCompletionChoice.restartLesson;
    }
    if (_contains(value, 'bai tiep theo') ||
        _contains(value, 'hoc bai tiep') ||
        _contains(value, 'bai ke tiep') ||
        _contains(value, 'tiep theo') ||
        _contains(value, 'next lesson') ||
        _contains(value, 'next one')) {
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
    try {
      return await _transcribe(recording);
    } on TimeoutException {
      throw const LessonCompletionRecognitionException(
        'Chưa kết nối được máy chủ. Con thử lại nhé.',
      );
    } on http.ClientException {
      throw const LessonCompletionRecognitionException(
        'Chưa kết nối được máy chủ. Con thử lại nhé.',
      );
    }
  }

  Future<String> _transcribe(LessonRecording recording) async {
    Uint8List? webBytes;
    if (recording.filePath.startsWith('blob:')) {
      final blobResponse = await _client.get(Uri.parse(recording.filePath));
      if (blobResponse.statusCode < 200 || blobResponse.statusCode >= 300) {
        throw const LessonCompletionRecognitionException(
          'Không đọc được câu trả lời vừa ghi âm.',
        );
      }
      webBytes = blobResponse.bodyBytes;
    }

    var response = await _postRecording(
      route: '/api/listening/recognize-choice',
      recordingPath: recording.filePath,
      webBytes: webBytes,
    );
    var transcriptField = 'transcript';
    if (response.statusCode == 404 || response.statusCode == 405) {
      response = await _postRecording(
        route: '/api/audio/translate',
        recordingPath: recording.filePath,
        webBytes: webBytes,
        sourceLanguage: 'vi',
      );
      transcriptField = 'englishText';
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorPayload = decoded is Map<String, dynamic>
          ? decoded['error']
          : null;
      final message = errorPayload is Map<String, dynamic>
          ? errorPayload['message']
          : null;
      throw LessonCompletionRecognitionException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'Chưa nhận ra lựa chọn của con.',
      );
    }
    if (decoded == null) {
      throw const LessonCompletionRecognitionException(
        'Máy chủ chưa xử lý được câu trả lời. Con thử lại nhé.',
      );
    }
    final transcript = decoded is Map<String, dynamic>
        ? decoded[transcriptField]
        : null;
    if (transcript is! String || transcript.trim().isEmpty) {
      throw const LessonCompletionRecognitionException(
        'Chưa nhận ra lựa chọn của con.',
      );
    }
    return transcript.trim();
  }

  Future<http.Response> _postRecording({
    required String route,
    required String recordingPath,
    required Uint8List? webBytes,
    String? sourceLanguage,
  }) async {
    final extension = lessonAudioExtensionForPath(recordingPath);
    final request = http.MultipartRequest('POST', _config.resolve(route));
    if (sourceLanguage != null) {
      request.fields['sourceLanguage'] = sourceLanguage;
    }
    request.files.add(
      await createAudioMultipartFile(
        field: 'audio',
        path: recordingPath,
        filename: 'lesson-choice.$extension',
        bytes: webBytes,
      ),
    );
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    return http.Response.fromStream(streamed);
  }

  @override
  void dispose() => _client.close();
}

class LessonCompletionRecognitionException implements Exception {
  const LessonCompletionRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}
