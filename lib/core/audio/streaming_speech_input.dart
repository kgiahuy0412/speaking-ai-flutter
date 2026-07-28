import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

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

class AndroidStreamingSpeechInput implements StreamingSpeechInput {
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

  late final StreamSubscription<dynamic> _eventSubscription;
  Completer<String>? _resultCompleter;
  DateTime? _startedAt;
  DateTime? _firstResultAt;
  DateTime? _resultAt;
  DateTime? _latestTextUpdatedAt;
  String _latestText = '';
  double? _confidence;
  bool _active = false;
  bool _disposed = false;

  @override
  String get label => 'ASR Android trực tiếp';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async {
    try {
      return await _methodChannel.invokeMethod<bool>('speech.isAvailable') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> start() async {
    if (_active) {
      await cancel();
    }
    if (!await checkAvailability()) {
      throw const StreamingSpeechInputException(
        'Thiết bị chưa có dịch vụ nhận diện giọng nói Android.',
      );
    }

    _latestText = '';
    _confidence = null;
    _firstResultAt = null;
    _resultAt = null;
    _latestTextUpdatedAt = null;
    final resultCompleter = Completer<String>();
    _resultCompleter = resultCompleter;
    unawaited(
      resultCompleter.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _startedAt = DateTime.now();
    _active = true;

    try {
      await _methodChannel.invokeMethod<void>('speech.start');
    } on PlatformException catch (error) {
      _active = false;
      throw StreamingSpeechInputException(
        error.message ?? 'Không thể bắt đầu nhận diện giọng nói.',
        code: error.code,
      );
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
      sourceText = partialAtStop;
      _resultAt = DateTime.now();
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
    if (_active) {
      await _methodChannel.invokeMethod<void>('speech.cancel');
    }
    _active = false;
    _startedAt = null;
    _latestText = '';
    _latestTextUpdatedAt = null;
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete('');
    }
    _resultCompleter = null;
  }

  void _handleEvent(dynamic event) {
    if (_disposed || event is! Map<dynamic, dynamic>) {
      return;
    }

    final type = event['type'];
    if (type == 'speech.rms') {
      final rmsDb = (event['rmsDb'] as num?)?.toDouble() ?? -2;
      final level = ((rmsDb + 2) / 12).clamp(0.0, 1.0);
      _amplitudeController.add(-60 + (level * 60));
      return;
    }

    if (type == 'speech.partial' || type == 'speech.final') {
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
      _active = false;
      _resultAt = DateTime.now();
      final message =
          event['message'] as String? ?? 'Không thể nhận diện giọng nói.';
      final completer = _resultCompleter;
      if (_latestText.isNotEmpty) {
        _completeResult(_latestText);
      } else if (completer != null && !completer.isCompleted) {
        completer.completeError(StreamingSpeechInputException(message));
      }
      _completedController.add(null);
    }
  }

  void _handleChannelError(Object error) {
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
    if (_active) {
      await _methodChannel.invokeMethod<void>('speech.cancel');
    }
    await _eventSubscription.cancel();
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
}

class StreamingSpeechInputException implements Exception {
  const StreamingSpeechInputException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
