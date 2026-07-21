import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_input.dart';
import 'wav_audio.dart';

class PhoneMicrophoneInput implements ChunkedAudioInput {
  PhoneMicrophoneInput({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final StreamController<Uint8List> _audioChunkController =
      StreamController<Uint8List>.broadcast(sync: true);
  DateTime? _startedAt;
  String? _currentPath;
  double? _initialNoiseRms;
  BytesBuilder? _pcmBytes;
  BytesBuilder? _pendingChunkBytes;
  StreamSubscription<Uint8List>? _pcmSubscription;
  Completer<void>? _pcmStreamDone;
  Object? _streamError;
  bool _chunked = false;

  static const int _chunkByteLength =
      pcm16SampleRate * pcm16ChannelCount * (pcm16BitsPerSample ~/ 8) ~/ 4;

  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 90))
      .map((amplitude) {
        _initialNoiseRms ??= math.pow(10, amplitude.current / 20).toDouble();
        return amplitude.current;
      });

  @override
  Stream<Uint8List> get audioChunks => _audioChunkController.stream;

  Future<void> _prepareRecording() async {
    if (!await _recorder.hasPermission()) {
      throw const AudioInputException(
        'Ứng dụng cần quyền micro để nghe con nói.',
      );
    }

    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.speech());

    final temporaryDirectory = await getTemporaryDirectory();
    final extension = _chunked ? 'wav' : 'm4a';
    final fileName =
        'utterance_${DateTime.now().microsecondsSinceEpoch}.$extension';
    _currentPath = '${temporaryDirectory.path}/$fileName';
    _startedAt = DateTime.now();
    _initialNoiseRms = null;
    _streamError = null;
  }

  @override
  Future<void> start() async {
    _chunked = false;
    await _prepareRecording();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: _currentPath!,
    );
  }

  @override
  Future<void> startChunked() async {
    _chunked = true;
    _pcmBytes = BytesBuilder(copy: false);
    _pendingChunkBytes = BytesBuilder(copy: false);
    _pcmStreamDone = Completer<void>();
    await _prepareRecording();

    final pcmStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: pcm16SampleRate,
        numChannels: pcm16ChannelCount,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _pcmSubscription = pcmStream.listen(
      _handlePcmBytes,
      onError: (Object error, StackTrace stackTrace) {
        _streamError = error;
        _completePcmStream();
      },
      onDone: _completePcmStream,
      cancelOnError: false,
    );
  }

  void _handlePcmBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    _pcmBytes?.add(bytes);
    _pendingChunkBytes?.add(bytes);
    final pending = _pendingChunkBytes?.takeBytes() ?? Uint8List(0);
    var offset = 0;
    while (pending.length - offset >= _chunkByteLength) {
      _audioChunkController.add(
        Uint8List.sublistView(pending, offset, offset + _chunkByteLength),
      );
      offset += _chunkByteLength;
    }
    if (offset < pending.length) {
      _pendingChunkBytes?.add(Uint8List.sublistView(pending, offset));
    }
  }

  void _flushFinalChunk() {
    final finalChunk = _pendingChunkBytes?.takeBytes();
    if (finalChunk != null && finalChunk.isNotEmpty) {
      _audioChunkController.add(finalChunk);
    }
  }

  void _completePcmStream() {
    final completer = _pcmStreamDone;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Future<AudioCapture> stop() async {
    final recorderPath = await _recorder.stop();
    if (_chunked) {
      await _pcmStreamDone?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _pcmSubscription?.cancel();
      _pcmSubscription = null;
      _flushFinalChunk();
    }
    final path = recorderPath ?? _currentPath;
    final startedAt = _startedAt;

    if (path == null || startedAt == null) {
      throw const AudioInputException('Không tìm thấy bản ghi âm vừa tạo.');
    }

    final streamError = _streamError;
    if (streamError != null) {
      throw AudioInputException('Không thể đọc luồng âm thanh: $streamError');
    }

    Uint8List? streamHeaderBytes;
    int? streamedAudioBytes;
    var mimeType = 'audio/mp4';
    if (_chunked) {
      final pcmBytes = _pcmBytes?.takeBytes() ?? Uint8List(0);
      if (pcmBytes.isEmpty) {
        throw const AudioInputException('Không thu được dữ liệu âm thanh PCM.');
      }
      streamedAudioBytes = pcmBytes.length;
      streamHeaderBytes = buildPcm16WavHeader(
        pcmByteLength: streamedAudioBytes,
      );
      await File(
        path,
      ).writeAsBytes(<int>[...streamHeaderBytes, ...pcmBytes], flush: true);
      mimeType = 'audio/wav';
    }

    return AudioCapture(
      filePath: path,
      mimeType: mimeType,
      duration: DateTime.now().difference(startedAt),
      inputLabel: label,
      isBluetoothInput: isBluetooth,
      initialNoiseRms: _initialNoiseRms,
      streamHeaderBytes: streamHeaderBytes,
      streamedAudioBytes: streamedAudioBytes,
    );
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    _completePcmStream();
    _currentPath = null;
    _startedAt = null;
    _pcmBytes = null;
    _pendingChunkBytes = null;
    _chunked = false;
  }

  @override
  Future<void> dispose() async {
    await _pcmSubscription?.cancel();
    await _audioChunkController.close();
    await _recorder.dispose();
  }
}

class AudioInputException implements Exception {
  const AudioInputException(this.message);

  final String message;

  @override
  String toString() => message;
}
