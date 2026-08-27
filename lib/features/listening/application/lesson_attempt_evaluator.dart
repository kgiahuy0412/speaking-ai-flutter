import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/auth/installation_authenticated_client.dart';
import '../../../core/device/client_identity.dart';
import '../../../core/network/multipart_audio_file.dart';
import '../domain/lesson_guide_flow.dart';

class BackendLessonAttemptEvaluator implements LessonAttemptEvaluator {
  factory BackendLessonAttemptEvaluator({
    AppConfig? config,
    http.Client? client,
    Future<String> Function()? clientIdProvider,
  }) {
    final resolvedConfig = config ?? AppConfig.fromEnvironment();
    final resolvedClientIdProvider =
        clientIdProvider ??
        (client == null
            ? ClientIdentity().getClientId
            : () async => 'android_test-installation');
    return BackendLessonAttemptEvaluator._(
      config: resolvedConfig,
      clientIdProvider: resolvedClientIdProvider,
      client:
          client ??
          InstallationAuthenticatedClient(
            config: resolvedConfig,
            clientIdProvider: resolvedClientIdProvider,
          ),
    );
  }

  BackendLessonAttemptEvaluator._({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    required http.Client client,
  }) : _config = config,
       _clientIdProvider = clientIdProvider,
       _client = client;

  final AppConfig _config;
  final Future<String> Function() _clientIdProvider;
  final http.Client _client;

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
  }) async {
    final clientId = await _clientIdProvider();
    Uint8List? webBytes;
    if (recordingPath.startsWith('blob:')) {
      final blobResponse = await _get(Uri.parse(recordingPath));
      if (blobResponse.statusCode < 200 || blobResponse.statusCode >= 300) {
        throw const LessonAttemptEvaluationException(
          'Không đọc được bản ghi âm vừa tạo.',
        );
      }
      webBytes = blobResponse.bodyBytes;
    }

    final response = await _postLessonAttempt(
      lessonCode: lessonCode,
      sentenceId: sentenceId,
      expectedEnglish: expectedEnglish,
      recordingPath: recordingPath,
      recordingDuration: recordingDuration,
      attemptNumber: attemptNumber,
      childAge: childAge,
      clientId: clientId,
      webBytes: webBytes,
    );

    // Older production deployments do not have the lesson-specific endpoint.
    // Reuse the existing English audio recognizer so a missing route never
    // blocks the child from completing a lesson.
    if (response.statusCode == 404 || response.statusCode == 405) {
      return _evaluateWithAudioTranslationFallback(
        expectedEnglish: expectedEnglish,
        recordingPath: recordingPath,
        clientId: clientId,
        webBytes: webBytes,
      );
    }

    return _parseLessonAttemptResponse(response);
  }

  Future<http.Response> _postLessonAttempt({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    required String clientId,
    required Uint8List? webBytes,
  }) async {
    final extension = recordingPath.startsWith('blob:') ? 'webm' : 'm4a';
    final request =
        http.MultipartRequest(
            'POST',
            _config.resolve('/api/listening/evaluate-attempt'),
          )
          ..fields['expectedEnglish'] = expectedEnglish
          ..fields['lessonCode'] = lessonCode
          ..fields['sentenceId'] = sentenceId
          ..fields['attemptNumber'] = '$attemptNumber'
          ..fields['childAge'] = '$childAge'
          ..fields['clientId'] = clientId
          ..fields['recordingDurationMs'] =
              '${recordingDuration.inMilliseconds}';
    request.files.add(
      await createAudioMultipartFile(
        field: 'audio',
        path: recordingPath,
        filename: 'lesson-attempt.$extension',
        bytes: webBytes,
      ),
    );
    return http.Response.fromStream(await _send(request));
  }

  LessonAttemptOutcome _parseLessonAttemptResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const LessonAttemptEvaluationException(
        'Máy chủ chưa xử lý được câu nói. Con thử lại sau nhé.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorPayload = decoded is Map<String, dynamic>
          ? decoded['error']
          : null;
      final code = errorPayload is Map<String, dynamic>
          ? errorPayload['code']
          : null;
      if (code == 'ASR_LOW_CONFIDENCE' ||
          code == 'AUDIO_TOO_SHORT' ||
          code == 'ASR_FAILED') {
        return LessonAttemptOutcome.unclear;
      }
      final message = errorPayload is Map<String, dynamic>
          ? errorPayload['message']
          : null;
      throw LessonAttemptEvaluationException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'Chưa kiểm tra được câu nói của con. Con thử lại sau nhé.',
      );
    }

    final matched = decoded is Map<String, dynamic> ? decoded['matched'] : null;
    if (matched is! bool) {
      throw const LessonAttemptEvaluationException(
        'Kết quả kiểm tra câu nói không hợp lệ. Con thử lại sau nhé.',
      );
    }
    return matched ? LessonAttemptOutcome.good : LessonAttemptOutcome.retry;
  }

  Future<LessonAttemptOutcome> _evaluateWithAudioTranslationFallback({
    required String expectedEnglish,
    required String recordingPath,
    required String clientId,
    required Uint8List? webBytes,
  }) async {
    final extension = recordingPath.startsWith('blob:') ? 'webm' : 'm4a';
    final request =
        http.MultipartRequest('POST', _config.resolve('/api/audio/translate'))
          ..fields['sourceLanguage'] = 'en'
          ..fields['clientId'] = clientId;
    request.files.add(
      await createAudioMultipartFile(
        field: 'audio',
        path: recordingPath,
        filename: 'lesson-attempt.$extension',
        bytes: webBytes,
      ),
    );

    final response = await http.Response.fromStream(await _send(request));
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const LessonAttemptEvaluationException(
        'Máy chủ chưa xử lý được câu nói. Con thử lại sau nhé.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorPayload = decoded is Map<String, dynamic>
          ? decoded['error']
          : null;
      final code = errorPayload is Map<String, dynamic>
          ? errorPayload['code']
          : null;
      if (code == 'ASR_LOW_CONFIDENCE' ||
          code == 'AUDIO_TOO_SHORT' ||
          code == 'ASR_FAILED') {
        return LessonAttemptOutcome.unclear;
      }
      final message = errorPayload is Map<String, dynamic>
          ? errorPayload['message']
          : null;
      throw LessonAttemptEvaluationException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'Chưa kiểm tra được câu nói của con. Con thử lại sau nhé.',
      );
    }

    final transcript = decoded is Map<String, dynamic>
        ? decoded['englishText']
        : null;
    if (transcript is! String || transcript.trim().isEmpty) {
      return LessonAttemptOutcome.unclear;
    }
    return matchesRecognizedLessonEnglish(expectedEnglish, transcript)
        ? LessonAttemptOutcome.good
        : LessonAttemptOutcome.retry;
  }

  void dispose() => _client.close();

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
      );
    } on http.ClientException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
      );
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    try {
      return await _client.send(request).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
      );
    } on http.ClientException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
      );
    }
  }
}

String _normalizeLessonEnglish(String value) {
  var normalized = value.normalizeApostrophes().trim().toLowerCase();
  const contractions = <String, String>{
    "i'm": 'i am',
    "you're": 'you are',
    "he's": 'he is',
    "she's": 'she is',
    "it's": 'it is',
    "we're": 'we are',
    "they're": 'they are',
    "can't": 'cannot',
    "don't": 'do not',
    "doesn't": 'does not',
    "isn't": 'is not',
    "aren't": 'are not',
  };
  for (final entry in contractions.entries) {
    normalized = normalized.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b'),
      entry.value,
    );
  }
  const aliases = <String, String>{
    'ann': 'an',
    'anne': 'an',
    'amen': 'i am an',
  };
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => aliases[word] ?? word)
      .join(' ');
}

/// Performs the intentionally basic local pass/fail check used after Apple
/// Speech produces an English transcript for a listening lesson.
bool matchesRecognizedLessonEnglish(String expectedEnglish, String transcript) {
  final expected = _normalizeLessonEnglish(expectedEnglish);
  final actual = _normalizeLessonEnglish(transcript);
  if (expected.isEmpty || actual.isEmpty) {
    return false;
  }
  if (expected == actual) {
    return true;
  }

  final expectedWords = expected.split(' ');
  final actualWords = actual.split(' ');
  if (actualWords.length <= expectedWords.length + 2 &&
      _containsContiguousWords(actualWords, expectedWords)) {
    return true;
  }

  final longest = math.max(expected.length, actual.length);
  final similarity = 1 - (_levenshteinDistance(expected, actual) / longest);
  return similarity >= 0.82;
}

bool _containsContiguousWords(List<String> source, List<String> expected) {
  if (expected.length > source.length) return false;
  for (var start = 0; start <= source.length - expected.length; start += 1) {
    var matches = true;
    for (var index = 0; index < expected.length; index += 1) {
      if (source[start + index] != expected[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

int _levenshteinDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex;
    for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      final substitution =
          left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
          ? 0
          : 1;
      current[rightIndex] = math.min(
        math.min(current[rightIndex - 1] + 1, previous[rightIndex] + 1),
        previous[rightIndex - 1] + substitution,
      );
    }
    previous = current;
  }
  return previous.last;
}

extension on String {
  String normalizeApostrophes() => replaceAll('’', "'");
}

class LessonAttemptEvaluationException implements Exception {
  const LessonAttemptEvaluationException(this.message);

  final String message;

  @override
  String toString() => message;
}
