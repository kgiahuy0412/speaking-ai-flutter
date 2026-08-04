import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio_input.dart';
import 'pcm_speech_preprocessor.dart';
import 'recording_storage.dart';
import 'wav_audio.dart';

class PhoneMicrophoneInput
    implements ChunkedAudioInput, SelectableAudioInputControl {
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
  PcmSpeechPreprocessor? _pcmPreprocessor;
  bool _chunked = false;
  bool _microphonePermissionGranted = false;
  bool _recordConfigListenerRegistered = false;
  int _effectiveSampleRate = pcm16SampleRate;
  bool? _platformAutoGainApplied;
  bool? _platformEchoCancellationApplied;
  bool? _platformNoiseSuppressionApplied;
  InputDevice? _selectedInputDevice;

  static const _androidVoiceRecordConfig = AndroidRecordConfig(
    audioSource: AndroidAudioSource.voiceCommunication,
    audioManagerMode: AudioManagerMode.modeInCommunication,
  );

  int get _chunkByteLength =>
      pcm16ChunkByteLength(sampleRate: _effectiveSampleRate);

  @override
  String get label {
    final selected = _selectedInputDevice;
    return selected == null
        ? 'Mic điện thoại'
        : 'Mic HFP Web • ${selected.label.trim().isEmpty ? selected.id : selected.label.trim()}';
  }

  @override
  bool get isBluetooth => _selectedInputDevice != null;

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

  @override
  SelectableAudioInputDevice? get selectedAudioInputDevice {
    final selected = _selectedInputDevice;
    return selected == null
        ? null
        : SelectableAudioInputDevice(id: selected.id, label: selected.label);
  }

  @override
  Future<List<SelectableAudioInputDevice>> listAudioInputDevices() async {
    final devices = await _recorder.listInputDevices();
    return devices
        .where((device) => device.id.trim().isNotEmpty)
        .map(
          (device) =>
              SelectableAudioInputDevice(id: device.id, label: device.label),
        )
        .toList(growable: false);
  }

  @override
  Future<void> selectAudioInputDevice(
    SelectableAudioInputDevice? device,
  ) async {
    if (device == null) {
      _selectedInputDevice = null;
      return;
    }
    final available = await _recorder.listInputDevices();
    InputDevice? selected;
    for (final item in available) {
      if (item.id == device.id) {
        selected = item;
        break;
      }
    }
    if (selected == null) {
      throw const AudioInputException(
        'Mic Bluetooth không còn khả dụng. Hãy kết nối lại tai nghe và thử lại.',
      );
    }
    _selectedInputDevice = selected;
  }

  Future<void> _prepareRecording() async {
    if (!_microphonePermissionGranted) {
      if (!await _recorder.hasPermission()) {
        throw const AudioInputException(
          'Ứng dụng cần quyền micro để nghe con nói.',
        );
      }
      _microphonePermissionGranted = true;
    }

    if (kIsWeb && !_recordConfigListenerRegistered) {
      await _recorder.setOnConfigChanged((config) {
        if (config.sampleRate > 0) {
          _effectiveSampleRate = config.sampleRate;
        }
        _platformAutoGainApplied = config.autoGain;
        _platformEchoCancellationApplied = config.echoCancel;
        _platformNoiseSuppressionApplied = config.noiseSuppress;
      });
      _recordConfigListenerRegistered = true;
    }

    final audioSession = await AudioSession.instance;
    await audioSession.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );

    final extension = _chunked ? 'wav' : 'm4a';
    _currentPath = await createTemporaryRecordingPath(extension);
    _startedAt = DateTime.now();
    _initialNoiseRms = null;
    _streamError = null;
    _pcmPreprocessor = null;
    // record_web reports adjusted track settings through setOnConfigChanged.
    // Android exposes support per device but not the final enabled state here,
    // so keep it unknown instead of claiming an effect was applied.
    _platformAutoGainApplied = kIsWeb ? true : null;
    _platformEchoCancellationApplied = kIsWeb ? true : null;
    _platformNoiseSuppressionApplied = kIsWeb ? true : null;
  }

  @override
  Future<void> start() async {
    _chunked = false;
    await _prepareRecording();

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: _androidVoiceRecordConfig,
        device: _selectedInputDevice,
      ),
      path: _currentPath!,
    );
  }

  @override
  Future<void> startChunked() async {
    _chunked = true;
    _effectiveSampleRate = pcm16SampleRate;
    _pcmBytes = BytesBuilder(copy: false);
    _pendingChunkBytes = BytesBuilder(copy: false);
    _pcmStreamDone = Completer<void>();
    await _prepareRecording();

    final pcmStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: pcm16SampleRate,
        numChannels: pcm16ChannelCount,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: _androidVoiceRecordConfig,
        device: _selectedInputDevice,
      ),
    );
    _pcmPreprocessor = PcmSpeechPreprocessor(sampleRate: _effectiveSampleRate);
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
    _pendingChunkBytes?.add(bytes);
    final pending = _pendingChunkBytes?.takeBytes() ?? Uint8List(0);
    var offset = 0;
    while (pending.length - offset >= _chunkByteLength) {
      final processed = _processPcmChunk(
        Uint8List.sublistView(pending, offset, offset + _chunkByteLength),
      );
      _pcmBytes?.add(processed);
      _audioChunkController.add(processed);
      offset += _chunkByteLength;
    }
    if (offset < pending.length) {
      _pendingChunkBytes?.add(Uint8List.sublistView(pending, offset));
    }
  }

  void _flushFinalChunk() {
    final finalChunk = _pendingChunkBytes?.takeBytes();
    if (finalChunk != null && finalChunk.isNotEmpty) {
      final processed = _processPcmChunk(finalChunk);
      _pcmBytes?.add(processed);
      _audioChunkController.add(processed);
    }
  }

  Uint8List _processPcmChunk(Uint8List bytes) =>
      _pcmPreprocessor?.process(bytes) ?? Uint8List.fromList(bytes);

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
    Uint8List? dataBytes;
    final audioProcessing = _buildAudioProcessingMetrics();
    var mimeType = 'audio/mp4';
    if (_chunked) {
      final pcmBytes = _pcmBytes?.takeBytes() ?? Uint8List(0);
      if (pcmBytes.isEmpty) {
        throw const AudioInputException('Không thu được dữ liệu âm thanh PCM.');
      }
      streamedAudioBytes = pcmBytes.length;
      streamHeaderBytes = buildPcm16WavHeader(
        pcmByteLength: streamedAudioBytes,
        sampleRate: _effectiveSampleRate,
      );
      final wavBytes = Uint8List.fromList(<int>[
        ...streamHeaderBytes,
        ...pcmBytes,
      ]);
      dataBytes = wavBytes;
      await persistRecordingBytes(path, wavBytes);
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
      recordingSampleRate: _chunked ? _effectiveSampleRate : null,
      dataBytes: dataBytes,
      audioProcessing: audioProcessing,
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
    _pcmPreprocessor = null;
    _chunked = false;
  }

  AudioProcessingMetrics _buildAudioProcessingMetrics() {
    final preprocessor = _pcmPreprocessor;
    if (preprocessor != null) {
      return preprocessor.metrics(
        platformNoiseSuppressionRequested: true,
        platformEchoCancellationRequested: true,
        platformAutoGainRequested: true,
        platformNoiseSuppressionApplied: _platformNoiseSuppressionApplied,
        platformEchoCancellationApplied: _platformEchoCancellationApplied,
        platformAutoGainApplied: _platformAutoGainApplied,
      );
    }
    return AudioProcessingMetrics(
      platformNoiseSuppressionRequested: true,
      platformEchoCancellationRequested: true,
      platformAutoGainRequested: true,
      platformNoiseSuppressionApplied: _platformNoiseSuppressionApplied,
      platformEchoCancellationApplied: _platformEchoCancellationApplied,
      platformAutoGainApplied: _platformAutoGainApplied,
      pcmHighPassApplied: false,
      pcmAdaptiveNoiseGateApplied: false,
    );
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
