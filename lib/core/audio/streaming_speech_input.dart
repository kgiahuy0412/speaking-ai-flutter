import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

import 'audio_input.dart';

const _incompleteVietnameseEndings = <String>{
  'ba',
  'bố',
  'con',
  'cô',
  'là',
  'mà',
  'mẹ',
  'muốn',
  'nên',
  'rồi',
  'sẽ',
  'thì',
  'và',
  'đang',
  'đã',
};

String preferCompleteVietnameseTranscript({
  required String partialText,
  required String finalText,
}) {
  final partial = partialText.trim().replaceAll(RegExp(r'\s+'), ' ');
  final completed = finalText.trim().replaceAll(RegExp(r'\s+'), ' ');

  if (partial.isEmpty) {
    return completed;
  }
  if (completed.isEmpty) {
    return partial;
  }

  final partialTokens = partial.toLowerCase().split(' ');
  final finalTokens = completed.toLowerCase().split(' ');
  if (partialTokens.length < finalTokens.length + 2 ||
      !_incompleteVietnameseEndings.contains(finalTokens.last)) {
    return completed;
  }

  final comparedLength = finalTokens.length;
  var matchingPrefixTokens = 0;
  while (matchingPrefixTokens < comparedLength &&
      partialTokens[matchingPrefixTokens] ==
          finalTokens[matchingPrefixTokens]) {
    matchingPrefixTokens += 1;
  }
  final prefixAgreement = matchingPrefixTokens / comparedLength;

  return prefixAgreement >= 0.8 ? partial : completed;
}

class StreamingSpeechCapture {
  const StreamingSpeechCapture({
    required this.sourceText,
    required this.duration,
    required this.inputLabel,
    required this.confidence,
    required this.firstResultMs,
    required this.finalAfterStopMs,
    this.asrMode = 'android_streaming',
    this.isBluetoothInput = false,
    this.initialNoiseRms,
    this.realtimeSessionCreateMs,
    this.realtimeWebSocketConnectMs,
    this.realtimeWebSocketOpenAfterRecordingMs,
    this.realtimeChunkDurationMs,
    this.workerAsrPilotRttMs,
    this.workerAsrPilotAsrMs,
    this.workerAsrPilotAudioBytes,
    this.extraBenchmark,
    this.recordedAudio,
    this.alternatives = const <String>[],
  });

  final String sourceText;
  final Duration duration;
  final String inputLabel;
  final double? confidence;
  final int? firstResultMs;
  final int finalAfterStopMs;
  final String asrMode;
  final bool isBluetoothInput;
  final double? initialNoiseRms;
  final int? realtimeSessionCreateMs;
  final int? realtimeWebSocketConnectMs;
  final int? realtimeWebSocketOpenAfterRecordingMs;
  final int? realtimeChunkDurationMs;
  final int? workerAsrPilotRttMs;
  final int? workerAsrPilotAsrMs;
  final int? workerAsrPilotAudioBytes;
  final Map<String, dynamic>? extraBenchmark;

  /// Other transcripts returned by the recognizer, ordered by confidence.
  ///
  /// Android can hear a wake phrase such as "Hey Pico" as "hay bi co" in
  /// the first result while keeping the intended phrase in a later result.
  final List<String> alternatives;

  /// Original microphone recording, when the platform recognizer exposes it.
  /// It is archived only after the conversation response has returned.
  final AudioCapture? recordedAudio;
}

abstract interface class StreamingSpeechInput {
  String get label;
  Stream<double> get amplitudeDbfs;
  Stream<void> get completed;
  Stream<String> get partialText;

  Future<bool> checkAvailability();
  Future<void> start();
  Future<StreamingSpeechCapture> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Optional fast profile for short navigation commands.
///
/// Conversation recording continues to use [StreamingSpeechInput.start] so a
/// child's natural pauses do not end a normal speaking turn too early.
abstract interface class CommandStreamingSpeechInput {
  Future<void> startCommandRecognition();
}

/// Optional stream of all transcripts produced for the same utterance.
///
/// Normal conversation UI keeps using [StreamingSpeechInput.partialText].
/// Voice commands can inspect these alternatives without replacing or
/// interfering with that existing speaking flow.
abstract interface class AlternativeTranscriptStreamingSpeechInput {
  Stream<List<String>> get transcriptAlternatives;
}

/// Android 13+ can feed an already recorded PCM WAV to SpeechRecognizer.
/// Recording once avoids competing microphone consumers and guarantees that
/// the exact utterance sent to recognition can also be archived for admin.
abstract interface class RecordedAudioStreamingSpeechInput {
  Future<bool> supportsRecordedAudioRecognition();

  Future<StreamingSpeechCapture> recognizeRecordedAudio(AudioCapture capture);
}

class AndroidStreamingSpeechInput
    implements
        StreamingSpeechInput,
        RecordedAudioStreamingSpeechInput,
        CommandStreamingSpeechInput,
        AlternativeTranscriptStreamingSpeechInput {
  AndroidStreamingSpeechInput({
    MethodChannel methodChannel = const MethodChannel('ailingo_speech'),
    EventChannel eventChannel = const EventChannel('ailingo_speech/events'),
  }) : _methodChannel = methodChannel {
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleChannelError,
    );
  }

  final MethodChannel _methodChannel;
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _transcriptAlternativesController =
      StreamController<List<String>>.broadcast();

  late final StreamSubscription<dynamic> _eventSubscription;
  Completer<String>? _resultCompleter;
  Completer<void>? _readyCompleter;
  DateTime? _startedAt;
  DateTime? _firstResultAt;
  DateTime? _resultAt;
  DateTime? _latestTextUpdatedAt;
  String _latestText = '';
  List<String> _latestAlternatives = const <String>[];
  double? _confidence;
  String? _recordedAudioPath;
  String? _recordedAudioMimeType;
  int? _recordedAudioByteLength;
  int? _recordedAudioSampleRate;
  bool _active = false;
  bool _audioFocusActive = false;
  AudioSession? _activeAudioSession;
  bool _disposed = false;
  bool? _availabilityCache;

  @override
  String get label => 'Chế độ tiêu chuẩn';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Stream<List<String>> get transcriptAlternatives =>
      _transcriptAlternativesController.stream;

  @override
  Future<bool> checkAvailability() async {
    final cached = _availabilityCache;
    if (cached != null) {
      return cached;
    }
    try {
      final available =
          await _methodChannel.invokeMethod<bool>('speech.isAvailable') ??
          false;
      if (available) {
        _availabilityCache = true;
      }
      return available;
    } on MissingPluginException {
      return false;
    }
  }

  /// Creates the platform recognizer without opening the microphone.
  ///
  /// Android's first SpeechRecognizer construction can be noticeably slower
  /// than subsequent starts. Running this after the first Flutter frame keeps
  /// that cold-start work out of the child's first recording attempt.
  Future<bool> prewarm() async {
    if (_disposed) {
      return false;
    }
    try {
      final prepared =
          await _methodChannel.invokeMethod<bool>('speech.prepare') ?? false;
      if (prepared) {
        _availabilityCache = true;
      }
      return prepared;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> supportsRecordedAudioRecognition() async {
    if (_disposed) {
      return false;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'speech.supportsAudioSource',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<StreamingSpeechCapture> recognizeRecordedAudio(
    AudioCapture capture,
  ) async {
    if (_active) {
      await cancel();
    }
    if (!await supportsRecordedAudioRecognition()) {
      throw const StreamingSpeechInputException(
        'Thiết bị chưa hỗ trợ nhận diện từ bản ghi âm.',
        code: 'RECORDED_AUDIO_RECOGNITION_UNAVAILABLE',
      );
    }

    _latestText = '';
    _latestAlternatives = const <String>[];
    _confidence = null;
    _firstResultAt = null;
    _resultAt = null;
    _latestTextUpdatedAt = null;
    _recordedAudioPath = capture.filePath;
    _recordedAudioMimeType = capture.mimeType;
    _recordedAudioByteLength = capture.dataBytes?.length;
    _recordedAudioSampleRate = capture.recordingSampleRate;
    final resultCompleter = Completer<String>();
    _resultCompleter = resultCompleter;
    unawaited(
      resultCompleter.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    final recognitionStartedAt = DateTime.now();
    _startedAt = recognitionStartedAt;
    _active = true;

    try {
      await _methodChannel.invokeMethod<void>('speech.recognizeFile', {
        'path': capture.filePath,
        'sampleRate': capture.recordingSampleRate ?? 16000,
      });
      await readyCompleter.future.timeout(const Duration(seconds: 2));
      final sourceText = await resultCompleter.future.timeout(
        const Duration(seconds: 12),
      );
      if (sourceText.trim().isEmpty) {
        throw const StreamingSpeechInputException(
          'Không nghe rõ câu nói. Hãy nói lại gần micro hơn.',
          code: 'RECORDED_AUDIO_UNCLEAR',
        );
      }
      return StreamingSpeechCapture(
        sourceText: sourceText.trim(),
        duration: capture.duration,
        inputLabel: label,
        confidence: _confidence,
        firstResultMs: _firstResultAt
            ?.difference(recognitionStartedAt)
            .inMilliseconds,
        finalAfterStopMs: math
            .max(
              0,
              (_resultAt ?? DateTime.now())
                  .difference(recognitionStartedAt)
                  .inMilliseconds,
            )
            .toInt(),
        alternatives: List<String>.unmodifiable(_latestAlternatives),
        recordedAudio: capture,
      );
    } on TimeoutException {
      await cancel();
      throw const StreamingSpeechInputException(
        'Nhận diện bản ghi âm mất quá nhiều thời gian.',
        code: 'RECORDED_AUDIO_RECOGNITION_TIMEOUT',
      );
    } on PlatformException catch (error) {
      _active = false;
      throw StreamingSpeechInputException(
        error.message ?? 'Không thể nhận diện bản ghi âm.',
        code: error.code,
      );
    } finally {
      if (identical(_readyCompleter, readyCompleter)) {
        _readyCompleter = null;
      }
    }
  }

  @override
  Future<void> start() => _start(commandMode: false);

  @override
  Future<void> startCommandRecognition() => _start(commandMode: true);

  Future<void> _start({required bool commandMode}) async {
    if (_active) {
      await cancel();
    }
    if (!await checkAvailability()) {
      throw const StreamingSpeechInputException(
        'Thiết bị chưa có dịch vụ nhận diện giọng nói Android.',
      );
    }

    _latestText = '';
    _latestAlternatives = const <String>[];
    _confidence = null;
    _firstResultAt = null;
    _resultAt = null;
    _latestTextUpdatedAt = null;
    _recordedAudioPath = null;
    _recordedAudioMimeType = null;
    _recordedAudioByteLength = null;
    _recordedAudioSampleRate = null;
    final resultCompleter = Completer<String>();
    _resultCompleter = resultCompleter;
    unawaited(
      resultCompleter.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _startedAt = null;
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    _active = true;

    try {
      await _activateAudioFocus();
      await _methodChannel.invokeMethod<void>('speech.start', {
        'commandMode': commandMode,
      });
      await readyCompleter.future.timeout(const Duration(seconds: 2));
      _startedAt = DateTime.now();
    } on TimeoutException {
      _active = false;
      await _methodChannel
          .invokeMethod<void>('speech.cancel')
          .catchError((Object _) {});
      await _releaseAudioFocus();
      throw const StreamingSpeechInputException(
        'Micro Android chưa sẵn sàng. Hãy thử lại sau một chút.',
        code: 'SPEECH_READY_TIMEOUT',
      );
    } on PlatformException catch (error) {
      _active = false;
      await _releaseAudioFocus();
      throw StreamingSpeechInputException(
        error.message ?? 'Không thể bắt đầu nhận diện giọng nói.',
        code: error.code,
      );
    } on StreamingSpeechInputException {
      _active = false;
      await _releaseAudioFocus();
      rethrow;
    } finally {
      if (identical(_readyCompleter, readyCompleter)) {
        _readyCompleter = null;
      }
    }
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    final startedAt = _startedAt;
    final completer = _resultCompleter;
    final stopRequestedAt = DateTime.now();

    if (startedAt == null || completer == null) {
      throw const StreamingSpeechInputException(
        'Không tìm thấy lượt nhận diện đang chạy.',
      );
    }

    if (_active) {
      await _methodChannel.invokeMethod<void>('speech.stop');
    }

    String sourceText;
    final partialAtStop = _stablePartialTranscript(
      minimumStableFor: const Duration(milliseconds: 350),
    );
    if (partialAtStop != null) {
      // A stable partial keeps stop responsive, but the Android final result is
      // often more accurate for softly spoken child speech. Give it a short,
      // bounded grace period before falling back to the partial transcript.
      try {
        sourceText = await completer.future.timeout(
          const Duration(milliseconds: 220),
        );
      } on TimeoutException {
        sourceText = partialAtStop;
        _resultAt = DateTime.now();
      }
    } else {
      try {
        sourceText = await completer.future.timeout(
          const Duration(milliseconds: 500),
        );
      } on TimeoutException {
        final usablePartial = _stablePartialTranscript(
          minimumStableFor: const Duration(milliseconds: 200),
        );
        if (usablePartial != null) {
          sourceText = usablePartial;
          _resultAt = DateTime.now();
        } else {
          sourceText = await completer.future.timeout(
            const Duration(milliseconds: 700),
            onTimeout: () => _latestText,
          );
        }
      }
    }
    _active = false;
    await _releaseAudioFocus();

    if (sourceText.trim().isEmpty) {
      throw const StreamingSpeechInputException(
        'Không nghe rõ câu nói. Hãy nói lại gần micro hơn.',
      );
    }

    final recordedAudioPath = _recordedAudioPath;
    final recordedAudioByteLength = _recordedAudioByteLength ?? 0;
    final recordedAudio =
        recordedAudioPath != null && recordedAudioByteLength > 44
        ? AudioCapture(
            filePath: recordedAudioPath,
            mimeType: _recordedAudioMimeType ?? 'audio/wav',
            duration: DateTime.now().difference(startedAt),
            inputLabel: label,
            isBluetoothInput: false,
            initialNoiseRms: null,
            recordingSampleRate: _recordedAudioSampleRate,
            streamedAudioBytes: recordedAudioByteLength - 44,
          )
        : null;
    return StreamingSpeechCapture(
      sourceText: sourceText.trim(),
      duration: DateTime.now().difference(startedAt),
      inputLabel: label,
      confidence: _confidence,
      firstResultMs: _firstResultAt?.difference(startedAt).inMilliseconds,
      finalAfterStopMs: math
          .max(
            0,
            (_resultAt ?? DateTime.now())
                .difference(stopRequestedAt)
                .inMilliseconds,
          )
          .toInt(),
      alternatives: List<String>.unmodifiable(_latestAlternatives),
      recordedAudio: recordedAudio,
    );
  }

  String? _stablePartialTranscript({required Duration minimumStableFor}) {
    final latestText = _latestText.trim();
    final latestTextUpdatedAt = _latestTextUpdatedAt;
    final stableFor = latestTextUpdatedAt == null
        ? Duration.zero
        : DateTime.now().difference(latestTextUpdatedAt);
    final hasEnoughSpeech =
        latestText.length >= 8 || latestText.split(RegExp(r'\s+')).length >= 2;
    return latestText.isNotEmpty &&
            hasEnoughSpeech &&
            stableFor >= minimumStableFor
        ? latestText
        : null;
  }

  @override
  Future<void> cancel() async {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(
        const StreamingSpeechInputException(
          'Đã dừng trước khi micro sẵn sàng.',
          code: 'SPEECH_START_CANCELLED',
        ),
      );
    }
    _readyCompleter = null;
    if (_active) {
      await _methodChannel.invokeMethod<void>('speech.cancel');
    }
    await _releaseAudioFocus();
    _active = false;
    _startedAt = null;
    _latestText = '';
    _latestAlternatives = const <String>[];
    _latestTextUpdatedAt = null;
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete('');
    }
    _resultCompleter = null;
  }

  Future<void> _activateAudioFocus() async {
    if (_audioFocusActive) {
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      final granted = await session.setActive(true);
      if (!granted) {
        throw const StreamingSpeechInputException(
          'Micro đang được cuộc gọi hoặc ứng dụng khác sử dụng.',
          code: 'AUDIO_FOCUS_UNAVAILABLE',
        );
      }
      _activeAudioSession = session;
      _audioFocusActive = true;
    } on MissingPluginException {
      // Unit tests do not install the native audio-session channel. The real
      // Android runtime always supplies it through the plugin registration.
    }
  }

  Future<void> _releaseAudioFocus() async {
    if (!_audioFocusActive) {
      return;
    }
    final session = _activeAudioSession;
    _activeAudioSession = null;
    _audioFocusActive = false;
    await session?.setActive(false).catchError((Object _) => false);
  }

  void _handleEvent(dynamic event) {
    if (_disposed || event is! Map<dynamic, dynamic>) {
      return;
    }

    final type = event['type'];
    if (type == 'speech.ready') {
      final readyCompleter = _readyCompleter;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
      return;
    }
    if (type == 'speech.rms') {
      final rmsDb = (event['rmsDb'] as num?)?.toDouble() ?? -2;
      final level = ((rmsDb + 2) / 12).clamp(0.0, 1.0);
      _amplitudeController.add(-60 + (level * 60));
      return;
    }

    if (type == 'speech.partial' || type == 'speech.final') {
      _readRecordedAudioMetadata(event);
      final alternatives = _readTranscriptAlternatives(event);
      final text = event['text'];
      if (text is String && text.trim().isNotEmpty) {
        final nextText = type == 'speech.final'
            ? preferCompleteVietnameseTranscript(
                partialText: _latestText,
                finalText: text,
              )
            : text.trim();
        final changed = nextText != _latestText;
        _latestText = nextText;
        if (changed || type == 'speech.final') {
          _latestTextUpdatedAt = DateTime.now();
        }
        _firstResultAt ??= DateTime.now();
        if (changed && type == 'speech.partial') {
          _partialTextController.add(nextText);
        }
      }
      if (alternatives.isNotEmpty) {
        _latestAlternatives = alternatives;
        _transcriptAlternativesController.add(alternatives);
      }
    }

    if (type == 'speech.final') {
      final confidence = (event['confidence'] as num?)?.toDouble();
      final finalText = event['text'];
      final finalWasPreserved =
          finalText is String && _latestText.trim() == finalText.trim();
      _confidence = finalWasPreserved && confidence != null && confidence >= 0
          ? confidence
          : null;
      _resultAt = DateTime.now();
      _active = false;
      unawaited(_releaseAudioFocus());
      _completeResult(_latestText);
      _completedController.add(null);
      return;
    }

    if (type == 'speech.error') {
      _readRecordedAudioMetadata(event);
      _active = false;
      unawaited(_releaseAudioFocus());
      _resultAt = DateTime.now();
      final message =
          event['message'] as String? ?? 'Không thể nhận diện giọng nói.';
      final readyCompleter = _readyCompleter;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.completeError(
          StreamingSpeechInputException(
            message,
            code: 'ANDROID_SPEECH_${event['code'] ?? 'ERROR'}',
          ),
        );
      }
      final completer = _resultCompleter;
      if (_latestText.isNotEmpty) {
        _completeResult(_latestText);
      } else if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StreamingSpeechInputException(
            message,
            code: 'ANDROID_SPEECH_${event['code'] ?? 'ERROR'}',
          ),
        );
      }
      _completedController.add(null);
    }
  }

  List<String> _readTranscriptAlternatives(Map<dynamic, dynamic> event) {
    final rawAlternatives = event['alternatives'];
    final candidates = <String>[];
    if (rawAlternatives is Iterable<dynamic>) {
      for (final value in rawAlternatives) {
        if (value is! String) {
          continue;
        }
        final candidate = value.trim();
        if (candidate.isNotEmpty && !candidates.contains(candidate)) {
          candidates.add(candidate);
        }
      }
    }
    final primaryText = event['text'];
    if (primaryText is String && primaryText.trim().isNotEmpty) {
      final candidate = primaryText.trim();
      if (!candidates.contains(candidate)) {
        candidates.insert(0, candidate);
      }
    }
    return List<String>.unmodifiable(candidates);
  }

  void _readRecordedAudioMetadata(Map<dynamic, dynamic> event) {
    final path = event['audioPath'];
    final mimeType = event['audioMimeType'];
    final byteLength = (event['audioByteLength'] as num?)?.toInt();
    final sampleRate = (event['audioSampleRate'] as num?)?.toInt();
    if (path is String && path.trim().isNotEmpty && byteLength != null) {
      _recordedAudioPath = path;
      _recordedAudioMimeType = mimeType is String ? mimeType : 'audio/wav';
      _recordedAudioByteLength = byteLength;
      _recordedAudioSampleRate = sampleRate;
    }
  }

  void _handleChannelError(Object error) {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(
        StreamingSpeechInputException(error.toString()),
      );
    }
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StreamingSpeechInputException(error.toString()));
    }
    if (!_disposed) {
      _completedController.add(null);
    }
  }

  void _completeResult(String text) {
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(text);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(
        const StreamingSpeechInputException(
          'Bộ nhận dạng đã được đóng.',
          code: 'SPEECH_DISPOSED',
        ),
      );
    }
    _readyCompleter = null;
    if (_active) {
      await _methodChannel.invokeMethod<void>('speech.cancel');
    }
    await _releaseAudioFocus();
    await _eventSubscription.cancel();
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
    await _transcriptAlternativesController.close();
  }
}

class StreamingSpeechInputException implements Exception {
  const StreamingSpeechInputException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
