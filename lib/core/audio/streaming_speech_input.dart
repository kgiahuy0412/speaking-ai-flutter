import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_input.dart';
import 'hfp_audio_control.dart';

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
  /// Android can hear a wake phrase such as "Hey HOMI" as a close phonetic
  /// variant in
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

/// Marks a native recognizer that acquires and releases its own short HFP
/// route lease for every recognition turn.
///
/// A controller using this input must not open a second lease around start(),
/// otherwise its route flag becomes stale as soon as the recognizer stops.
abstract interface class HfpRouteOwningStreamingSpeechInput {}

/// Lets a hands-free session keep one verified HFP route across consecutive
/// recognition turns.
///
/// The caller must still verify that the independent BLE MAIN transport stays
/// connected after the route opens. If BLE/HFP coexistence is not stable on a
/// device, it must end this session and fall back to utterance-scoped leases.
abstract interface class ContinuousHfpSessionStreamingSpeechInput {
  bool get isContinuousHfpSessionActive;

  Future<void> beginContinuousHfpSession();
  Future<void> endContinuousHfpSession();
}

/// Optional signal emitted as soon as the native audio engine detects speech.
///
/// A partial transcript can arrive noticeably later (especially on an HFP
/// route), so navigation must not use transcript delivery as its only proof
/// that the child has started answering.
abstract interface class SpeechActivityStreamingSpeechInput {
  Stream<void> get speechStarted;
}

/// Optional fast profile for short navigation commands.
///
/// Conversation recording continues to use [StreamingSpeechInput.start] so a
/// child's natural pauses do not end a normal speaking turn too early.
abstract interface class CommandStreamingSpeechInput {
  Future<void> startCommandRecognition();
}

enum NativeSpeechAudioSource {
  builtInMic('builtInMic'),
  hfp('hfp');

  const NativeSpeechAudioSource(this.channelValue);

  final String channelValue;
}

/// Lets the caller pin the next native recognition turn to a verified input.
///
/// This is intentionally one-shot: a physical H20 MAIN press can force the
/// iPhone microphone without permanently overriding a later, explicitly
/// selected HFP route.
abstract interface class NativeSpeechAudioSourceControl {
  void useNativeSpeechAudioSourceOnce(NativeSpeechAudioSource source);
}

class NativeSpeechDiagnostic {
  const NativeSpeechDiagnostic({
    required this.stage,
    required this.occurredAt,
    this.audioSource,
    this.audioRoute,
    this.code,
    this.message,
    this.turnId,
    this.sequence,
    this.elapsedMs,
    this.caller,
  });

  final String stage;
  final DateTime occurredAt;
  final String? audioSource;
  final String? audioRoute;
  final String? code;
  final String? message;
  final String? turnId;
  final int? sequence;
  final int? elapsedMs;
  final String? caller;

  bool get isError => stage == 'error' || code != null;
}

/// Exposes the real microphone hand-off stages for on-device diagnostics.
abstract interface class NativeSpeechDiagnostics {
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic;
  Stream<NativeSpeechDiagnostic> get nativeSpeechDiagnostics;

  void reportNativeSpeechStage(
    String stage, {
    String? audioSource,
    String? audioRoute,
    String? code,
    String? message,
    String? turnId,
    int? sequence,
    int? elapsedMs,
    String? caller,
    DateTime? occurredAt,
  });
}

/// Optional stream of all transcripts produced for the same utterance.
///
/// Normal conversation UI keeps using [StreamingSpeechInput.partialText].
/// Voice commands can inspect these alternatives without replacing or
/// interfering with that existing speaking flow.
abstract interface class AlternativeTranscriptStreamingSpeechInput {
  Stream<List<String>> get transcriptAlternatives;
}

/// Marks a native recognizer whose microphone turn may safely fall back to the
/// existing Cloudflare/Batch path when Apple Speech is unavailable.
abstract interface class BatchFallbackCapableNativeSpeechInput {}

/// Exposes the private, local-only safety recording after native recognition
/// fails. Successful native turns never expose this file and therefore never
/// upload their audio merely for archiving.
abstract interface class NativeSpeechFallbackAudioProvider {
  AudioCapture? takeFallbackAudioCapture();
}

/// Recognizes a complete safety recording without opening another microphone
/// turn. This lets MAIN recover the same utterance when native iOS recognition
/// fails after audio capture has already begun.
abstract interface class RecordedAudioFallbackSpeechInput {
  Future<StreamingSpeechCapture> recognizeRecordedAudio(
    AudioCapture capture, {
    String? fallbackReason,
  });
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
        SpeechActivityStreamingSpeechInput,
        RecordedAudioStreamingSpeechInput,
        CommandStreamingSpeechInput,
        AlternativeTranscriptStreamingSpeechInput,
        NativeSpeechFallbackAudioProvider,
        NativeSpeechAudioSourceControl,
        NativeSpeechDiagnostics {
  AndroidStreamingSpeechInput({
    MethodChannel methodChannel = const MethodChannel('ailingo_speech'),
    EventChannel eventChannel = const EventChannel('ailingo_speech/events'),
    Stream<dynamic>? eventStream,
    String platformName = 'Android',
    String inputLabel = 'Chế độ tiêu chuẩn',
    String asrMode = 'android_streaming',
    bool preferOnDevice = false,
    bool failOnRuntimeError = false,
    Duration readyTimeout = const Duration(seconds: 2),
    Duration nativeCommandTimeout = const Duration(seconds: 2),
  }) : _methodChannel = methodChannel,
       _platformName = platformName,
       _inputLabel = inputLabel,
       _asrMode = asrMode,
       _preferOnDevice = preferOnDevice,
       _failOnRuntimeError = failOnRuntimeError,
       _readyTimeout = readyTimeout,
       _nativeCommandTimeout = nativeCommandTimeout {
    _eventSubscription = (eventStream ?? eventChannel.receiveBroadcastStream())
        .listen(_handleEvent, onError: _handleChannelError);
  }

  final MethodChannel _methodChannel;
  final String _platformName;
  final String _inputLabel;
  final String _asrMode;
  final bool _preferOnDevice;
  final bool _failOnRuntimeError;
  final Duration _readyTimeout;
  final Duration _nativeCommandTimeout;
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _speechStartedController =
      StreamController<void>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _transcriptAlternativesController =
      StreamController<List<String>>.broadcast();
  final StreamController<NativeSpeechDiagnostic> _nativeDiagnosticsController =
      StreamController<NativeSpeechDiagnostic>.broadcast();

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
  bool _recordedAudioBluetoothInput = false;
  String? _nativeSpeechEngine;
  String? _nativeSpeechLocale;
  String? _nativeAudioRoute;
  bool? _nativeSpeechOnDevice;
  int? _nativeListeningReadyMs;
  int? _nativeFirstPartialMs;
  int? _nativeFinalTranscriptMs;
  bool _active = false;
  bool _disposed = false;
  bool? _availabilityCache;
  NativeSpeechAudioSource? _nextAudioSource;
  NativeSpeechAudioSource? _activeAudioSource;
  NativeSpeechDiagnostic? _nativeDiagnostic;

  @override
  String get label => _inputLabel;

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get speechStarted => _speechStartedController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Stream<List<String>> get transcriptAlternatives =>
      _transcriptAlternativesController.stream;

  @override
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic => _nativeDiagnostic;

  @override
  Stream<NativeSpeechDiagnostic> get nativeSpeechDiagnostics =>
      _nativeDiagnosticsController.stream;

  @override
  void useNativeSpeechAudioSourceOnce(NativeSpeechAudioSource source) {
    _nextAudioSource = source;
  }

  NativeSpeechAudioSource takeNativeSpeechAudioSource(
    NativeSpeechAudioSource fallback,
  ) {
    final selected = _nextAudioSource ?? fallback;
    _nextAudioSource = null;
    return selected;
  }

  @override
  void reportNativeSpeechStage(
    String stage, {
    String? audioSource,
    String? audioRoute,
    String? code,
    String? message,
    String? turnId,
    int? sequence,
    int? elapsedMs,
    String? caller,
    DateTime? occurredAt,
  }) {
    if (_disposed) return;
    final diagnostic = NativeSpeechDiagnostic(
      stage: stage,
      occurredAt: occurredAt ?? DateTime.now(),
      audioSource: audioSource ?? _activeAudioSource?.channelValue,
      audioRoute: audioRoute,
      code: code,
      message: message,
      turnId: turnId,
      sequence: sequence,
      elapsedMs: elapsedMs,
      caller: caller,
    );
    _nativeDiagnostic = diagnostic;
    _nativeDiagnosticsController.add(diagnostic);
    if (_platformName == 'iOS') {
      debugPrint(
        'HOMI Apple Speech [$stage] source=${diagnostic.audioSource ?? '-'} '
        'route=${diagnostic.audioRoute ?? '-'} code=${code ?? '-'} '
        '${message ?? ''}',
      );
    }
  }

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
  Future<void> start() => startWithNativeAudioSource(
    commandMode: false,
    audioSource: takeNativeSpeechAudioSource(
      NativeSpeechAudioSource.builtInMic,
    ),
  );

  @override
  Future<void> startCommandRecognition() => startWithNativeAudioSource(
    commandMode: true,
    audioSource: takeNativeSpeechAudioSource(
      NativeSpeechAudioSource.builtInMic,
    ),
  );

  Future<void> startWithNativeAudioSource({
    required bool commandMode,
    required NativeSpeechAudioSource audioSource,
    String? localeIdentifier,
  }) async {
    if (_active) {
      await cancel();
    }
    if (!await checkAvailability()) {
      throw StreamingSpeechInputException(
        'Thiết bị chưa có dịch vụ nhận diện giọng nói $_platformName.',
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
    _recordedAudioBluetoothInput = false;
    _resetNativeTelemetry();
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
    _activeAudioSource = audioSource;
    try {
      await _methodChannel
          .invokeMethod<void>('speech.start', {
            'commandMode': commandMode,
            'preferOnDevice': _preferOnDevice,
            'audioSource': audioSource.channelValue,
            'locale': ?localeIdentifier,
          })
          .timeout(_nativeCommandTimeout);
      await readyCompleter.future.timeout(_readyTimeout);
      _startedAt = DateTime.now();
    } on TimeoutException {
      _active = false;
      await _cancelNativeRecognitionBounded();
      reportNativeSpeechStage(
        'error',
        code: 'SPEECH_READY_TIMEOUT',
        message: 'Micro $_platformName chưa phát speech.ready đúng hạn.',
      );
      throw StreamingSpeechInputException(
        'Micro $_platformName chưa sẵn sàng. Hãy thử lại sau một chút.',
        code: 'SPEECH_READY_TIMEOUT',
      );
    } on PlatformException catch (error) {
      _active = false;
      reportNativeSpeechStage(
        'error',
        code: error.code,
        message: error.message,
      );
      throw StreamingSpeechInputException(
        error.message ?? 'Không thể bắt đầu nhận diện giọng nói.',
        code: error.code,
      );
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
      asrMode: _asrMode,
      isBluetoothInput: _recordedAudioBluetoothInput,
      extraBenchmark: _nativeBenchmark,
      recordedAudio: recordedAudio,
    );
  }

  Map<String, dynamic>? get _nativeBenchmark {
    final values = <String, dynamic>{
      'nativeSpeechPlatform': _platformName.toLowerCase(),
      if (_nativeSpeechEngine != null)
        'nativeSpeechEngine': _nativeSpeechEngine,
      if (_nativeSpeechLocale != null)
        'nativeSpeechLocale': _nativeSpeechLocale,
      if (_nativeSpeechOnDevice != null)
        'nativeSpeechOnDevice': _nativeSpeechOnDevice,
      if (_nativeAudioRoute != null)
        'nativeSpeechAudioRoute': _nativeAudioRoute,
      if (_nativeListeningReadyMs != null)
        'nativeSpeechListeningReadyMs': _nativeListeningReadyMs,
      if (_nativeFirstPartialMs != null)
        'nativeSpeechFirstPartialMs': _nativeFirstPartialMs,
      if (_nativeFinalTranscriptMs != null)
        'nativeSpeechFinalTranscriptMs': _nativeFinalTranscriptMs,
    };
    return values.length == 1 && _platformName == 'Android' ? null : values;
  }

  void _resetNativeTelemetry() {
    _nativeSpeechEngine = null;
    _nativeSpeechLocale = null;
    _nativeAudioRoute = null;
    _nativeSpeechOnDevice = null;
    _nativeListeningReadyMs = null;
    _nativeFirstPartialMs = null;
    _nativeFinalTranscriptMs = null;
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
    final shouldCancelNative = _active || readyCompleter != null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(
        const StreamingSpeechInputException(
          'Đã dừng trước khi micro sẵn sàng.',
          code: 'SPEECH_START_CANCELLED',
        ),
      );
    }
    _readyCompleter = null;
    _active = false;
    if (shouldCancelNative) {
      await _cancelNativeRecognitionBounded();
    }
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

  Future<void> _cancelNativeRecognitionBounded() async {
    try {
      await _methodChannel
          .invokeMethod<void>('speech.cancel')
          .timeout(_nativeCommandTimeout);
    } catch (_) {
      // Cancellation is lifecycle cleanup. A native channel that is already
      // stuck must not keep MAIN, a lesson route, or app disposal waiting.
    }
  }

  void _handleEvent(dynamic event) {
    if (_disposed || event is! Map<dynamic, dynamic>) {
      return;
    }

    final type = event['type'];
    if (type == 'speech.stage') {
      reportNativeSpeechStage(
        '${event['stage'] ?? 'unknown'}',
        audioSource: event['audioSource'] as String?,
        audioRoute: event['audioRoute'] as String?,
        code: event['code'] as String?,
        message: event['message'] as String?,
        turnId: event['turnId'] as String?,
        sequence: (event['sequence'] as num?)?.toInt(),
        elapsedMs: (event['elapsedMs'] as num?)?.toInt(),
        caller: event['caller'] as String?,
        occurredAt: (event['eventEpochMs'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (event['eventEpochMs'] as num).toInt(),
              ),
      );
      return;
    }
    if (type == 'speech.ready') {
      _readNativeTelemetry(event);
      reportNativeSpeechStage(
        'speech.ready',
        audioSource: event['audioSource'] as String?,
        audioRoute: event['audioRoute'] as String?,
      );
      final readyCompleter = _readyCompleter;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
      return;
    }
    if (type == 'speech.begin') {
      reportNativeSpeechStage(
        'speech.begin',
        audioSource: event['audioSource'] as String?,
        audioRoute: event['audioRoute'] as String?,
      );
      _speechStartedController.add(null);
      return;
    }
    if (type == 'speech.rms') {
      final rmsDb = (event['rmsDb'] as num?)?.toDouble() ?? -2;
      if (_platformName == 'iOS') {
        // IOSSpeechRecognizerBridge already reports conventional dBFS
        // (-60...0). Applying Android's positive RMS conversion flattened
        // almost every iOS sample to -60 and hid real H20 microphone activity.
        _amplitudeController.add(rmsDb.clamp(-60.0, 0.0));
      } else {
        final level = ((rmsDb + 2) / 12).clamp(0.0, 1.0);
        _amplitudeController.add(-60 + (level * 60));
      }
      return;
    }

    if (type == 'speech.partial' || type == 'speech.final') {
      _readNativeTelemetry(event);
      _readRecordedAudioMetadata(event);
      final alternatives = _readTranscriptAlternatives(event);
      final text = event['text'];
      if (text is String && text.trim().isNotEmpty) {
        final isFirstTranscript = _firstResultAt == null;
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
        if (isFirstTranscript) {
          reportNativeSpeechStage(
            type == 'speech.final'
                ? 'first_final_transcript'
                : 'first_partial_transcript',
            audioSource: event['audioSource'] as String?,
            audioRoute: event['audioRoute'] as String?,
            message: nextText,
          );
        }
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
      _completeResult(_latestText);
      _completedController.add(null);
      return;
    }

    if (type == 'speech.error') {
      _readNativeTelemetry(event);
      _readRecordedAudioMetadata(event);
      _active = false;
      _resultAt = DateTime.now();
      final message =
          event['message'] as String? ?? 'Không thể nhận diện giọng nói.';
      reportNativeSpeechStage(
        'error',
        audioSource: event['audioSource'] as String?,
        audioRoute: event['audioRoute'] as String?,
        code: '${event['code'] ?? 'ERROR'}',
        message: message,
      );
      final readyCompleter = _readyCompleter;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.completeError(
          StreamingSpeechInputException(
            message,
            code:
                '${_platformName.toUpperCase()}_SPEECH_${event['code'] ?? 'ERROR'}',
          ),
        );
      }
      final completer = _resultCompleter;
      if (_latestText.isNotEmpty && !_failOnRuntimeError) {
        _completeResult(_latestText);
      } else if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StreamingSpeechInputException(
            message,
            code:
                '${_platformName.toUpperCase()}_SPEECH_${event['code'] ?? 'ERROR'}',
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
      _recordedAudioBluetoothInput = event['isBluetoothInput'] == true;
    }
  }

  void _readNativeTelemetry(Map<dynamic, dynamic> event) {
    _nativeSpeechEngine = event['engine'] as String? ?? _nativeSpeechEngine;
    _nativeSpeechLocale = event['locale'] as String? ?? _nativeSpeechLocale;
    _nativeAudioRoute = event['audioRoute'] as String? ?? _nativeAudioRoute;
    _nativeSpeechOnDevice = event['onDevice'] as bool? ?? _nativeSpeechOnDevice;
    _nativeListeningReadyMs =
        (event['listeningReadyMs'] as num?)?.toInt() ?? _nativeListeningReadyMs;
    _nativeFirstPartialMs =
        (event['firstPartialMs'] as num?)?.toInt() ?? _nativeFirstPartialMs;
    _nativeFinalTranscriptMs =
        (event['finalTranscriptMs'] as num?)?.toInt() ??
        _nativeFinalTranscriptMs;
  }

  @override
  AudioCapture? takeFallbackAudioCapture() {
    final path = _recordedAudioPath;
    final byteLength = _recordedAudioByteLength ?? 0;
    final startedAt = _startedAt;
    if (path == null || byteLength <= 44 || startedAt == null) {
      return null;
    }
    final capture = AudioCapture(
      filePath: path,
      mimeType: _recordedAudioMimeType ?? 'audio/wav',
      duration: DateTime.now().difference(startedAt),
      inputLabel: label,
      isBluetoothInput: _recordedAudioBluetoothInput,
      initialNoiseRms: null,
      recordingSampleRate: _recordedAudioSampleRate,
      streamedAudioBytes: byteLength - 44,
    );
    _recordedAudioPath = null;
    _recordedAudioMimeType = null;
    _recordedAudioByteLength = null;
    _recordedAudioSampleRate = null;
    _recordedAudioBluetoothInput = false;
    return capture;
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
    final shouldCancelNative = _active;
    _active = false;
    if (shouldCancelNative) {
      await _cancelNativeRecognitionBounded();
    }
    await _eventSubscription.cancel();
    await _amplitudeController.close();
    await _speechStartedController.close();
    await _completedController.close();
    await _partialTextController.close();
    await _transcriptAlternativesController.close();
    await _nativeDiagnosticsController.close();
  }
}

class IOSStreamingSpeechInput extends AndroidStreamingSpeechInput
    implements
        HfpRouteOwningStreamingSpeechInput,
        ContinuousHfpSessionStreamingSpeechInput {
  IOSStreamingSpeechInput({
    super.methodChannel = const MethodChannel('ailingo_speech'),
    super.eventChannel = const EventChannel('ailingo_speech/events'),
    super.eventStream,
    super.nativeCommandTimeout,
    HfpAudioControl? audioRouteControl,
  }) : _audioRouteControl = audioRouteControl,
       super(
         platformName: 'iOS',
         inputLabel: 'Apple Native Speech',
         // Keep the established backend contract while engine/platform detail
         // travels in benchmark metadata.
         asrMode: 'android_streaming',
         preferOnDevice: true,
         failOnRuntimeError: true,
         // Route confirmation may legitimately take about two seconds after
         // iOS changes from HFP to the built-in microphone. Do not let Dart
         // cancel the native start while AVAudioSession is still settling.
         readyTimeout: const Duration(seconds: 6),
       );

  final HfpAudioControl? _audioRouteControl;
  int _audioRouteGeneration = 0;
  int? _pendingAudioRouteGeneration;
  int? _activeAudioRouteGeneration;
  int? _continuousAudioRouteGeneration;

  @override
  bool get isContinuousHfpSessionActive =>
      _continuousAudioRouteGeneration != null;

  @override
  Future<void> beginContinuousHfpSession() async {
    if (isContinuousHfpSessionActive) return;
    final routeControl = _audioRouteControl;
    if (routeControl == null ||
        (routeControl.status.deviceId == null &&
            !routeControl.status.isConnected)) {
      throw const HfpAudioException(
        'Hãy kết nối H20 trước khi bắt đầu dịch liên tục.',
      );
    }

    await _cancelCurrentRecognition(preserveContinuousSession: false);
    final routeGeneration = ++_audioRouteGeneration;
    _pendingAudioRouteGeneration = routeGeneration;
    try {
      await routeControl.startAudioRoute();
      if (routeGeneration != _audioRouteGeneration) {
        await routeControl.stopAudioRoute().catchError((Object _) {});
        throw const StreamingSpeechInputException(
          'Đã dừng trước khi phiên HFP liên tục sẵn sàng.',
          code: 'CONTINUOUS_HFP_START_CANCELLED',
        );
      }
      if (!routeControl.status.routeActive ||
          routeControl.status.phase !=
              BluetoothAudioConnectionPhase.recording) {
        throw const HfpAudioException(
          'iOS chưa xác nhận HFP ổn định cho phiên dịch liên tục.',
        );
      }
      _pendingAudioRouteGeneration = null;
      _continuousAudioRouteGeneration = routeGeneration;
    } catch (_) {
      if (_pendingAudioRouteGeneration == routeGeneration) {
        _pendingAudioRouteGeneration = null;
      }
      if (_continuousAudioRouteGeneration == routeGeneration) {
        _continuousAudioRouteGeneration = null;
      }
      await routeControl.stopAudioRoute().catchError((Object _) {});
      rethrow;
    }
  }

  @override
  Future<void> endContinuousHfpSession() async {
    final routeGeneration = _continuousAudioRouteGeneration;
    if (routeGeneration == null) return;
    _continuousAudioRouteGeneration = null;
    _audioRouteGeneration += 1;
    await super.cancel().catchError((Object _) {});
    await _audioRouteControl?.stopAudioRoute().catchError((Object _) {});
  }

  @override
  Future<void> start() => _startWithAudioRoute(commandMode: false);

  @override
  // The native bridge still uses the dictation task hint for Vietnamese MAIN
  // phrases. commandMode only describes the interaction; it never switches
  // recognizers while a turn is active.
  Future<void> startCommandRecognition() =>
      _startWithAudioRoute(commandMode: true);

  /// Reuses the verified iOS/H20 native pipeline for an English lesson turn.
  Future<void> startLessonEnglishRecognition() =>
      _startWithAudioRoute(commandMode: false, localeIdentifier: 'en-US');

  Future<void> _startWithAudioRoute({
    required bool commandMode,
    String? localeIdentifier,
  }) async {
    // Outside a verified continuous session, each recognition turn still owns
    // a short HFP lease. A continuous session is opt-in and survives only after
    // its caller proves that BLE MAIN Notify remains stable with HFP active.
    await _cancelCurrentRecognition(preserveContinuousSession: true);
    int? routeGeneration;

    final routeControl = _audioRouteControl;
    final audioSource = takeNativeSpeechAudioSource(
      routeControl != null &&
              (routeControl.status.deviceId != null ||
                  routeControl.status.isConnected)
          ? NativeSpeechAudioSource.hfp
          : NativeSpeechAudioSource.builtInMic,
    );
    try {
      if (audioSource == NativeSpeechAudioSource.hfp &&
          routeControl != null &&
          (routeControl.status.deviceId != null ||
              routeControl.status.isConnected)) {
        if (!isContinuousHfpSessionActive) {
          // Selecting H20 in Settings only remembers the preferred input. The
          // HFP route must be activated immediately before AVAudioEngine opens
          // its input node or Apple Speech can remain on an inactive route.
          routeGeneration = ++_audioRouteGeneration;
          _pendingAudioRouteGeneration = routeGeneration;
          await routeControl.startAudioRoute();
          if (routeGeneration != _audioRouteGeneration) {
            await _releaseStaleAudioRouteIfUnowned();
            throw const StreamingSpeechInputException(
              'Đã dừng trước khi micro HFP sẵn sàng.',
              code: 'SPEECH_START_CANCELLED',
            );
          }
          if (_pendingAudioRouteGeneration == routeGeneration) {
            _pendingAudioRouteGeneration = null;
          }
          _activeAudioRouteGeneration = routeGeneration;
        }
        if (!routeControl.status.routeActive ||
            routeControl.status.phase !=
                BluetoothAudioConnectionPhase.recording) {
          throw const HfpAudioException(
            'iOS chưa xác nhận currentRoute là bluetoothHFP.',
          );
        }
      }
      await super.startWithNativeAudioSource(
        commandMode: commandMode,
        audioSource: audioSource,
        localeIdentifier: localeIdentifier,
      );
    } catch (_) {
      if (routeGeneration != null) {
        await _releaseAudioRouteLease(routeGeneration);
      }
      rethrow;
    }
  }

  /// iOS MAIN is deliberately native-only. Do not expose a private WAV that a
  /// controller could upload to the Batch endpoint after a native failure.
  @override
  AudioCapture? takeFallbackAudioCapture() => null;

  @override
  Future<StreamingSpeechCapture> stop() async {
    final routeGeneration =
        _activeAudioRouteGeneration ?? _pendingAudioRouteGeneration;
    try {
      return await super.stop();
    } finally {
      // Apple Speech has finished consuming the H20 microphone. Keeping SCO
      // alive after this boundary prevents the independent BLE control link
      // from reconnecting, so a later physical MAIN press never reaches Dart.
      if (routeGeneration != null) {
        await _releaseAudioRouteLease(routeGeneration);
      }
    }
  }

  @override
  Future<void> cancel() async {
    await _cancelCurrentRecognition(preserveContinuousSession: true);
  }

  Future<void> _cancelCurrentRecognition({
    required bool preserveContinuousSession,
  }) async {
    // Detach ownership before waiting for native cancellation. A late callback
    // from this turn must never release a newer HFP lease acquired meanwhile.
    final routeGeneration = _detachAudioRouteLease();
    final routeStop = _stopDetachedAudioRoute(
      routeGeneration,
      preserveContinuousSession: preserveContinuousSession,
    );
    try {
      await super.cancel();
    } finally {
      await routeStop;
    }
  }

  Future<void> _stopAudioRoute() async {
    final routeGeneration = _detachAudioRouteLease();
    await _stopDetachedAudioRoute(
      routeGeneration,
      preserveContinuousSession: false,
    );
  }

  int? _detachAudioRouteLease() {
    final routeGeneration =
        _activeAudioRouteGeneration ?? _pendingAudioRouteGeneration;
    _audioRouteGeneration += 1;
    _pendingAudioRouteGeneration = null;
    _activeAudioRouteGeneration = null;
    return routeGeneration;
  }

  Future<void> _stopDetachedAudioRoute(
    int? routeGeneration, {
    required bool preserveContinuousSession,
  }) async {
    if (routeGeneration == null) return;
    if (preserveContinuousSession && isContinuousHfpSessionActive) return;
    await _audioRouteControl?.stopAudioRoute().catchError((Object _) {});
  }

  Future<void> _releaseAudioRouteLease(int routeGeneration) async {
    final ownsPending = _pendingAudioRouteGeneration == routeGeneration;
    final ownsActive = _activeAudioRouteGeneration == routeGeneration;
    if (!ownsPending && !ownsActive) return;
    _audioRouteGeneration += 1;
    if (ownsPending) {
      _pendingAudioRouteGeneration = null;
    }
    if (ownsActive) {
      _activeAudioRouteGeneration = null;
    }
    if (_pendingAudioRouteGeneration == null &&
        _activeAudioRouteGeneration == null &&
        !isContinuousHfpSessionActive) {
      await _audioRouteControl?.stopAudioRoute().catchError((Object _) {});
    }
  }

  Future<void> _releaseStaleAudioRouteIfUnowned() async {
    if (_pendingAudioRouteGeneration != null ||
        _activeAudioRouteGeneration != null ||
        isContinuousHfpSessionActive) {
      return;
    }
    await _audioRouteControl?.stopAudioRoute().catchError((Object _) {});
  }

  @override
  Future<void> dispose() async {
    try {
      await endContinuousHfpSession();
      await super.dispose();
    } finally {
      await _stopAudioRoute();
    }
  }
}

/// Uses Apple Speech first for MAIN and switches to Cloudflare/Batch only when
/// native recognition cannot start. A recognition failure after speech begins
/// disables native for the next attempt because replaying the same utterance
/// would otherwise require uploading audio that was never captured by Batch.
class NativeFirstStreamingSpeechInput
    implements
        StreamingSpeechInput,
        SpeechActivityStreamingSpeechInput,
        CommandStreamingSpeechInput,
        AlternativeTranscriptStreamingSpeechInput,
        NativeSpeechFallbackAudioProvider,
        NativeSpeechDiagnostics {
  NativeFirstStreamingSpeechInput({
    required this.primary,
    required this.fallback,
    this.disposePrimary = false,
    this.disposeFallback = true,
    this.primaryStartTimeout = const Duration(seconds: 8),
  }) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      primary.amplitudeDbfs.listen((value) {
        if (identical(_active, primary)) _amplitudeController.add(value);
      }),
      fallback.amplitudeDbfs.listen((value) {
        if (identical(_active, fallback)) _amplitudeController.add(value);
      }),
      primary.partialText.listen((value) {
        if (identical(_active, primary)) _partialController.add(value);
      }),
      fallback.partialText.listen((value) {
        if (identical(_active, fallback)) _partialController.add(value);
      }),
      primary.completed.listen((_) {
        if (identical(_active, primary)) _completedController.add(null);
      }),
      fallback.completed.listen((_) {
        if (identical(_active, fallback)) _completedController.add(null);
      }),
    ]);
    final primaryAlternatives =
        primary is AlternativeTranscriptStreamingSpeechInput
        ? primary as AlternativeTranscriptStreamingSpeechInput
        : null;
    if (primaryAlternatives != null) {
      _subscriptions.add(
        primaryAlternatives.transcriptAlternatives.listen((value) {
          if (identical(_active, primary)) _alternativesController.add(value);
        }),
      );
    }
    final primaryActivity = primary is SpeechActivityStreamingSpeechInput
        ? primary as SpeechActivityStreamingSpeechInput
        : null;
    if (primaryActivity != null) {
      _subscriptions.add(
        primaryActivity.speechStarted.listen((_) {
          if (identical(_active, primary)) _speechStartedController.add(null);
        }),
      );
    }
    final fallbackActivity = fallback is SpeechActivityStreamingSpeechInput
        ? fallback as SpeechActivityStreamingSpeechInput
        : null;
    if (fallbackActivity != null) {
      _subscriptions.add(
        fallbackActivity.speechStarted.listen((_) {
          if (identical(_active, fallback)) _speechStartedController.add(null);
        }),
      );
    }
  }

  final StreamingSpeechInput primary;
  final StreamingSpeechInput fallback;
  final bool disposePrimary;
  final bool disposeFallback;
  final Duration primaryStartTimeout;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _speechStartedController =
      StreamController<void>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _alternativesController =
      StreamController<List<String>>.broadcast();
  StreamingSpeechInput? _active;
  String? _fallbackReason;
  DateTime? _nativeDisabledUntil;
  bool _disposed = false;

  @override
  String get label => _active?.label ?? primary.label;

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get speechStarted => _speechStartedController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialController.stream;

  @override
  Stream<List<String>> get transcriptAlternatives =>
      _alternativesController.stream;

  NativeSpeechDiagnostics? get _primaryDiagnostics =>
      primary is NativeSpeechDiagnostics
      ? primary as NativeSpeechDiagnostics
      : null;

  @override
  NativeSpeechDiagnostic? get nativeSpeechDiagnostic =>
      _primaryDiagnostics?.nativeSpeechDiagnostic;

  @override
  Stream<NativeSpeechDiagnostic> get nativeSpeechDiagnostics =>
      _primaryDiagnostics?.nativeSpeechDiagnostics ??
      const Stream<NativeSpeechDiagnostic>.empty();

  @override
  void reportNativeSpeechStage(
    String stage, {
    String? audioSource,
    String? audioRoute,
    String? code,
    String? message,
    String? turnId,
    int? sequence,
    int? elapsedMs,
    String? caller,
    DateTime? occurredAt,
  }) {
    _primaryDiagnostics?.reportNativeSpeechStage(
      stage,
      audioSource: audioSource,
      audioRoute: audioRoute,
      code: code,
      message: message,
      turnId: turnId,
      sequence: sequence,
      elapsedMs: elapsedMs,
      caller: caller,
      occurredAt: occurredAt,
    );
  }

  @override
  Future<bool> checkAvailability() async {
    if (_disposed) return false;
    return await primary.checkAvailability() ||
        await fallback.checkAvailability();
  }

  @override
  Future<void> start() => _start(commandMode: false);

  @override
  Future<void> startCommandRecognition() => _start(commandMode: true);

  Future<void> _start({required bool commandMode}) async {
    if (_disposed) {
      throw const StreamingSpeechInputException(
        'Bộ nhận dạng native-first đã đóng.',
        code: 'NATIVE_FIRST_DISPOSED',
      );
    }
    await cancel();
    _fallbackReason = null;
    final nativeDisabled =
        _nativeDisabledUntil?.isAfter(DateTime.now()) ?? false;
    if (!nativeDisabled) {
      _active = primary;
      try {
        // The concrete primary start already checks availability. Keeping a
        // separate check here made iOS query SpeechTranscriber.supportedLocale
        // twice and, more importantly, left the first asynchronous query
        // outside [primaryStartTimeout]. If that Apple API stalled, MAIN stayed
        // after prompt_done forever without ever invoking native speech.start.
        reportNativeSpeechStage('native_primary_start_requested');
        await _startInput(primary, commandMode: commandMode).timeout(
          primaryStartTimeout,
          onTimeout: () async {
            await primary.cancel().catchError((Object _) {});
            throw const StreamingSpeechInputException(
              'Apple Speech mất quá nhiều thời gian để sẵn sàng.',
              code: 'NATIVE_SPEECH_START_TIMEOUT',
            );
          },
        );
        return;
      } catch (error) {
        _fallbackReason = error is StreamingSpeechInputException
            ? error.code ?? error.message
            : error.toString();
        await primary.cancel().catchError((Object _) {});
      }
    } else {
      _fallbackReason = 'native_temporarily_disabled_after_error';
    }
    _active = fallback;
    await _startInput(fallback, commandMode: commandMode);
  }

  Future<void> _startInput(
    StreamingSpeechInput input, {
    required bool commandMode,
  }) {
    if (commandMode && input is CommandStreamingSpeechInput) {
      return (input as CommandStreamingSpeechInput).startCommandRecognition();
    }
    return input.start();
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    final active = _active;
    if (active == null) {
      throw const StreamingSpeechInputException(
        'Không tìm thấy lượt nhận dạng đang chạy.',
        code: 'NATIVE_FIRST_NOT_ACTIVE',
      );
    }
    try {
      final capture = await active.stop();
      if (!identical(active, fallback)) return capture;
      return _tagFallback(capture);
    } catch (error) {
      if (identical(active, primary)) {
        _nativeDisabledUntil = DateTime.now().add(const Duration(seconds: 30));
        final provider = primary is NativeSpeechFallbackAudioProvider
            ? primary as NativeSpeechFallbackAudioProvider
            : null;
        final recordedFallback = fallback is RecordedAudioFallbackSpeechInput
            ? fallback as RecordedAudioFallbackSpeechInput
            : null;
        final safetyRecording = provider?.takeFallbackAudioCapture();
        if (recordedFallback != null && safetyRecording != null) {
          _fallbackReason = error is StreamingSpeechInputException
              ? error.code ?? error.message
              : error.toString();
          _active = fallback;
          final capture = await recordedFallback.recognizeRecordedAudio(
            safetyRecording,
            fallbackReason: _fallbackReason,
          );
          return _tagFallback(capture);
        }
      }
      rethrow;
    }
  }

  StreamingSpeechCapture _tagFallback(StreamingSpeechCapture capture) {
    return StreamingSpeechCapture(
      sourceText: capture.sourceText,
      duration: capture.duration,
      inputLabel: capture.inputLabel,
      confidence: capture.confidence,
      firstResultMs: capture.firstResultMs,
      finalAfterStopMs: capture.finalAfterStopMs,
      asrMode: capture.asrMode,
      isBluetoothInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      realtimeSessionCreateMs: capture.realtimeSessionCreateMs,
      realtimeWebSocketConnectMs: capture.realtimeWebSocketConnectMs,
      realtimeWebSocketOpenAfterRecordingMs:
          capture.realtimeWebSocketOpenAfterRecordingMs,
      realtimeChunkDurationMs: capture.realtimeChunkDurationMs,
      workerAsrPilotRttMs: capture.workerAsrPilotRttMs,
      workerAsrPilotAsrMs: capture.workerAsrPilotAsrMs,
      workerAsrPilotAudioBytes: capture.workerAsrPilotAudioBytes,
      alternatives: capture.alternatives,
      recordedAudio: capture.recordedAudio,
      extraBenchmark: <String, dynamic>{
        ...?capture.extraBenchmark,
        'nativeSpeechFallbackUsed': true,
        if (_fallbackReason != null)
          'nativeSpeechFallbackReason': _fallbackReason,
      },
    );
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    _active = null;
    if (active != null) await active.cancel();
  }

  @override
  AudioCapture? takeFallbackAudioCapture() {
    final provider = primary is NativeSpeechFallbackAudioProvider
        ? primary as NativeSpeechFallbackAudioProvider
        : null;
    return provider?.takeFallbackAudioCapture();
  }

  Future<bool> prewarm() async {
    final native = primary is AndroidStreamingSpeechInput
        ? primary as AndroidStreamingSpeechInput
        : null;
    return native?.prewarm() ?? primary.checkAvailability();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel().catchError((Object _) {});
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    if (disposeFallback) await fallback.dispose();
    if (disposePrimary) await primary.dispose();
    await _amplitudeController.close();
    await _speechStartedController.close();
    await _completedController.close();
    await _partialController.close();
    await _alternativesController.close();
  }
}

class StreamingSpeechInputException implements Exception {
  const StreamingSpeechInputException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
