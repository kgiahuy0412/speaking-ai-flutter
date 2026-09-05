import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/auth/installation_authenticated_client.dart';
import '../../../core/device/client_identity.dart';
import '../../../core/network/multipart_audio_file.dart';
import '../domain/lesson_guide_flow.dart';
import '../domain/lesson_recognition.dart';
import 'lesson_audio_format.dart';

abstract interface class DisposableLessonAttemptEvaluator {
  void dispose();
}

class LessonRecordedSpeechRecognition {
  const LessonRecordedSpeechRecognition({
    required this.transcript,
    this.alternatives = const <String>[],
  });

  final String transcript;
  final List<String> alternatives;
}

class LessonRecordedSpeechRecognitionException implements Exception {
  const LessonRecordedSpeechRecognitionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class LessonRecordedSpeechRecognizer {
  Future<LessonRecordedSpeechRecognition> recognizeFile({
    required String path,
    String locale = 'vi-VN',
    bool preferOnDevice = false,
    bool requireOnDevice = false,
  });
}

class MethodChannelLessonRecordedSpeechRecognizer
    implements LessonRecordedSpeechRecognizer {
  const MethodChannelLessonRecordedSpeechRecognizer({
    MethodChannel channel = const MethodChannel('homi_offline_speech'),
    Duration timeout = const Duration(seconds: 20),
  }) : _channel = channel,
       _timeout = timeout;

  final MethodChannel _channel;
  final Duration _timeout;

  @override
  Future<LessonRecordedSpeechRecognition> recognizeFile({
    required String path,
    String locale = 'vi-VN',
    bool preferOnDevice = false,
    bool requireOnDevice = false,
  }) async {
    try {
      final payload = await _channel
          .invokeMethod<Object?>('recognizeFile', <String, Object?>{
            'path': path,
            'sampleRate': 16000,
            'locale': locale,
            'preferOnDevice': preferOnDevice,
            'requireOnDevice': requireOnDevice,
          })
          .timeout(_timeout);
      if (payload is! Map<Object?, Object?>) {
        throw const LessonRecordedSpeechRecognitionException(
          'RECORDED_AUDIO_RESULT_INVALID',
          'Kết quả nhận diện Android không hợp lệ.',
        );
      }
      final transcript = payload['text'];
      final alternatives = payload['alternatives'];
      return LessonRecordedSpeechRecognition(
        transcript: transcript is String ? transcript.trim() : '',
        alternatives: alternatives is List<Object?>
            ? alternatives
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false)
            : const <String>[],
      );
    } on TimeoutException {
      try {
        await _channel
            .invokeMethod<void>('cancel')
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Native cleanup is best-effort after a bounded recognition timeout.
      }
      throw const LessonRecordedSpeechRecognitionException(
        'SPEECH_TIMEOUT',
        'Nhận diện bản ghi âm mất quá nhiều thời gian.',
      );
    } on MissingPluginException {
      throw const LessonRecordedSpeechRecognitionException(
        'ON_DEVICE_SPEECH_UNAVAILABLE',
        'Thiết bị chưa có bộ nhận diện giọng nói offline.',
      );
    } on PlatformException catch (error) {
      throw LessonRecordedSpeechRecognitionException(
        error.code,
        error.message ?? 'Không thể nhận diện bản ghi âm.',
      );
    }
  }
}

/// Keeps normal online lesson scoring unchanged. Only a backend connectivity
/// failure activates HOMI's app-owned English model on Android.
class BackendFirstLessonAttemptEvaluator
    implements LessonAttemptEvaluator, DisposableLessonAttemptEvaluator {
  BackendFirstLessonAttemptEvaluator({
    required LessonAttemptEvaluator backendEvaluator,
    LessonRecordedSpeechRecognizer recognizer =
        const MethodChannelLessonRecordedSpeechRecognizer(),
  }) : _backendEvaluator = backendEvaluator,
       _recognizer = recognizer;

  final LessonAttemptEvaluator _backendEvaluator;
  final LessonRecordedSpeechRecognizer _recognizer;

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
    LessonAttemptEvaluationException backendFailure;
    try {
      return await _backendEvaluator.evaluate(
        lessonCode: lessonCode,
        sentenceId: sentenceId,
        expectedEnglish: expectedEnglish,
        recordingPath: recordingPath,
        recordingDuration: recordingDuration,
        attemptNumber: attemptNumber,
        childAge: childAge,
        acceptedVariants: acceptedVariants,
        requireAllExpectedTokens: requireAllExpectedTokens,
      );
    } on LessonAttemptEvaluationException catch (error) {
      if (!error.backendUnavailable) rethrow;
      backendFailure = error;
    } on TimeoutException {
      backendFailure = const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
      );
    } on http.ClientException {
      backendFailure = const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
      );
    }

    try {
      final recognition = await _recognizer.recognizeFile(
        path: recordingPath,
        locale: 'en-US',
        preferOnDevice: true,
        requireOnDevice: true,
      );
      final candidates = <String>{
        recognition.transcript,
        ...recognition.alternatives,
      }.where((candidate) => candidate.trim().isNotEmpty);
      if (candidates.isEmpty) return LessonAttemptOutcome.unclear;
      return candidates.any(
            (candidate) => matchesRecognizedLessonEnglish(
              expectedEnglish,
              candidate,
              acceptedVariants: acceptedVariants,
              requireAllExpectedTokens: requireAllExpectedTokens,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
    } on LessonRecordedSpeechRecognitionException catch (error) {
      if (_isUnclearRecognitionFailure(error.code)) {
        return LessonAttemptOutcome.unclear;
      }
      throw backendFailure;
    }
  }

  bool _isUnclearRecognitionFailure(String code) =>
      code == 'SPEECH_NO_MATCH' ||
      code == 'SPEECH_TIMEOUT' ||
      code == 'RECORDED_AUDIO_UNCLEAR' ||
      code == 'RECORDED_AUDIO_RECOGNITION_TIMEOUT';

  @override
  void dispose() {
    final backendEvaluator = _backendEvaluator;
    if (backendEvaluator is DisposableLessonAttemptEvaluator) {
      (backendEvaluator as DisposableLessonAttemptEvaluator).dispose();
    }
  }
}

LessonAttemptEvaluator createDefaultLessonAttemptEvaluator() {
  final backendEvaluator = BackendLessonAttemptEvaluator();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return BackendFirstLessonAttemptEvaluator(
      backendEvaluator: backendEvaluator,
    );
  }
  return backendEvaluator;
}

class BackendLessonAttemptEvaluator
    implements LessonAttemptEvaluator, DisposableLessonAttemptEvaluator {
  factory BackendLessonAttemptEvaluator({
    AppConfig? config,
    http.Client? client,
    Future<String> Function()? clientIdProvider,
    Future<void> Function()? clientIdResetter,
  }) {
    final resolvedConfig = config ?? AppConfig.fromEnvironment();
    // Keep the provider and resetter on the same identity instance. A stale
    // server registration then rotates both the native id and this object's
    // cached value before the authenticated client retries the request.
    final clientIdentity = client == null && clientIdProvider == null
        ? ClientIdentity()
        : null;
    final resolvedClientIdProvider =
        clientIdProvider ??
        (clientIdentity?.getClientId ??
            () async => 'android_test-installation');
    final resolvedClientIdResetter =
        clientIdResetter ?? clientIdentity?.resetClientId;
    return BackendLessonAttemptEvaluator._(
      config: resolvedConfig,
      clientIdProvider: resolvedClientIdProvider,
      client:
          client ??
          InstallationAuthenticatedClient(
            config: resolvedConfig,
            clientIdProvider: resolvedClientIdProvider,
            clientIdResetter: resolvedClientIdResetter,
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
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async {
    await _ensureInstallationAuthenticated();
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
      acceptedVariants: acceptedVariants,
      requireAllExpectedTokens: requireAllExpectedTokens,
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
        acceptedVariants: acceptedVariants,
        requireAllExpectedTokens: requireAllExpectedTokens,
        clientId: clientId,
        webBytes: webBytes,
      );
    }

    return _parseLessonAttemptResponse(
      response,
      expectedEnglish: expectedEnglish,
      acceptedVariants: acceptedVariants,
      requireAllExpectedTokens: requireAllExpectedTokens,
    );
  }

  Future<http.Response> _postLessonAttempt({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    required Iterable<String> acceptedVariants,
    required bool requireAllExpectedTokens,
    required String clientId,
    required Uint8List? webBytes,
  }) async {
    final extension = lessonAudioExtensionForPath(recordingPath);
    final request =
        http.MultipartRequest(
            'POST',
            _config.resolve('/api/listening/evaluate-attempt'),
          )
          ..fields['expectedEnglish'] = expectedEnglish
          ..fields['acceptedVariants'] = jsonEncode(acceptedVariants.toList())
          ..fields['requireAllExpectedTokens'] = requireAllExpectedTokens
              .toString()
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

  LessonAttemptOutcome _parseLessonAttemptResponse(
    http.Response response, {
    required String expectedEnglish,
    required Iterable<String> acceptedVariants,
    required bool requireAllExpectedTokens,
  }) {
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
    if (matched) {
      return LessonAttemptOutcome.good;
    }

    // Some deployed evaluators use a stricter server-side matcher than the V4
    // authored recognition inventory. When they already return an English
    // transcript, apply that inventory locally before telling a child they are
    // wrong. This does not accept arbitrary audio: every expected token and
    // authored variant is still checked by the lesson matcher.
    final transcript = _recognizedEnglishFrom(decoded);
    if (transcript != null &&
        matchesRecognizedLessonEnglish(
          expectedEnglish,
          transcript,
          acceptedVariants: acceptedVariants,
          requireAllExpectedTokens: requireAllExpectedTokens,
        )) {
      return LessonAttemptOutcome.good;
    }
    return LessonAttemptOutcome.retry;
  }

  String? _recognizedEnglishFrom(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    for (final field in const <String>[
      'englishText',
      'transcript',
      'recognizedText',
      'text',
    ]) {
      final value = decoded[field];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Future<LessonAttemptOutcome> _evaluateWithAudioTranslationFallback({
    required String expectedEnglish,
    required String recordingPath,
    required Iterable<String> acceptedVariants,
    required bool requireAllExpectedTokens,
    required String clientId,
    required Uint8List? webBytes,
  }) async {
    final extension = lessonAudioExtensionForPath(recordingPath);
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
    return matchesRecognizedLessonEnglish(
          expectedEnglish,
          transcript,
          acceptedVariants: acceptedVariants,
          requireAllExpectedTokens: requireAllExpectedTokens,
        )
        ? LessonAttemptOutcome.good
        : LessonAttemptOutcome.retry;
  }

  @override
  void dispose() => _client.close();

  Future<void> _ensureInstallationAuthenticated() async {
    final client = _client;
    if (client is InstallationAuthenticatedClient) {
      await client.ensureAuthenticated();
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
      );
    } on http.ClientException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
      );
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    try {
      return await _client.send(request).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
      );
    } on http.ClientException {
      throw const LessonAttemptEvaluationException(
        'Chưa kết nối được máy chủ. Con thử lại sau nhé.',
        backendUnavailable: true,
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

/// Performs the encouraging local pass/fail check used after an on-device
/// recognizer produces an English transcript for a listening lesson.
///
/// Authored targets which explicitly require every token (notably
/// Alphabet/ABC) stay strict. Normal speaking exercises accept a small ASR or
/// pronunciation miss so children are encouraged to continue, while silence,
/// one-word fragments and clearly different answers still fail.
bool matchesRecognizedLessonEnglish(
  String expectedEnglish,
  String transcript, {
  Iterable<String> acceptedVariants = const <String>[],
  bool requireAllExpectedTokens = false,
}) {
  final strictMatch = const LessonRecognitionMatcher().matches(
    expectedEnglish: expectedEnglish,
    transcript: transcript,
    acceptedVariants: acceptedVariants,
    requireAllExpectedTokens: requireAllExpectedTokens,
  );
  if (strictMatch || requireAllExpectedTokens) {
    return strictMatch;
  }

  final actual = _normalizeLessonEnglish(transcript);
  if (actual.isEmpty) {
    return false;
  }
  final targets = <String>{expectedEnglish, ...acceptedVariants};
  return targets.any((target) {
    final expected = _normalizeLessonEnglish(target);
    return _matchesEncouragingLessonEnglish(expected, actual);
  });
}

bool _matchesEncouragingLessonEnglish(String expected, String actual) {
  if (expected.isEmpty || actual.isEmpty) {
    return false;
  }
  if (expected == actual) {
    return true;
  }

  final expectedWords = expected.split(' ');
  final actualWords = actual.split(' ');

  // A short isolated word can change meaning completely (left/right,
  // shirt/short), so only authored exact variants may pass one-word targets.
  if (expectedWords.length == 1) {
    return false;
  }

  if (actualWords.length < expectedWords.length - 1 ||
      actualWords.length > expectedWords.length + 2) {
    return false;
  }

  if (_containsContiguousWords(actualWords, expectedWords)) {
    return true;
  }

  final longest = math.max(expected.length, actual.length);
  final similarity = 1 - (_levenshteinDistance(expected, actual) / longest);
  final exactWordsInOrder = _longestCommonWordSubsequence(
    expectedWords,
    actualWords,
  );

  if (expectedWords.length == 2) {
    return exactWordsInOrder >= 1 && similarity >= 0.78;
  }

  // For normal phrases, tolerate one omitted or mistranscribed word. The
  // similarity floor prevents a sentence sharing only common filler words
  // from being accepted.
  return exactWordsInOrder >= expectedWords.length - 1 && similarity >= 0.66;
}

int _longestCommonWordSubsequence(List<String> left, List<String> right) {
  var previous = List<int>.filled(right.length + 1, 0);
  for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    final current = List<int>.filled(right.length + 1, 0);
    for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      if (left[leftIndex - 1] == right[rightIndex - 1]) {
        current[rightIndex] = previous[rightIndex - 1] + 1;
      } else {
        current[rightIndex] = math.max(
          current[rightIndex - 1],
          previous[rightIndex],
        );
      }
    }
    previous = current;
  }
  return previous.last;
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
  const LessonAttemptEvaluationException(
    this.message, {
    this.backendUnavailable = false,
  });

  final String message;
  final bool backendUnavailable;

  @override
  String toString() => message;
}
