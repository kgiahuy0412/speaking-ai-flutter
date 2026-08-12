import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/audio/adaptive_voice_activity_detector.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/audio_playback_service.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/audio/offline_intent_recognizer.dart';
import '../../../core/audio/realtime_fallback_buffer.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import '../domain/conversation_models.dart';
import '../domain/conversation_repository.dart';
import '../domain/speech_gated_batch_upload_session.dart';

enum H20HardwareTestPhase {
  idle,
  openingRoute,
  recording,
  playing,
  completed,
  error,
}

class H20HardwareTestResult {
  const H20HardwareTestResult({
    required this.completedAt,
    required this.inputRouteVerified,
    required this.outputRouteVerified,
    this.recordedDuration,
    this.inputDeviceName,
    this.outputDeviceName,
    this.playbackAudible,
  });

  final DateTime completedAt;
  final bool inputRouteVerified;
  final bool outputRouteVerified;
  final Duration? recordedDuration;
  final String? inputDeviceName;
  final String? outputDeviceName;
  final bool? playbackAudible;

  H20HardwareTestResult copyWith({bool? playbackAudible}) {
    return H20HardwareTestResult(
      completedAt: completedAt,
      inputRouteVerified: inputRouteVerified,
      outputRouteVerified: outputRouteVerified,
      recordedDuration: recordedDuration,
      inputDeviceName: inputDeviceName,
      outputDeviceName: outputDeviceName,
      playbackAudible: playbackAudible ?? this.playbackAudible,
    );
  }
}

class ConversationController extends ChangeNotifier {
  ConversationController({
    required AudioInput audioInput,
    StreamingSpeechInput? streamingSpeechInput,
    HfpAudioControl? hfpAudioControl,
    Aiv0BleControl? aiv0BleControl,
    required AudioPlaybackService playbackService,
    VoicePromptService? voicePromptService,
    required ConversationRepository repository,
    OfflineIntentRecognizer? offlineIntentRecognizer,
    DisplayLanguageStore? displayLanguageStore,
    required int childAge,
    bool preferBleStreaming = true,
    bool realtimeBatchFallback = true,
    int realtimeFallbackBufferBytes = 15 * 1024 * 1024,
    AsrMode? initialAsrMode,
    bool? webRuntimeOverride,
    Duration? adaptiveWebUploadDelay,
  }) : _audioInput = audioInput,
       _bluetoothAudioControl = audioInput is BluetoothAudioInputControl
           ? audioInput as BluetoothAudioInputControl
           : null,
       _streamingSpeechInput = streamingSpeechInput,
       _hfpAudioControl = hfpAudioControl,
       _aiv0BleControl = aiv0BleControl,
       _playbackService = playbackService,
       _voicePromptService = voicePromptService,
       _repository = repository,
       _offlineIntentRecognizer = offlineIntentRecognizer,
       _displayLanguageStore = displayLanguageStore,
       _childAge = childAge,
       _preferBleStreaming = preferBleStreaming,
       _realtimeBatchFallback = realtimeBatchFallback,
       _isWebRuntime = webRuntimeOverride ?? kIsWeb,
       _adaptiveWebUploadDelay = adaptiveWebUploadDelay ?? Duration.zero,
       _realtimeFallbackBuffer = RealtimeFallbackBuffer(
         maxBytes: realtimeFallbackBufferBytes > 0
             ? realtimeFallbackBufferBytes
             : 15 * 1024 * 1024,
       ),
       asrMode =
           initialAsrMode ??
           (streamingSpeechInput == null
               ? AsrMode.batchChunks
               : AsrMode.androidStreaming) {
    _streamingCompletionSubscription = streamingSpeechInput?.completed.listen((
      _,
    ) {
      if (phase == ConversationPhase.recording &&
          _usingStreamingSpeech &&
          !_stopInProgress) {
        unawaited(stopRecording(manual: false));
      }
    });
    _partialTextSubscription = streamingSpeechInput?.partialText.listen(
      _onPartialText,
    );
    final bluetoothControl = _bluetoothAudioControl;
    if (bluetoothControl != null) {
      _bluetoothStatusSubscription = bluetoothControl.bluetoothStatusChanges
          .listen((_) {
            if (!_disposed) {
              notifyListeners();
            }
          });
      unawaited(
        bluetoothControl.initializeBluetooth().catchError((Object error) {
          debugPrint('INNOTRIK BLE initialization failed: $error');
        }),
      );
    }
    final hfpControl = _hfpAudioControl;
    if (hfpControl != null) {
      _hfpStatusSubscription = hfpControl.statusChanges.listen((_) {
        if (!_disposed) {
          notifyListeners();
        }
      });
      unawaited(
        hfpControl.initialize().catchError((Object error) {
          debugPrint('HFP initialization failed: $error');
        }),
      );
    }
    final aiv0Control = _aiv0BleControl;
    if (aiv0Control != null) {
      _aiv0StatusSubscription = aiv0Control.statusStream.listen((_) {
        if (!_disposed) notifyListeners();
      });
      _aiv0ButtonSubscription = aiv0Control.buttonEvents.listen(
        _onAiv0ButtonEvent,
      );
      unawaited(
        aiv0Control.initialize().catchError((Object error) {
          debugPrint('AIV0 BLE Control initialization failed: $error');
        }),
      );
    }
    _playbackPlayingSubscription = playbackService.playingStream
        .distinct()
        .listen((playing) {
          _playbackPlaying = playing;
          unawaited(_syncAiv0AppState());
          if (!_disposed) notifyListeners();
        });
    if (displayLanguageStore != null) {
      unawaited(_loadDisplayLanguage());
    }
    unawaited(_primeExactIntentCatalog());
  }

  final AudioInput _audioInput;
  final BluetoothAudioInputControl? _bluetoothAudioControl;
  final StreamingSpeechInput? _streamingSpeechInput;
  final HfpAudioControl? _hfpAudioControl;
  final Aiv0BleControl? _aiv0BleControl;
  final AudioPlaybackService _playbackService;
  final VoicePromptService? _voicePromptService;
  final ConversationRepository _repository;
  final OfflineIntentRecognizer? _offlineIntentRecognizer;
  final DisplayLanguageStore? _displayLanguageStore;
  final int _childAge;
  final bool _preferBleStreaming;
  final bool _realtimeBatchFallback;
  final bool _isWebRuntime;
  final Duration _adaptiveWebUploadDelay;
  final RealtimeFallbackBuffer _realtimeFallbackBuffer;
  final AdaptiveVoiceActivityDetector _voiceActivityDetector =
      AdaptiveVoiceActivityDetector();

  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<BluetoothAudioStatus>? _bluetoothStatusSubscription;
  StreamSubscription<BluetoothAudioStatus>? _hfpStatusSubscription;
  StreamSubscription<Aiv0BleStatus>? _aiv0StatusSubscription;
  StreamSubscription<Aiv0ButtonEvent>? _aiv0ButtonSubscription;
  StreamSubscription<bool>? _playbackPlayingSubscription;
  StreamSubscription<void>? _streamingCompletionSubscription;
  StreamSubscription<String>? _partialTextSubscription;
  StreamSubscription<Uint8List>? _batchChunkSubscription;
  StreamSubscription<ConversationPreview>? _batchPreviewSubscription;
  StreamSubscription<Uint8List>? _realtimeChunkSubscription;
  StreamSubscription<String>? _realtimePartialSubscription;
  StreamSubscription<OfflineIntentHypothesis>?
  _offlineIntentHypothesisSubscription;
  Timer? _partialPreviewTimer;
  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  Timer? _maximumDurationTimer;
  Timer? _offlineFallbackTimer;
  Timer? _processingStageTimer;
  Timer? _h20HardwareRecordingTimer;
  DateTime? _recordingStartedAt;
  DateTime? _stoppedAt;
  DateTime? _responseReceivedAt;
  bool _stopInProgress = false;
  bool _speechDetected = false;
  bool _noisyRecording = false;
  bool _usingStreamingSpeech = false;
  bool _usingHfpRoute = false;
  bool _usingRealtimeTranscription = false;
  bool _usingOfflineIntent = false;
  bool _playbackPlaying = false;
  bool _h20HardwareAudioInputStarted = false;
  bool _h20HardwareStopInProgress = false;
  BatchChunkUploadSession? _batchChunkUpload;
  SpeechGatedBatchUploadSession? _batchSpeechGate;
  _AdaptiveWebChunkUpload? _adaptiveWebUpload;
  RealtimeTranscriptionSession? _realtimeSession;
  Future<void>? _realtimeConnectionFuture;
  int _realtimeConnectionGeneration = 0;
  OfflineIntentManifest? _offlineIntentManifest;
  OfflineIntentGate? _offlineIntentGate;
  OfflineIntentDecision? _offlineIntentDecision;
  int? _offlineIntentFirstResultMs;
  bool _disposed = false;
  int _previewGeneration = 0;
  String? _lastPreviewText;
  ConversationPreview? _preview;
  Uri? _preferredPlaybackUri;
  Uri? _speculativePreloadUri;
  final List<Aiv0ButtonEvent> _aiv0ButtonEventLog = <Aiv0ButtonEvent>[];

  ConversationPhase phase = ConversationPhase.idle;
  ConversationProcessingStage processingStage =
      ConversationProcessingStage.recognizing;
  PracticeContext context = PracticeContext.home;
  AsrMode asrMode;
  int vadSilenceMs = 900;
  double amplitude = 0;
  ConversationResult? result;
  bool? qualityApproved;
  String? errorMessage;
  String? transientMessage;
  DisplayLanguage displayLanguage = DisplayLanguage.vietnamese;
  bool bleDiagnosticRunning = false;
  bool h20HardwareTestModeEnabled = false;
  H20HardwareTestPhase h20HardwareTestPhase = H20HardwareTestPhase.idle;
  H20HardwareTestResult? h20HardwareTestResult;
  String? h20HardwareTestMessage;

  Future<void> _loadDisplayLanguage() async {
    final stored = await _displayLanguageStore!.read();
    if (_disposed || stored == displayLanguage) {
      return;
    }
    displayLanguage = stored;
    notifyListeners();
  }

  Future<void> _primeExactIntentCatalog() async {
    // Web Batch Chunks has no local transcript to match while recording. The
    // backend performs the exact lookup after ASR, so downloading the catalog
    // during PWA startup only delays the first microphone interaction.
    if (_isWebRuntime) {
      return;
    }
    final catalog = _repository is OfflineIntentCatalogRepository
        ? _repository as OfflineIntentCatalogRepository
        : null;
    if (catalog == null) {
      return;
    }
    try {
      final manifest = await catalog.fetchOfflineIntentManifest();
      if (!_disposed) {
        _offlineIntentManifest = manifest;
      }
    } catch (error) {
      debugPrint('Exact-rule catalog preload was skipped: $error');
    }
  }

  String _normalizeExactText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\.,!?;:"“”‘’…()\-_/]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  OfflineIntentDefinition? _findLocalExactIntent(
    String sourceText,
    PracticeContext targetContext,
  ) {
    final normalized = _normalizeExactText(sourceText);
    if (normalized.isEmpty) {
      return null;
    }
    for (final item in _offlineIntentManifest?.items ?? const []) {
      if (!item.contexts.contains(targetContext.apiValue)) {
        continue;
      }
      for (final sample in item.samples) {
        if (_normalizeExactText(sample) == normalized) {
          return item;
        }
      }
    }
    return null;
  }

  bool _applyLocalExactPreview(
    String sourceText, {
    required PracticeContext targetContext,
  }) {
    final exact = _findLocalExactIntent(sourceText, targetContext);
    if (exact == null || exact.englishText.trim().isEmpty) {
      return false;
    }
    _preview = ConversationPreview(
      sourceText: sourceText.trim(),
      englishText: exact.englishText.trim(),
      textSource: 'device_exact_rule',
      audioUri: exact.audioUri,
    );
    unawaited(
      _playbackService.preload(exact.audioUri).catchError((Object error) {
        debugPrint('Local exact-rule audio preload was skipped: $error');
      }),
    );
    return true;
  }

  void setDisplayLanguage(DisplayLanguage language) {
    if (language == displayLanguage) {
      return;
    }
    displayLanguage = language;
    notifyListeners();
    final store = _displayLanguageStore;
    if (store != null) {
      unawaited(
        store.write(language).catchError((Object error) {
          debugPrint('Cannot persist display language: $error');
        }),
      );
    }
  }

  String get inputLabel {
    if (asrMode == AsrMode.hfpStreaming || _usingHfpRoute) {
      final name = hfpAudioStatus.deviceName?.trim();
      if (supportsBrowserHfp) {
        return name == null || name.isEmpty
            ? 'Mic HFP Web'
            : 'Mic HFP Web • $name';
      }
      return name == null || name.isEmpty
          ? 'ASR HFP trực tiếp'
          : 'ASR HFP trực tiếp • $name';
    }
    return _usingStreamingSpeech ||
            (phase == ConversationPhase.idle &&
                asrMode == AsrMode.androidStreaming)
        ? _streamingSpeechInput?.label ?? _audioInput.label
        : _audioInput.label;
  }

  bool get supportsAndroidStreaming => _streamingSpeechInput != null;
  BluetoothAudioStatus get bluetoothAudioStatus =>
      _bluetoothAudioControl?.bluetoothStatus ??
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.unsupported,
      );
  bool get supportsInnotrikBle => bluetoothAudioStatus.isBridgeSupported;
  bool get canUseInnotrikBle => bluetoothAudioStatus.isConnected;
  BluetoothAudioStatus get hfpAudioStatus =>
      _hfpAudioControl?.status ??
      const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.unsupported,
        sampleRate: 16000,
      );
  bool get supportsHfp => hfpAudioStatus.isBridgeSupported;
  bool get canUseHfp => hfpAudioStatus.isConnected;
  Aiv0BleStatus get aiv0BleStatus =>
      _aiv0BleControl?.status ?? const Aiv0BleStatus.disabled();
  bool get supportsAiv0Ble => aiv0BleStatus.phase != Aiv0BlePhase.disabled;
  bool get canUseAiv0Ble => aiv0BleStatus.isConnected;
  List<Aiv0ButtonEvent> get aiv0ButtonEventLog =>
      List<Aiv0ButtonEvent>.unmodifiable(_aiv0ButtonEventLog);
  bool get supportsBrowserHfp =>
      (_hfpAudioControl?.usesBrowserAudioInput ?? false) &&
      _audioInput is ChunkedAudioInput;
  bool get isBrowserHfpMode =>
      asrMode == AsrMode.hfpStreaming && supportsBrowserHfp;
  bool get isBluetoothInput =>
      asrMode == AsrMode.hfpStreaming ||
      _usingHfpRoute ||
      _audioInput.isBluetooth;
  bool get isInputAvailable => _audioInput.isAvailable;
  bool get isRecording => phase == ConversationPhase.recording;
  bool get h20HardwareTestActive =>
      h20HardwareTestPhase == H20HardwareTestPhase.openingRoute ||
      h20HardwareTestPhase == H20HardwareTestPhase.recording ||
      h20HardwareTestPhase == H20HardwareTestPhase.playing;
  bool get isBusy =>
      bleDiagnosticRunning ||
      h20HardwareTestActive ||
      hfpAudioStatus.isBusy ||
      aiv0BleStatus.phase == Aiv0BlePhase.scanning ||
      aiv0BleStatus.phase == Aiv0BlePhase.connecting ||
      phase == ConversationPhase.recording ||
      phase == ConversationPhase.processing;

  Future<({String englishText, String vietnameseText})> translateVocabulary(
    String sourceText,
  ) async {
    final normalized = sourceText.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        sourceText,
        'sourceText',
        'Từ không được trống.',
      );
    }
    if (isBusy) {
      throw StateError('Hãy hoàn tất lượt giao tiếp trước khi thêm từ vựng.');
    }

    try {
      final preview = await _repository.previewStreamingText(
        sourceText: normalized,
        context: context,
        childAge: _childAge,
      );
      final previewEnglish = preview?.englishText.trim() ?? '';
      if (previewEnglish.isNotEmpty) {
        return (englishText: previewEnglish, vietnameseText: normalized);
      }
    } catch (error) {
      debugPrint('Vocabulary preview failed; using full translation: $error');
    }

    final result = await _repository.processStreamingText(
      capture: StreamingSpeechCapture(
        sourceText: normalized,
        duration: Duration.zero,
        inputLabel: 'Nhập từ vựng',
        confidence: 1,
        firstResultMs: 0,
        finalAfterStopMs: 0,
        asrMode: 'text',
      ),
      context: context,
      childAge: _childAge,
      vadSilenceMs: vadSilenceMs,
    );
    final englishText = result.englishText.trim();
    if (englishText.isEmpty) {
      throw StateError('Backend không trả về bản dịch tiếng Anh.');
    }
    return (
      englishText: englishText,
      vietnameseText: result.vietnameseText.trim().isEmpty
          ? normalized
          : result.vietnameseText.trim(),
    );
  }

  Future<void> onPrimaryAction() async {
    if (phase == ConversationPhase.recording) {
      final userGesturePlayback = _playbackService;
      if (userGesturePlayback is UserGestureAudioPlaybackService) {
        await (userGesturePlayback as UserGestureAudioPlaybackService)
            .unlockForUserGesture();
      }
      await stopRecording(manual: true);
      return;
    }
    if (phase == ConversationPhase.processing) {
      return;
    }
    await startRecording();
  }

  Future<List<Aiv0BleDevice>> scanAiv0Devices() async {
    final control = _aiv0BleControl;
    if (control == null || isBusy) return const [];
    transientMessage = 'Đang quét BLE Control H20/AIV0…';
    notifyListeners();
    try {
      final devices = await control.scan(timeout: const Duration(seconds: 8));
      transientMessage = devices.isEmpty
          ? 'Không tìm thấy H20. Hãy bật thiết bị và đặt gần điện thoại.'
          : null;
      notifyListeners();
      return devices;
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectAiv0Device(Aiv0BleDevice device) async {
    final control = _aiv0BleControl;
    if (control == null || isBusy) return;
    transientMessage = 'Đang xác nhận BLE Control trên ${device.name}…';
    notifyListeners();
    try {
      await control.connect(device.id);
      transientMessage = aiv0BleStatus.protocolConfirmed
          ? 'BLE Control AIV0 đã kết nối; MAIN đã sẵn sàng.'
          : 'BLE Control đã kết nối ở chế độ chẩn đoán. Hãy bấm MAIN để lấy raw hex từ ODM.';
      notifyListeners();
      await _syncAiv0AppState();
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnectAiv0Device() async {
    if (isBusy) return;
    await _aiv0BleControl?.disconnect();
    transientMessage = 'Đã ngắt BLE Control AIV0.';
    notifyListeners();
  }

  void _onAiv0ButtonEvent(Aiv0ButtonEvent event) {
    if (_disposed) return;
    _aiv0ButtonEventLog.insert(0, event);
    if (_aiv0ButtonEventLog.length > 12) {
      _aiv0ButtonEventLog.removeRange(12, _aiv0ButtonEventLog.length);
    }
    if (!event.isDraftPacket) {
      transientMessage =
          'Đã nhận raw hex từ H20: ${event.rawHex}. Chưa điều khiển APP vì ODM chưa xác nhận định dạng packet.';
      notifyListeners();
      return;
    }
    unawaited(
      _handleAiv0ButtonEvent(event).catchError((Object error) async {
        transientMessage = _friendlyError(error);
        if (!_disposed) notifyListeners();
        await _syncAiv0AppState(
          resultCode: Aiv0AppResult.internalError,
          sequence: event.sequence ?? 0,
        );
      }),
    );
  }

  Future<void> _handleAiv0ButtonEvent(Aiv0ButtonEvent event) async {
    final sequence = event.sequence ?? 0;
    if (event.isDuplicate) {
      await _syncAiv0AppState(
        resultCode: Aiv0AppResult.duplicate,
        sequence: sequence,
      );
      return;
    }
    if (event.gesture != Aiv0ButtonGesture.shortPress) return;

    switch (event.button) {
      case Aiv0Button.main:
        if (h20HardwareTestModeEnabled) {
          if (h20HardwareTestPhase == H20HardwareTestPhase.playing ||
              h20HardwareTestPhase == H20HardwareTestPhase.openingRoute) {
            await _syncAiv0AppState(
              resultCode: Aiv0AppResult.busy,
              sequence: sequence,
            );
            return;
          }
          await toggleH20OfflineRecordingTest();
          await _syncAiv0AppState(sequence: sequence);
          return;
        }
        if (phase == ConversationPhase.processing) {
          await _syncAiv0AppState(
            resultCode: Aiv0AppResult.busy,
            sequence: sequence,
          );
          return;
        }
        if (_playbackPlaying) await _playbackService.stop();
        if (phase == ConversationPhase.recording) {
          await stopRecording(manual: true);
        } else {
          await startRecording();
        }
        await _syncAiv0AppState(sequence: sequence);
        return;
      case Aiv0Button.unknown:
        transientMessage =
            'Đã bỏ qua mã nút chưa hỗ trợ: ${event.rawHex}. V1 chỉ dùng MAIN.';
        notifyListeners();
        return;
    }
  }

  Aiv0AppState get _currentAiv0AppState {
    if (h20HardwareTestPhase == H20HardwareTestPhase.recording) {
      return Aiv0AppState.recording;
    }
    if (h20HardwareTestPhase == H20HardwareTestPhase.playing) {
      return Aiv0AppState.playing;
    }
    if (h20HardwareTestPhase == H20HardwareTestPhase.error) {
      return Aiv0AppState.error;
    }
    if (_playbackPlaying) return Aiv0AppState.playing;
    return switch (phase) {
      ConversationPhase.recording => Aiv0AppState.recording,
      ConversationPhase.processing => Aiv0AppState.processing,
      ConversationPhase.ready => Aiv0AppState.ready,
      ConversationPhase.error => Aiv0AppState.error,
      _ => Aiv0AppState.idle,
    };
  }

  Future<void> _syncAiv0AppState({
    Aiv0AppResult resultCode = Aiv0AppResult.accepted,
    int sequence = 0,
  }) async {
    final control = _aiv0BleControl;
    if (control == null || !control.status.isConnected) return;
    try {
      await control.sendAppState(
        state: _currentAiv0AppState,
        result: resultCode,
        sequence: sequence,
      );
    } catch (error) {
      debugPrint('Cannot send AIV0 APP State: $error');
    }
  }

  Future<List<BluetoothAudioDevice>> scanInnotrikDevices() async {
    final control = _bluetoothAudioControl;
    if (control == null || isBusy) {
      return const <BluetoothAudioDevice>[];
    }
    transientMessage = 'Đang quét thiết bị INNOTRIK ở gần…';
    notifyListeners();
    try {
      final devices = await control.scanBluetoothDevices();
      transientMessage = devices.isEmpty
          ? 'Không tìm thấy INNOTRIK. Hãy bật thiết bị và đặt gần điện thoại.'
          : null;
      notifyListeners();
      return devices;
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectInnotrikDevice(BluetoothAudioDevice device) async {
    final control = _bluetoothAudioControl;
    if (control == null || isBusy) {
      return;
    }
    transientMessage = 'Đang kết nối ${device.displayName}…';
    notifyListeners();
    try {
      await control.connectBluetoothDevice(device.id);
      asrMode = AsrMode.deviceStreaming;
      transientMessage =
          'Đã kết nối Mic INNOTRIK. BLE streaming đã sẵn sàng để thử.';
      notifyListeners();
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnectInnotrikDevice() async {
    if (isBusy) {
      return;
    }
    await _bluetoothAudioControl?.disconnectBluetoothDevice();
    if (asrMode == AsrMode.deviceStreaming) {
      asrMode = supportsAndroidStreaming
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks;
    }
    transientMessage = 'Đã ngắt Mic INNOTRIK; ứng dụng sẽ dùng mic điện thoại.';
    notifyListeners();
  }

  Future<List<HfpAudioDevice>> findHfpDevices() async {
    final control = _hfpAudioControl;
    if (control == null || isBusy) {
      return const <HfpAudioDevice>[];
    }
    transientMessage = supportsBrowserHfp
        ? 'Đang kiểm tra mic Bluetooth mà trình duyệt cung cấp…'
        : 'Đang tìm thiết bị HFP đã ghép đôi…';
    notifyListeners();
    try {
      final devices = await control.findDevices();
      transientMessage = devices.isEmpty
          ? supportsBrowserHfp
                ? 'Trình duyệt chưa hiển thị mic Bluetooth. Hãy kết nối tai nghe trong Cài đặt hệ thống rồi thử lại.'
                : 'Không tìm thấy thiết bị HFP đã ghép đôi.'
          : null;
      notifyListeners();
      return devices;
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectHfpDevice(HfpAudioDevice device) async {
    final control = _hfpAudioControl;
    if (control == null || isBusy) {
      return;
    }
    transientMessage = supportsBrowserHfp
        ? 'Đang chọn mic Bluetooth ${device.displayName}…'
        : 'Đang kiểm tra HFP của ${device.displayName}…';
    notifyListeners();
    try {
      await control.connect(device);
      asrMode = AsrMode.hfpStreaming;
      transientMessage = supportsBrowserHfp
          ? 'Đã chọn mic HFP Web. Trình duyệt sẽ ghi âm từ thiết bị Bluetooth.'
          : 'Đã chọn mic HFP. Chế độ tiêu chuẩn sẽ nghe từ thiết bị Bluetooth.';
      notifyListeners();
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnectHfpDevice() async {
    if (isBusy) {
      return;
    }
    await _hfpAudioControl?.disconnect();
    if (asrMode == AsrMode.hfpStreaming) {
      asrMode = supportsBrowserHfp
          ? AsrMode.batchChunks
          : supportsAndroidStreaming
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks;
    }
    transientMessage = supportsBrowserHfp
        ? 'Đã bỏ chọn mic HFP Web; trình duyệt sẽ dùng mic mặc định.'
        : 'Đã bỏ chọn mic HFP; ứng dụng sẽ dùng mic điện thoại.';
    notifyListeners();
  }

  Future<void> setH20HardwareTestMode(bool enabled) async {
    if (enabled == h20HardwareTestModeEnabled) return;
    if (!enabled && h20HardwareTestActive) {
      await cancelH20HardwareTest();
    }
    h20HardwareTestModeEnabled = enabled;
    h20HardwareTestPhase = H20HardwareTestPhase.idle;
    h20HardwareTestMessage = enabled
        ? 'Chế độ kiểm tra cục bộ đã bật. Không gửi âm thanh lên cloud.'
        : null;
    notifyListeners();
  }

  /// Opens the verified HFP/SCO route and records locally. No repository or
  /// network API is touched. A second tap (or MAIN after ODM confirmation)
  /// stops capture and immediately replays the local file through H20.
  Future<void> toggleH20OfflineRecordingTest() async {
    if (h20HardwareTestPhase == H20HardwareTestPhase.recording) {
      await stopAndReplayH20OfflineRecording();
      return;
    }
    await startH20OfflineRecording();
  }

  Future<void> startH20OfflineRecording() async {
    if (!h20HardwareTestModeEnabled) {
      throw StateError('Hãy bật chế độ kiểm tra phần cứng offline trước.');
    }
    if (h20HardwareTestActive ||
        phase == ConversationPhase.recording ||
        phase == ConversationPhase.processing) {
      return;
    }
    final hfp = _hfpAudioControl;
    if (hfp == null || !hfp.status.isConnected || supportsBrowserHfp) {
      throw StateError('Hãy kết nối HFP của H20 trước khi kiểm tra micro.');
    }

    h20HardwareTestResult = null;
    h20HardwareTestPhase = H20HardwareTestPhase.openingRoute;
    h20HardwareTestMessage = 'Đang mở đường HFP/SCO hai chiều…';
    notifyListeners();
    try {
      await _playbackService.stop();
      await hfp.startAudioRoute();
      _usingHfpRoute = true;
      _setPlaybackCommunicationRoute(true);
      final route = hfp.status;
      if (!route.routeActive || route.inputDeviceName == null) {
        throw StateError('Android chưa xác nhận micro H20 trên đường HFP/SCO.');
      }
      await _audioInput.start();
      _h20HardwareAudioInputStarted = true;
      h20HardwareTestPhase = H20HardwareTestPhase.recording;
      h20HardwareTestMessage =
          'Đang thu cục bộ từ ${route.inputDeviceName}. Bấm lại để dừng; tự dừng sau 5 giây.';
      _h20HardwareRecordingTimer?.cancel();
      _h20HardwareRecordingTimer = Timer(
        const Duration(seconds: 5),
        () => unawaited(stopAndReplayH20OfflineRecording()),
      );
      unawaited(_syncAiv0AppState());
      notifyListeners();
    } catch (error) {
      await _failH20HardwareTest(error);
      rethrow;
    }
  }

  Future<void> stopAndReplayH20OfflineRecording() async {
    if (h20HardwareTestPhase != H20HardwareTestPhase.recording ||
        _h20HardwareStopInProgress) {
      return;
    }
    _h20HardwareStopInProgress = true;
    _h20HardwareRecordingTimer?.cancel();
    _h20HardwareRecordingTimer = null;
    try {
      final capture = await _audioInput.stop();
      _h20HardwareAudioInputStarted = false;
      final routeBeforePlayback = hfpAudioStatus;
      h20HardwareTestPhase = H20HardwareTestPhase.playing;
      h20HardwareTestMessage = 'Đang phát lại bản ghi cục bộ qua loa H20…';
      notifyListeners();

      await _playH20TestUri(Uri.file(capture.filePath));
      final routeAfterPlayback = hfpAudioStatus;
      final inputName =
          routeBeforePlayback.inputDeviceName ??
          routeAfterPlayback.inputDeviceName;
      final outputName =
          routeAfterPlayback.outputDeviceName ??
          routeBeforePlayback.outputDeviceName;
      h20HardwareTestResult = H20HardwareTestResult(
        completedAt: DateTime.now(),
        inputRouteVerified:
            routeBeforePlayback.routeActive && inputName != null,
        outputRouteVerified:
            routeAfterPlayback.routeActive && outputName != null,
        recordedDuration: capture.duration,
        inputDeviceName: inputName,
        outputDeviceName: outputName,
      );
      h20HardwareTestPhase = H20HardwareTestPhase.completed;
      h20HardwareTestMessage =
          'Đã thu và phát lại hoàn toàn offline. Hãy xác nhận bạn có nghe giọng từ loa H20.';
      notifyListeners();
    } catch (error) {
      await _failH20HardwareTest(error);
      rethrow;
    } finally {
      _h20HardwareStopInProgress = false;
      await _closeH20HardwareAudioRoute();
      unawaited(_syncAiv0AppState());
    }
  }

  Future<void> playH20BundledSpeakerTest() async {
    if (!h20HardwareTestModeEnabled) {
      throw StateError('Hãy bật chế độ kiểm tra phần cứng offline trước.');
    }
    if (h20HardwareTestActive ||
        phase == ConversationPhase.recording ||
        phase == ConversationPhase.processing) {
      return;
    }
    final hfp = _hfpAudioControl;
    if (hfp == null || !hfp.status.isConnected || supportsBrowserHfp) {
      throw StateError('Hãy kết nối HFP của H20 trước khi kiểm tra loa.');
    }
    h20HardwareTestPhase = H20HardwareTestPhase.openingRoute;
    h20HardwareTestMessage = 'Đang mở HFP/SCO để kiểm tra loa…';
    notifyListeners();
    try {
      await _playbackService.stop();
      await hfp.startAudioRoute();
      _usingHfpRoute = true;
      _setPlaybackCommunicationRoute(true);
      if (!hfp.status.routeActive || hfp.status.outputDeviceName == null) {
        throw StateError('Android chưa xác nhận loa H20 trên đường HFP/SCO.');
      }
      h20HardwareTestPhase = H20HardwareTestPhase.playing;
      h20HardwareTestMessage = 'Đang phát file có sẵn trong APK qua H20…';
      notifyListeners();
      await _playH20TestUri(
        Uri.parse(
          'asset:assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3',
        ),
      );
      final route = hfp.status;
      h20HardwareTestResult = H20HardwareTestResult(
        completedAt: DateTime.now(),
        inputRouteVerified: false,
        outputRouteVerified:
            route.routeActive && route.outputDeviceName != null,
        outputDeviceName: route.outputDeviceName,
      );
      h20HardwareTestPhase = H20HardwareTestPhase.completed;
      h20HardwareTestMessage =
          'Đã phát file offline. Hãy xác nhận âm thanh phát từ loa H20.';
      notifyListeners();
    } catch (error) {
      await _failH20HardwareTest(error);
      rethrow;
    } finally {
      await _closeH20HardwareAudioRoute();
      unawaited(_syncAiv0AppState());
    }
  }

  void confirmH20PlaybackAudible(bool audible) {
    final current = h20HardwareTestResult;
    if (current == null) return;
    h20HardwareTestResult = current.copyWith(playbackAudible: audible);
    h20HardwareTestMessage = audible
        ? 'Đã xác nhận: âm thanh nghe được từ loa H20.'
        : 'Không nghe từ loa H20. Chưa đạt; cần kiểm tra lại route HFP/SCO.';
    notifyListeners();
  }

  Future<void> cancelH20HardwareTest() async {
    _h20HardwareRecordingTimer?.cancel();
    _h20HardwareRecordingTimer = null;
    if (_h20HardwareAudioInputStarted) {
      await _audioInput.cancel().catchError((Object _) {});
      _h20HardwareAudioInputStarted = false;
    }
    await _playbackService.stop().catchError((Object _) {});
    await _closeH20HardwareAudioRoute();
    h20HardwareTestPhase = H20HardwareTestPhase.idle;
    h20HardwareTestMessage = h20HardwareTestModeEnabled
        ? 'Đã dừng kiểm tra cục bộ.'
        : null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _playH20TestUri(Uri uri) async {
    final playback = _playbackService;
    final completion = playback is CompletionAwareAudioPlaybackService
        ? (playback as CompletionAwareAudioPlaybackService)
              .completionStream
              .first
              .timeout(const Duration(seconds: 20), onTimeout: () {})
        : null;
    await playback.play(uri);
    if (completion != null) await completion;
  }

  Future<void> _failH20HardwareTest(Object error) async {
    _h20HardwareRecordingTimer?.cancel();
    _h20HardwareRecordingTimer = null;
    if (_h20HardwareAudioInputStarted) {
      await _audioInput.cancel().catchError((Object _) {});
      _h20HardwareAudioInputStarted = false;
    }
    h20HardwareTestPhase = H20HardwareTestPhase.error;
    h20HardwareTestMessage = _friendlyError(error);
    await _closeH20HardwareAudioRoute();
    if (!_disposed) notifyListeners();
  }

  Future<void> _closeH20HardwareAudioRoute() async {
    if (_usingHfpRoute) await _stopHfpRoute();
  }

  Future<void> testInnotrikMicrophone() async {
    if (!canUseInnotrikBle || isBusy || _audioInput is! ChunkedAudioInput) {
      return;
    }
    bleDiagnosticRunning = true;
    transientMessage =
        'Kiểm tra Mic INNOTRIK trong 4 giây: hãy nói một câu rõ ràng…';
    notifyListeners();
    try {
      await _playbackService.stop();
      if (_audioInput is BluetoothCapturePolicy) {
        (_audioInput as BluetoothCapturePolicy).requireBluetoothCaptureOnce();
      }
      await _audioInput.startChunked();
      await Future<void>.delayed(const Duration(seconds: 4));
      final capture = await _audioInput.stop();
      final status = bluetoothAudioStatus;
      if ((capture.streamedAudioBytes ?? 0) < 8000) {
        throw StateError('Audio giải mã quá ngắn để xác nhận mic hoạt động.');
      }
      transientMessage =
          'Mic INNOTRIK đạt kiểm tra: ${status.packetCount} gói, '
          '${(capture.streamedAudioBytes ?? 0) ~/ 1024} KB PCM. '
          'Đang phát lại bản ghi.';
      notifyListeners();
      await _playbackService.play(Uri.file(capture.filePath));
    } catch (error) {
      await _audioInput.cancel().catchError((Object _) {});
      transientMessage =
          'Kiểm tra Mic INNOTRIK thất bại: ${_friendlyError(error)}';
      notifyListeners();
      rethrow;
    } finally {
      bleDiagnosticRunning = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> startRecording() async {
    if (!_audioInput.isAvailable || isBusy) {
      _setError('Nguồn âm thanh hiện chưa sẵn sàng.');
      return;
    }
    if (asrMode == AsrMode.hfpStreaming && !canUseHfp) {
      _setError('Hãy tìm và kết nối thiết bị HFP trước khi bắt đầu nói.');
      return;
    }

    try {
      final userGesturePlayback = _playbackService;
      if (userGesturePlayback is UserGestureAudioPlaybackService) {
        await (userGesturePlayback as UserGestureAudioPlaybackService)
            .unlockForUserGesture();
      }
      await _playbackService.stop();
      errorMessage = null;
      transientMessage = null;
      qualityApproved = null;
      _processingStageTimer?.cancel();
      processingStage = ConversationProcessingStage.recognizing;
      _speechDetected = false;
      _noisyRecording = false;
      _voiceActivityDetector.reset();
      _stopInProgress = false;
      _realtimeConnectionGeneration += 1;
      _realtimeConnectionFuture = null;
      _realtimeFallbackBuffer.clear();
      final preferAvailableBle =
          _preferBleStreaming &&
          _audioInput.isBluetooth &&
          _audioInput is ChunkedAudioInput;
      if (preferAvailableBle && asrMode == AsrMode.androidStreaming) {
        asrMode = AsrMode.deviceStreaming;
      } else if (!preferAvailableBle && asrMode == AsrMode.deviceStreaming) {
        asrMode = _streamingSpeechInput == null
            ? AsrMode.batchChunks
            : AsrMode.androidStreaming;
      }
      _usingHfpRoute = false;
      _usingStreamingSpeech =
          (asrMode == AsrMode.androidStreaming ||
              asrMode == AsrMode.hfpStreaming) &&
          _streamingSpeechInput != null &&
          !isBrowserHfpMode;
      _usingRealtimeTranscription = false;
      _usingOfflineIntent = false;
      _offlineIntentDecision = null;
      _offlineIntentFirstResultMs = null;
      _offlineIntentGate = null;
      _offlineFallbackTimer?.cancel();
      _offlineFallbackTimer = null;
      amplitude = 0;
      _previewGeneration += 1;
      _partialPreviewTimer?.cancel();
      _lastPreviewText = null;
      _preview = null;
      _preferredPlaybackUri = null;
      _speculativePreloadUri = null;
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      await _batchPreviewSubscription?.cancel();
      _batchPreviewSubscription = null;
      final previousAdaptiveWebUpload = _adaptiveWebUpload;
      _adaptiveWebUpload = null;
      if (previousAdaptiveWebUpload != null) {
        await previousAdaptiveWebUpload.discard();
      }
      final previousBatchUpload = _batchChunkUpload;
      _batchChunkUpload = null;
      _batchSpeechGate = null;
      if (previousBatchUpload != null) {
        await previousBatchUpload
            .discard(reason: 'superseded')
            .catchError((Object _) {});
      }
      await _realtimeChunkSubscription?.cancel();
      _realtimeChunkSubscription = null;
      await _realtimePartialSubscription?.cancel();
      _realtimePartialSubscription = null;
      await _offlineIntentHypothesisSubscription?.cancel();
      _offlineIntentHypothesisSubscription = null;
      await _offlineIntentRecognizer?.cancel().catchError((Object _) {});
      final previousRealtimeSession = _realtimeSession;
      _realtimeSession = null;
      if (previousRealtimeSession != null) {
        await previousRealtimeSession.discard().catchError((Object _) {});
      }

      if (_usingStreamingSpeech) {
        try {
          if (asrMode == AsrMode.hfpStreaming) {
            await _hfpAudioControl!.startAudioRoute();
            _usingHfpRoute = true;
            _setPlaybackCommunicationRoute(true);
          }
          await _streamingSpeechInput!.start();
        } catch (error) {
          final permissionFailure =
              error is StreamingSpeechInputException &&
              (error.code == 'MICROPHONE_PERMISSION_DENIED' ||
                  error.code == 'MICROPHONE_PERMISSION_PENDING');
          if (permissionFailure) {
            await _stopHfpRoute();
            rethrow;
          }
          _usingStreamingSpeech = false;
          final keepsHfpRoute = _usingHfpRoute;
          asrMode = AsrMode.batchChunks;
          transientMessage = keepsHfpRoute
              ? 'Nhận diện HFP trực tiếp chưa sẵn sàng; đang ghi âm HFP để gửi Cloudflare.'
              : 'Nhận diện Android trực tiếp chưa sẵn sàng; đang ghi âm để gửi Cloudflare.';
          await _startBatchRecording();
        }
      } else if (isBrowserHfpMode && _audioInput is ChunkedAudioInput) {
        try {
          await _hfpAudioControl!.startAudioRoute();
          _usingHfpRoute = true;
          _setPlaybackCommunicationRoute(true);
          await _startAdaptiveWebRecording();
        } catch (_) {
          await _stopHfpRoute();
          rethrow;
        }
      } else if (asrMode == AsrMode.openAiRealtime ||
          asrMode == AsrMode.deviceStreaming) {
        if (asrMode == AsrMode.deviceStreaming) {
          if (_audioInput is BluetoothCapturePolicy) {
            (_audioInput as BluetoothCapturePolicy)
                .requireBluetoothCaptureOnce();
          }
          await _startBleHybridRecording();
        } else {
          await _startRealtimeRecordingWithBatchFallback();
        }
      } else if (_isWebRuntime && _audioInput is ChunkedAudioInput) {
        await _startAdaptiveWebRecording();
      } else {
        await _startBatchRecording();
      }

      _recordingStartedAt = DateTime.now();
      phase = ConversationPhase.recording;
      unawaited(_syncAiv0AppState());
      _listenToAmplitude(
        _usingStreamingSpeech
            ? _streamingSpeechInput!.amplitudeDbfs
            : _audioInput.amplitudeDbfs,
      );
      _maximumDurationTimer = Timer(
        const Duration(seconds: 12),
        () => unawaited(stopRecording(manual: false)),
      );
      _noSpeechTimer = Timer(const Duration(seconds: 3), () {
        if (phase == ConversationPhase.recording && !_speechDetected) {
          unawaited(stopRecording(manual: false));
        }
      });
      notifyListeners();
    } catch (error) {
      _setError(_friendlyError(error));
    }
  }

  Future<void> _startBleHybridRecording() async {
    final chunkedInput = _audioInput is ChunkedAudioInput ? _audioInput : null;
    final catalog = _repository is OfflineIntentCatalogRepository
        ? _repository as OfflineIntentCatalogRepository
        : null;
    final recognizer = _offlineIntentRecognizer;

    if (chunkedInput == null ||
        catalog == null ||
        recognizer == null ||
        !await recognizer.checkAvailability()) {
      transientMessage =
          'ASR offline BLE chưa sẵn sàng; đang gửi Batch Chunks qua Cloudflare.';
      await _startBatchRecording();
      return;
    }

    try {
      final manifest = await catalog.fetchOfflineIntentManifest();
      if (manifest.items.isEmpty) {
        throw StateError('Backend chưa có offline intent manifest.');
      }
      _offlineIntentManifest = manifest;
      _offlineIntentGate = OfflineIntentGate(manifest.policy);
      _offlineIntentDecision = null;
      _offlineIntentHypothesisSubscription = recognizer.hypotheses.listen(
        _onOfflineIntentHypothesis,
        onError: (Object error) {
          debugPrint('BLE offline intent failed: $error');
          _markOfflineBatchFallback();
        },
      );
      await recognizer.start(manifest: manifest);
      _realtimeChunkSubscription = chunkedInput.audioChunks.listen(
        (bytes) {
          _realtimeFallbackBuffer.add(bytes);
          recognizer.addAudioChunk(bytes);
          _realtimeSession?.addAudioChunk(bytes);
        },
        onError: (Object error) {
          debugPrint('BLE hybrid audio stream failed: $error');
          _markOfflineBatchFallback(audioStreamFailed: true);
        },
      );
      await chunkedInput.startChunked();
      _usingOfflineIntent = true;
      transientMessage =
          'BLE offline đang nghe; câu lạ sẽ được gửi Batch Chunks qua Cloudflare.';
    } catch (error) {
      await _offlineIntentHypothesisSubscription?.cancel();
      _offlineIntentHypothesisSubscription = null;
      await _realtimeChunkSubscription?.cancel();
      _realtimeChunkSubscription = null;
      await recognizer.cancel().catchError((Object _) {});
      await chunkedInput.cancel().catchError((Object _) {});
      _usingOfflineIntent = false;
      _offlineIntentGate = null;
      _offlineIntentDecision = null;
      _realtimeFallbackBuffer.clear();
      transientMessage =
          'ASR offline BLE chưa sẵn sàng; đang gửi Batch Chunks qua Cloudflare.';
      await _startBatchRecording();
    }
  }

  void _onOfflineIntentHypothesis(OfflineIntentHypothesis hypothesis) {
    if (!_usingOfflineIntent || phase != ConversationPhase.recording) {
      return;
    }
    _registerSpeechDetection(confirmDetector: true);
    final decision = _offlineIntentGate?.evaluate(hypothesis);
    if (decision == null) {
      return;
    }
    _offlineIntentDecision = decision;
    final startedAt = _recordingStartedAt;
    _offlineIntentFirstResultMs ??= startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    _offlineFallbackTimer?.cancel();
    _offlineFallbackTimer = null;

    OfflineIntentDefinition? definition;
    for (final item in _offlineIntentManifest?.items ?? const []) {
      if (item.id == decision.hypothesis.intentId &&
          item.contexts.contains(context.apiValue)) {
        definition = item;
        break;
      }
    }
    if (definition != null) {
      _preview = ConversationPreview(
        sourceText: decision.hypothesis.transcript.trim(),
        englishText: definition.englishText,
        textSource: 'offline_intent',
        audioUri: definition.audioUri,
      );
      unawaited(_playbackService.preload(definition.audioUri));
    }
    notifyListeners();
  }

  void _scheduleOfflineFallback() {
    if (!_usingOfflineIntent ||
        _offlineIntentDecision != null ||
        _offlineFallbackTimer != null) {
      return;
    }
    final delay = _offlineIntentManifest?.policy.earlyFallbackMs ?? 800;
    _offlineFallbackTimer = Timer(Duration(milliseconds: delay), () {
      _offlineFallbackTimer = null;
      if (_offlineIntentDecision == null &&
          phase == ConversationPhase.recording) {
        _markOfflineBatchFallback();
      }
    });
  }

  void _markOfflineBatchFallback({bool audioStreamFailed = false}) {
    if (!_usingOfflineIntent || _offlineIntentDecision != null) {
      return;
    }
    if (audioStreamFailed) {
      // A broken chunk stream may only contain part of the utterance. Clearing
      // it forces the safe full-file upload path at stop instead of sending a
      // truncated Batch Chunks session.
      _realtimeFallbackBuffer.clear();
    }
    transientMessage = audioStreamFailed
        ? 'Luồng BLE bị gián đoạn; sẽ gửi file ghi âm đầy đủ qua Cloudflare.'
        : 'Câu chưa đủ chắc chắn; sẽ gửi Batch Chunks qua Cloudflare khi dừng.';
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _startRealtimeRecordingWithBatchFallback() async {
    final chunkedInput = _audioInput is ChunkedAudioInput ? _audioInput : null;
    final realtimeRepository = _repository is RealtimeConversationRepository
        ? _repository as RealtimeConversationRepository
        : null;

    if (chunkedInput == null || realtimeRepository == null) {
      transientMessage = 'Chế độ AI chưa khả dụng; đang dùng xử lý dự phòng.';
      await _startBatchRecording();
      return;
    }

    final recordingStartedAt = DateTime.now();
    final connectionGeneration = ++_realtimeConnectionGeneration;
    _realtimeChunkSubscription = chunkedInput.audioChunks.listen(
      (bytes) {
        final realtimeSession = _realtimeSession;
        if (realtimeSession == null || _realtimeBatchFallback) {
          _realtimeFallbackBuffer.add(bytes);
        }
        realtimeSession?.addAudioChunk(bytes);
      },
      onError: (Object error) {
        debugPrint('Legacy Realtime audio stream failed: $error');
      },
    );

    final connectionFuture = _connectRealtimeInBackground(
      repository: realtimeRepository,
      connectionGeneration: connectionGeneration,
      recordingStartedAt: recordingStartedAt,
    );
    _realtimeConnectionFuture = connectionFuture;
    unawaited(
      connectionFuture.whenComplete(() {
        if (identical(_realtimeConnectionFuture, connectionFuture)) {
          _realtimeConnectionFuture = null;
        }
      }),
    );

    try {
      await chunkedInput.startChunked();
    } catch (error) {
      _realtimeConnectionGeneration += 1;
      _realtimeConnectionFuture = null;
      await _realtimeChunkSubscription?.cancel();
      _realtimeChunkSubscription = null;
      await _realtimePartialSubscription?.cancel();
      _realtimePartialSubscription = null;
      final session = _realtimeSession;
      _realtimeSession = null;
      await chunkedInput.cancel().catchError((Object _) {});
      if (session != null) {
        await session.discard().catchError((Object _) {});
      }
      _usingRealtimeTranscription = false;
      _realtimeFallbackBuffer.clear();
      transientMessage = 'Chế độ AI chưa sẵn sàng; đang dùng xử lý dự phòng.';
      await _startBatchRecording();
    }
  }

  Future<void> _connectRealtimeInBackground({
    required RealtimeConversationRepository repository,
    required int connectionGeneration,
    required DateTime recordingStartedAt,
  }) async {
    RealtimeTranscriptionSession? session;
    try {
      session = await repository.startRealtimeTranscription(
        audioInputLabel: _audioInput.label,
        bluetoothAudioInput: _audioInput.isBluetooth,
      );
      if (_disposed || connectionGeneration != _realtimeConnectionGeneration) {
        await session.discard().catchError((Object _) {});
        return;
      }

      session.markRecordingStarted(recordingStartedAt);
      _realtimeSession = session;
      _realtimeFallbackBuffer.replay(session.addAudioChunk);
      if (!_realtimeBatchFallback) {
        _realtimeFallbackBuffer.clear();
      }
      _usingRealtimeTranscription = true;
      _realtimePartialSubscription = session.partialText.listen(
        _onPartialText,
        onError: (Object error) {
          debugPrint('Legacy Realtime transcript failed: $error');
        },
      );
    } catch (error) {
      await session?.discard().catchError((Object _) {});
      if (_disposed || connectionGeneration != _realtimeConnectionGeneration) {
        return;
      }
      _usingRealtimeTranscription = false;
      transientMessage =
          'Realtime chưa kết nối; âm thanh vẫn được giữ để dùng Batch Chunks.';
      if (!_disposed) {
        notifyListeners();
      }
      debugPrint('Legacy Realtime background connection failed: $error');
    }
  }

  Future<void> _startBatchRecording() async {
    final chunkedInput = _audioInput is ChunkedAudioInput ? _audioInput : null;
    final chunkedRepository = _repository is ChunkedConversationRepository
        ? _repository as ChunkedConversationRepository
        : null;

    if (chunkedInput == null || chunkedRepository == null) {
      await _audioInput.start();
      return;
    }

    final gatedUpload = SpeechGatedBatchUploadSession();
    _batchSpeechGate = gatedUpload;
    try {
      _batchChunkSubscription = chunkedInput.audioChunks.listen(
        gatedUpload.addAudioChunk,
        onError: (Object error) {
          debugPrint('Batch audio stream failed: $error');
        },
      );
      final inputStart = chunkedInput.startChunked();
      final uploadStart = chunkedRepository.startBatchChunkUpload().then((
        session,
      ) {
        gatedUpload.attachDelegate(session);
        _batchChunkUpload = gatedUpload;
      });
      await Future.wait<void>(<Future<void>>[inputStart, uploadStart]);
    } catch (error) {
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      _batchChunkUpload = null;
      _batchSpeechGate = null;
      await chunkedInput.cancel().catchError((Object _) {});
      await gatedUpload.discard().catchError((Object _) {});
      transientMessage =
          'Batch Chunks chưa sẵn sàng; đang dùng upload file dự phòng.';
      await _audioInput.start();
    }
  }

  Future<void> _startAdaptiveWebRecording() async {
    final chunkedInput = _audioInput is ChunkedAudioInput ? _audioInput : null;
    final chunkedRepository = _repository is ChunkedConversationRepository
        ? _repository as ChunkedConversationRepository
        : null;
    if (chunkedInput == null || chunkedRepository == null) {
      await _audioInput.start();
      return;
    }

    final upload = _AdaptiveWebChunkUpload(
      repository: chunkedRepository,
      promotionDelay: _adaptiveWebUploadDelay,
    );
    upload.configureSpeculativePreview(context: context, childAge: _childAge);
    _adaptiveWebUpload = upload;
    _batchPreviewSubscription = upload.speculativePreviews.listen(
      _onSpeculativeBatchPreview,
      onError: (Object error) {
        debugPrint('Speculative Web preview failed: $error');
      },
    );
    _batchChunkSubscription = chunkedInput.audioChunks.listen(
      upload.addAudioChunk,
      onError: (Object error) {
        debugPrint('Adaptive Web audio stream failed: $error');
      },
    );
    upload.schedulePromotion();

    try {
      await chunkedInput.startChunked();
    } catch (_) {
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      await _batchPreviewSubscription?.cancel();
      _batchPreviewSubscription = null;
      _adaptiveWebUpload = null;
      await upload.discard();
      rethrow;
    }
  }

  void _beginProcessingStages() {
    _processingStageTimer?.cancel();
    processingStage = ConversationProcessingStage.recognizing;
    _processingStageTimer = Timer(const Duration(milliseconds: 700), () {
      if (_disposed || phase != ConversationPhase.processing) {
        return;
      }
      processingStage = ConversationProcessingStage.translating;
      notifyListeners();
    });
  }

  void _registerSpeechDetection({bool confirmDetector = false}) {
    if (confirmDetector) {
      _voiceActivityDetector.confirmSpeech();
    }
    final firstSpeechFrame = !_speechDetected;
    _speechDetected = true;
    _batchSpeechGate?.markSpeechDetected();
    _adaptiveWebUpload?.markSpeculativeSpeechDetected();
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (firstSpeechFrame) {
      _scheduleOfflineFallback();
    }
  }

  void _listenToAmplitude(Stream<double> amplitudeStream) {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = amplitudeStream.listen((dbfs) {
      if (phase != ConversationPhase.recording) {
        return;
      }

      amplitude = ((dbfs + 60) / 48).clamp(0.0, 1.0).toDouble();
      final startedAt = _recordingStartedAt;
      final activity = _voiceActivityDetector.addSample(
        dbfs,
        elapsed: startedAt == null
            ? Duration.zero
            : DateTime.now().difference(startedAt),
      );
      _noisyRecording = _noisyRecording || activity.noisyEnvironment;
      if (activity.speechStarted) {
        _registerSpeechDetection();
      }
      if (activity.voiceActive) {
        _batchSpeechGate?.markVoiceActive();
        _adaptiveWebUpload?.markSpeculativeVoiceActive();
        _silenceTimer?.cancel();
        _silenceTimer = null;
      } else if (_speechDetected &&
          !activity.isCalibrating &&
          _silenceTimer == null) {
        _batchSpeechGate?.markVoiceInactive();
        _adaptiveWebUpload?.markSpeculativeVoiceInactive();
        _silenceTimer = Timer(
          Duration(milliseconds: vadSilenceMs),
          () => unawaited(stopRecording(manual: false)),
        );
      }
      notifyListeners();
    }, onError: (Object error) => _setError(_friendlyError(error)));
  }

  void _onPartialText(String sourceText) {
    if (phase != ConversationPhase.recording ||
        (!_usingStreamingSpeech && !_usingRealtimeTranscription)) {
      return;
    }
    final normalized = sourceText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 5 || normalized.split(' ').length < 2) {
      return;
    }
    _registerSpeechDetection(confirmDetector: true);
    _partialPreviewTimer?.cancel();
    final generation = _previewGeneration;
    final previewContext = context;
    if (_applyLocalExactPreview(normalized, targetContext: previewContext)) {
      _lastPreviewText = normalized;
      return;
    }
    _partialPreviewTimer = Timer(const Duration(milliseconds: 300), () {
      if (_lastPreviewText == normalized) {
        return;
      }
      _lastPreviewText = normalized;
      unawaited(
        _loadPartialPreview(
          normalized,
          previewContext: previewContext,
          generation: generation,
        ),
      );
    });
  }

  void _onSpeculativeBatchPreview(ConversationPreview preview) {
    if (!_isWebRuntime ||
        (phase != ConversationPhase.recording &&
            phase != ConversationPhase.processing) ||
        preview.englishText.trim().isEmpty) {
      return;
    }
    _preview = preview;
    final audioUri = preview.audioUri;
    if (audioUri != null) {
      _preferredPlaybackUri = audioUri;
      _speculativePreloadUri = audioUri;
      final preload = _playbackService.preload(audioUri).catchError((
        Object error,
      ) {
        debugPrint('Speculative Web audio preload was skipped: $error');
      });
      // Browser preload assigns the source to the persistent HTMLAudioElement
      // synchronously before this future first yields. Finalization only reuses
      // this source when the committed result returns the exact same URI.
      unawaited(preload);
    }
  }

  Future<void> _loadPartialPreview(
    String sourceText, {
    required PracticeContext previewContext,
    required int generation,
  }) async {
    try {
      final preview = await _repository.previewStreamingText(
        sourceText: sourceText,
        context: previewContext,
        childAge: _childAge,
      );
      if (preview == null ||
          preview.audioUri == null ||
          generation != _previewGeneration ||
          phase != ConversationPhase.recording ||
          context != previewContext) {
        return;
      }
      _preview = preview;
      await _playbackService.preload(preview.audioUri!);
    } catch (error) {
      debugPrint('Partial rule preload was skipped: $error');
    }
  }

  Future<void> stopRecording({required bool manual}) async {
    if (phase != ConversationPhase.recording || _stopInProgress) {
      return;
    }
    _stopInProgress = true;
    _adaptiveWebUpload?.markStopRequested(manual: manual);
    _partialPreviewTimer?.cancel();
    _previewGeneration += 1;
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _maximumDurationTimer?.cancel();
    _offlineFallbackTimer?.cancel();
    _offlineFallbackTimer = null;
    await _amplitudeSubscription?.cancel();
    _stoppedAt = DateTime.now();
    _responseReceivedAt = null;
    _AdaptiveWebChunkUpload? stoppedAdaptiveWebUpload;

    try {
      final startedAt = _recordingStartedAt;
      final elapsed = startedAt == null
          ? Duration.zero
          : _stoppedAt!.difference(startedAt);
      if (elapsed < const Duration(milliseconds: 450)) {
        _realtimeConnectionGeneration += 1;
        _realtimeConnectionFuture = null;
        if (_usingStreamingSpeech) {
          await _streamingSpeechInput!.cancel();
        } else {
          await _audioInput.cancel();
        }
        await _batchChunkSubscription?.cancel();
        _batchChunkSubscription = null;
        final adaptiveWebUpload = _adaptiveWebUpload;
        _adaptiveWebUpload = null;
        if (adaptiveWebUpload != null) {
          await adaptiveWebUpload.discard();
        }
        await _realtimeChunkSubscription?.cancel();
        _realtimeChunkSubscription = null;
        await _realtimePartialSubscription?.cancel();
        _realtimePartialSubscription = null;
        await _offlineIntentHypothesisSubscription?.cancel();
        _offlineIntentHypothesisSubscription = null;
        await _offlineIntentRecognizer?.cancel().catchError((Object _) {});
        final realtimeSession = _realtimeSession;
        _realtimeSession = null;
        if (realtimeSession != null) {
          await realtimeSession.discard().catchError((Object _) {});
        }
        final batchUpload = _batchChunkUpload;
        _batchChunkUpload = null;
        _batchSpeechGate = null;
        if (batchUpload != null) {
          await batchUpload
              .discard(reason: 'recording_too_short')
              .catchError((Object _) {});
        }
        phase = ConversationPhase.idle;
        unawaited(_syncAiv0AppState());
        transientMessage = 'Hãy nói lâu hơn một chút nhé.';
        _stopInProgress = false;
        notifyListeners();
        return;
      }

      // Cloud ASR inputs can still return PCM bytes when the selected
      // microphone is muted, disconnected, too far away or only captures
      // background noise. Never upload an unconfirmed cloud recording: ASR
      // could otherwise produce a confident-looking hallucination. Preserve
      // the existing manual-stop behavior for Android SpeechRecognizer, which
      // has its own transcript/confidence checks.
      if (!_speechDetected && (!_usingStreamingSpeech || !manual)) {
        _realtimeConnectionGeneration += 1;
        _realtimeConnectionFuture = null;
        if (_usingStreamingSpeech) {
          await _streamingSpeechInput!.cancel();
        } else {
          await _audioInput.cancel();
        }
        await _batchChunkSubscription?.cancel();
        _batchChunkSubscription = null;
        final adaptiveWebUpload = _adaptiveWebUpload;
        _adaptiveWebUpload = null;
        if (adaptiveWebUpload != null) {
          await adaptiveWebUpload.discard();
        }
        await _realtimeChunkSubscription?.cancel();
        _realtimeChunkSubscription = null;
        await _realtimePartialSubscription?.cancel();
        _realtimePartialSubscription = null;
        await _offlineIntentHypothesisSubscription?.cancel();
        _offlineIntentHypothesisSubscription = null;
        await _offlineIntentRecognizer?.cancel().catchError((Object _) {});
        final realtimeSession = _realtimeSession;
        _realtimeSession = null;
        if (realtimeSession != null) {
          await realtimeSession.discard().catchError((Object _) {});
        }
        final batchUpload = _batchChunkUpload;
        _batchChunkUpload = null;
        _batchSpeechGate = null;
        if (batchUpload != null) {
          await batchUpload
              .discard(reason: 'no_speech')
              .catchError((Object _) {});
        }
        phase = ConversationPhase.idle;
        unawaited(_syncAiv0AppState());
        transientMessage = _noisyRecording
            ? 'Môi trường đang khá ồn. Hãy đưa micro gần hơn, tránh hướng quạt hoặc chuyển sang chỗ yên hơn rồi thử lại.'
            : _unclearSpeechMessage;
        unawaited(_speakUnclearSpeechPrompt());
        _stopInProgress = false;
        notifyListeners();
        return;
      }

      StreamingSpeechCapture? streamingCapture;
      AudioCapture? audioCapture;
      BatchChunkUploadSession? realtimeFallbackUpload;
      BatchChunkUploadSession? adaptiveWebUpload;
      if (_usingStreamingSpeech) {
        try {
          streamingCapture = await _streamingSpeechInput!.stop();
        } catch (error) {
          _usingStreamingSpeech = false;
          asrMode = AsrMode.batchChunks;
          throw StreamingSpeechInputException(
            'Nhận diện trực tiếp bị gián đoạn. Ứng dụng đã chuyển sang Cloudflare Batch Chunks; hãy nói lại câu vừa rồi.',
            code: 'STREAMING_FAILED_USE_BATCH',
          );
        }
        if (_usingHfpRoute) {
          streamingCapture = StreamingSpeechCapture(
            sourceText: streamingCapture.sourceText,
            duration: streamingCapture.duration,
            inputLabel: inputLabel,
            confidence: streamingCapture.confidence,
            firstResultMs: streamingCapture.firstResultMs,
            finalAfterStopMs: streamingCapture.finalAfterStopMs,
            asrMode: AsrMode.hfpStreaming.apiValue,
            isBluetoothInput: true,
            initialNoiseRms: streamingCapture.initialNoiseRms,
          );
        }
      } else {
        final adaptiveUpload = _adaptiveWebUpload;
        _adaptiveWebUpload = null;
        stoppedAdaptiveWebUpload = adaptiveUpload;
        adaptiveUpload?.markSpeculativeVoiceInactive();
        final promotionReady = adaptiveUpload?.waitUntilPromoted();
        final audioStop = _audioInput.stop();
        audioCapture = await audioStop;
        if (promotionReady != null) {
          await promotionReady;
        }
        // PhoneMicrophoneInput.stop() has now emitted its final PCM frame.
        // Snapshot it before sealing the adaptive upload so prefetch covers the
        // real end of the utterance rather than the earlier VAD transition.
        adaptiveUpload?.requestTerminalSpeculativePreview();
        if (adaptiveUpload != null) {
          adaptiveWebUpload = await adaptiveUpload.stopAndTakeSession();
        }
        if (_usingHfpRoute && !supportsBrowserHfp) {
          audioCapture = AudioCapture(
            filePath: audioCapture.filePath,
            mimeType: audioCapture.mimeType,
            duration: audioCapture.duration,
            inputLabel: inputLabel,
            isBluetoothInput: true,
            initialNoiseRms: audioCapture.initialNoiseRms,
            streamHeaderBytes: audioCapture.streamHeaderBytes,
            streamedAudioBytes: audioCapture.streamedAudioBytes,
            recordingSampleRate: audioCapture.recordingSampleRate,
            dataBytes: audioCapture.dataBytes,
          );
        }
      }
      if (_usingOfflineIntent) {
        final finalHypothesis = await _offlineIntentRecognizer?.stop();
        if (finalHypothesis != null) {
          _onOfflineIntentHypothesis(finalHypothesis);
        }
        final decision = _offlineIntentDecision;
        if (decision != null) {
          streamingCapture = StreamingSpeechCapture(
            sourceText: decision.hypothesis.transcript.trim(),
            duration: audioCapture?.duration ?? elapsed,
            inputLabel: audioCapture?.inputLabel ?? _audioInput.label,
            confidence: decision.hypothesis.confidence,
            firstResultMs: _offlineIntentFirstResultMs,
            finalAfterStopMs: 0,
            asrMode: AsrMode.bleOfflineIntent.apiValue,
            isBluetoothInput: true,
            initialNoiseRms: audioCapture?.initialNoiseRms,
          );
        }
        await _offlineIntentHypothesisSubscription?.cancel();
        _offlineIntentHypothesisSubscription = null;
      }
      await _waitForRealtimeConnectionAtStop();
      _realtimeConnectionGeneration += 1;
      _realtimeConnectionFuture = null;
      await _realtimeChunkSubscription?.cancel();
      _realtimeChunkSubscription = null;
      await _realtimePartialSubscription?.cancel();
      _realtimePartialSubscription = null;
      final realtimeSession = _realtimeSession;
      _realtimeSession = null;
      if (realtimeSession != null) {
        try {
          streamingCapture = await realtimeSession.finalize();
        } catch (error) {
          debugPrint(
            'Legacy Realtime finalize failed; preparing Batch Chunks fallback: $error',
          );
          realtimeFallbackUpload = await _prepareRealtimeBatchFallback();
          transientMessage = realtimeFallbackUpload == null
              ? 'Realtime không ổn định; đã chuyển sang gửi WAV dự phòng.'
              : 'Realtime không ổn định; đã chuyển sang Batch Chunks dự phòng.';
        }
      } else if (streamingCapture == null &&
          audioCapture != null &&
          _batchChunkUpload == null) {
        realtimeFallbackUpload = await _prepareRealtimeBatchFallback();
        if (realtimeFallbackUpload != null) {
          transientMessage =
              'Đang gửi phần ghi âm qua Cloudflare Batch Chunks.';
        }
      }
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      final batchUpload =
          _batchChunkUpload ?? adaptiveWebUpload ?? realtimeFallbackUpload;
      _batchChunkUpload = null;
      _batchSpeechGate = null;
      _realtimeFallbackBuffer.clear();
      _usingOfflineIntent = false;
      phase = ConversationPhase.processing;
      unawaited(_syncAiv0AppState());
      _beginProcessingStages();
      amplitude = 0;
      notifyListeners();

      Future<PlaybackStartMetrics>? earlyRulePlayback;
      DateTime? earlyRulePlaybackRequestedAt;
      Uri? earlyRulePlaybackUri;
      String? earlyRuleEnglishText;
      if (streamingCapture != null) {
        final matchedLocalRule = _applyLocalExactPreview(
          streamingCapture.sourceText,
          targetContext: context,
        );
        final localPreview = _preview;
        if (matchedLocalRule && localPreview?.audioUri != null) {
          final localAudioUri = localPreview!.audioUri!;
          earlyRulePlaybackUri = localAudioUri;
          earlyRuleEnglishText = localPreview.englishText.trim();
          earlyRulePlaybackRequestedAt = DateTime.now();
          earlyRulePlayback = _playbackService.play(localAudioUri);
        }
      }

      final resultFuture = streamingCapture != null
          ? _repository.processStreamingText(
              capture: streamingCapture,
              context: context,
              childAge: _childAge,
              vadSilenceMs: vadSilenceMs,
            )
          : batchUpload != null
          ? _finalizeBatchChunksWithFallback(
              upload: batchUpload,
              capture: audioCapture!,
            )
          : _repository.processAudio(
              capture: audioCapture!,
              context: context,
              childAge: _childAge,
              vadSilenceMs: vadSilenceMs,
            );
      final processing = await Future.wait<Object?>([
        earlyRulePlayback == null
            ? _playbackService.prepare()
            : Future<void>.value(),
        resultFuture,
      ]);
      final nextResult = processing[1]! as ConversationResult;
      _responseReceivedAt = DateTime.now();
      // Do not wait for a late preview HTTP request before starting Safari
      // playback. The forwarding stream stays alive through finalize, so any
      // already-delivered terminal preview can still supply the exact
      // preloaded HTMLAudioElement source below. Cleanup happens only after
      // playback has started (or in finally on error).
      final preview = _preview;
      final preparedPreviewMatchesResult =
          preview?.audioUri != null &&
          preview!.englishText.trim() == nextResult.englishText.trim() &&
          preview.audioUri == nextResult.audioUri;
      if (preparedPreviewMatchesResult) {
        _preferredPlaybackUri = preview.audioUri;
      } else {
        // A different signed URL means finalize did not commit the preparation
        // that owns the current HTMLAudioElement. Do not play stale speculative
        // audio merely because its English text happens to be equal.
        _preferredPlaybackUri = nextResult.audioUri;
        if (_speculativePreloadUri != nextResult.audioUri) {
          _speculativePreloadUri = null;
        }
      }
      result = nextResult;
      _processingStageTimer?.cancel();
      processingStage = ConversationProcessingStage.preparingAudio;
      errorMessage = null;
      notifyListeners();

      var reusedEarlyRulePlayback = false;
      final canReuseEarlyRulePlayback =
          earlyRulePlayback != null &&
          earlyRulePlaybackRequestedAt != null &&
          earlyRulePlaybackUri != null &&
          earlyRuleEnglishText == nextResult.englishText.trim() &&
          (_preferredPlaybackUri == earlyRulePlaybackUri ||
              nextResult.audioUri == earlyRulePlaybackUri);
      if (canReuseEarlyRulePlayback) {
        try {
          final metrics = await earlyRulePlayback;
          final startedAt = earlyRulePlaybackRequestedAt.add(
            metrics.startedAfterRequest,
          );
          _reportPlaybackStarted(
            currentResult: nextResult,
            startedAt: startedAt,
            metrics: metrics,
          );
          reusedEarlyRulePlayback = true;
        } catch (error) {
          debugPrint('Early exact-rule playback failed: $error');
        }
      }
      if (!reusedEarlyRulePlayback && earlyRulePlayback != null) {
        await earlyRulePlayback.catchError((Object _) {
          return const PlaybackStartMetrics(
            audioLoadDuration: Duration.zero,
            startedAfterRequest: Duration.zero,
            fromDeviceCache: false,
          );
        });
        await _playbackService.stop();
      }
      if (!reusedEarlyRulePlayback &&
          (nextResult.audioUri != null || _preferredPlaybackUri != null)) {
        await playResult(reportLatency: true);
      }
      await stoppedAdaptiveWebUpload?.finishPreviewForwarding();
      stoppedAdaptiveWebUpload = null;
      await _batchPreviewSubscription?.cancel();
      _batchPreviewSubscription = null;
      phase = ConversationPhase.ready;
      unawaited(_syncAiv0AppState());
      notifyListeners();
    } catch (error) {
      _handleConversationError(error);
    } finally {
      await stoppedAdaptiveWebUpload?.finishPreviewForwarding();
      await _batchPreviewSubscription?.cancel();
      _batchPreviewSubscription = null;
      final adaptiveWebUpload = _adaptiveWebUpload;
      _adaptiveWebUpload = null;
      if (adaptiveWebUpload != null) {
        await adaptiveWebUpload.discard();
      }
      if (_usingHfpRoute && _playbackPlaying) {
        await _waitForActivePlaybackToComplete();
      }
      await _stopHfpRoute();
      _realtimeConnectionGeneration += 1;
      _realtimeConnectionFuture = null;
      _realtimeFallbackBuffer.clear();
      _stopInProgress = false;
    }
  }

  Future<void> _stopHfpRoute() async {
    if (!_usingHfpRoute) {
      return;
    }
    _usingHfpRoute = false;
    _setPlaybackCommunicationRoute(false);
    await _hfpAudioControl?.stopAudioRoute().catchError((Object error) {
      debugPrint('Cannot stop HFP audio route: $error');
    });
  }

  void _setPlaybackCommunicationRoute(bool active) {
    final playback = _playbackService;
    if (playback is CommunicationRouteAwareAudioPlaybackService) {
      (playback as CommunicationRouteAwareAudioPlaybackService)
          .setCommunicationRouteActive(active);
    }
  }

  Future<void> _waitForActivePlaybackToComplete() async {
    final playback = _playbackService;
    if (playback is! CompletionAwareAudioPlaybackService) return;
    try {
      await (playback as CompletionAwareAudioPlaybackService)
          .completionStream
          .first
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Timed out while keeping the HFP route open for playback.');
    }
  }

  Future<void> _waitForRealtimeConnectionAtStop() async {
    if (_realtimeSession != null) {
      return;
    }
    final pendingConnection = _realtimeConnectionFuture;
    if (pendingConnection == null) {
      return;
    }

    final waitStopwatch = Stopwatch()..start();
    try {
      await pendingConnection.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      debugPrint(
        '{"event":"openai_realtime_stop_wait_timeout",'
        '"waitMs":${waitStopwatch.elapsedMilliseconds}}',
      );
    } catch (error) {
      debugPrint('Legacy Realtime connection failed while stopping: $error');
    } finally {
      waitStopwatch.stop();
    }
  }

  Future<BatchChunkUploadSession?> _prepareRealtimeBatchFallback() async {
    if (!_realtimeBatchFallback || !_realtimeFallbackBuffer.canReplay) {
      return null;
    }
    final chunkedRepository = _repository is ChunkedConversationRepository
        ? _repository as ChunkedConversationRepository
        : null;
    if (chunkedRepository == null) {
      return null;
    }

    BatchChunkUploadSession? upload;
    try {
      upload = await chunkedRepository.startBatchChunkUpload();
      _realtimeFallbackBuffer.replay(upload.addAudioChunk);
      return upload;
    } catch (error) {
      debugPrint('Cannot prepare buffered Batch Chunks fallback: $error');
      await upload
          ?.discard(reason: 'fallback_prepare_failed')
          .catchError((Object _) {});
      return null;
    }
  }

  Future<ConversationResult> _finalizeBatchChunksWithFallback({
    required BatchChunkUploadSession upload,
    required AudioCapture capture,
  }) async {
    try {
      return await upload.finalize(
        capture: capture,
        context: context,
        childAge: _childAge,
        vadSilenceMs: vadSilenceMs,
      );
    } catch (error) {
      await upload.discard(reason: 'finalize_failed').catchError((Object _) {});
      if (_shouldSkipWavFallback(error)) {
        debugPrint(
          'Batch chunk request was rejected permanently; skipping WAV fallback.',
        );
        rethrow;
      }
      debugPrint('Batch chunk finalize failed; uploading WAV fallback: $error');
      transientMessage =
          'Mạng chunk không ổn định; đã chuyển sang gửi file WAV dự phòng.';
      notifyListeners();
      return _repository.processAudio(
        capture: capture,
        context: context,
        childAge: _childAge,
        vadSilenceMs: vadSilenceMs,
        fallbackReason: _batchFallbackReason(error),
      );
    }
  }

  bool _shouldSkipWavFallback(Object error) {
    if (error is! CodedConversationException) {
      return false;
    }
    return switch (error.errorCode) {
      'ASR_LOW_CONFIDENCE' ||
      'AUDIO_SESSION_UNAUTHORIZED' ||
      'AUDIO_SESSION_INVALID' ||
      'AUDIO_UPLOAD_LIMIT' ||
      'AUDIO_CHUNK_CONFLICT' ||
      'AUDIO_CHUNK_CHECKSUM_INVALID' ||
      'AUDIO_CHUNK_CHECKSUM_MISMATCH' ||
      'AUDIO_CHUNK_IDEMPOTENCY_INVALID' ||
      'AUDIO_CHUNK_ACK_MISMATCH' => true,
      _ => false,
    };
  }

  String _batchFallbackReason(Object error) {
    if (error is CodedConversationException && error.errorCode != null) {
      return error.errorCode!.toLowerCase();
    }
    return error is TimeoutException
        ? 'batch_timeout'
        : 'batch_transport_failure';
  }

  Future<void> playResult({bool reportLatency = false}) async {
    final currentResult = result;
    final audioUri = _preferredPlaybackUri ?? currentResult?.audioUri;
    if (currentResult == null) {
      return;
    }
    if (audioUri == null) {
      transientMessage =
          'Bản demo không tải âm thanh. Phiên bản đầy đủ sẽ phát câu tiếng Anh tại đây.';
      notifyListeners();
      return;
    }

    var openedHfpForReplay = false;
    try {
      if (asrMode == AsrMode.hfpStreaming && canUseHfp && !_usingHfpRoute) {
        await _hfpAudioControl!.startAudioRoute();
        _usingHfpRoute = true;
        openedHfpForReplay = true;
        _setPlaybackCommunicationRoute(true);
      }
      final playbackRequestedAt = DateTime.now();
      PlaybackStartMetrics? gestureMetrics;
      final gesturePlayback = _playbackService;
      if (!reportLatency &&
          gesturePlayback is DirectUserGestureAudioPlaybackService) {
        gestureMetrics =
            await (gesturePlayback as DirectUserGestureAudioPlaybackService)
                .playLoadedForUserGesture(audioUri);
      }
      final metrics = gestureMetrics ?? await _playbackService.play(audioUri);
      if (reportLatency && _stoppedAt != null) {
        _reportPlaybackStarted(
          currentResult: currentResult,
          startedAt: playbackRequestedAt.add(metrics.startedAfterRequest),
          metrics: metrics,
        );
      }
      if (_usingHfpRoute) {
        await _waitForActivePlaybackToComplete();
      }
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
    } finally {
      if (openedHfpForReplay) await _stopHfpRoute();
    }
  }

  void _reportPlaybackStarted({
    required ConversationResult currentResult,
    required DateTime startedAt,
    required PlaybackStartMetrics metrics,
  }) {
    final stoppedAt = _stoppedAt;
    if (stoppedAt == null) {
      return;
    }
    final firstAudioMs = math.max(
      0,
      startedAt.difference(stoppedAt).inMilliseconds,
    );
    final responseReceivedAt = _responseReceivedAt;
    final responseToPlaybackMs = responseReceivedAt == null
        ? null
        : math.max(0, startedAt.difference(responseReceivedAt).inMilliseconds);
    debugPrint(
      jsonEncode(<String, dynamic>{
        'event': 'playback_latency_client',
        'conversationId': currentResult.conversationId,
        'audioStartedAfterStopMs': firstAudioMs,
        'audioLoadMs': metrics.audioLoadDuration.inMilliseconds,
        'audioFromDeviceCache': metrics.fromDeviceCache,
        'responseToPlaybackMs': responseToPlaybackMs,
        'audioPreloadLoadedData': metrics.preloadedSourceLoaded,
        'audioPreloadCanPlay': metrics.preloadedSourceReady,
        'audioPreloadLoadedDataMs':
            metrics.preloadLoadedDuration?.inMilliseconds,
        'audioPreloadCanPlayMs': metrics.preloadReadyDuration?.inMilliseconds,
      }),
    );
    unawaited(
      _reportPlaybackLatency(
        currentResult: currentResult,
        timeToFirstAudioMs: firstAudioMs,
        audioLoadMs: metrics.audioLoadDuration.inMilliseconds,
        audioFromDeviceCache: metrics.fromDeviceCache,
        responseToPlaybackMs: responseToPlaybackMs,
        audioPreloadLoadedData: metrics.preloadedSourceLoaded,
        audioPreloadCanPlay: metrics.preloadedSourceReady,
        audioPreloadLoadedDataMs: metrics.preloadLoadedDuration?.inMilliseconds,
        audioPreloadCanPlayMs: metrics.preloadReadyDuration?.inMilliseconds,
      ),
    );
  }

  Future<void> _reportPlaybackLatency({
    required ConversationResult currentResult,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
    int? responseToPlaybackMs,
    bool? audioPreloadLoadedData,
    bool? audioPreloadCanPlay,
    int? audioPreloadLoadedDataMs,
    int? audioPreloadCanPlayMs,
  }) async {
    try {
      await _repository.patchPlaybackLatency(
        conversationId: currentResult.conversationId,
        timeToFirstAudioMs: timeToFirstAudioMs,
        audioLoadMs: audioLoadMs,
        audioFromDeviceCache: audioFromDeviceCache,
        responseToPlaybackMs: responseToPlaybackMs,
        audioPreloadLoadedData: audioPreloadLoadedData,
        audioPreloadCanPlay: audioPreloadCanPlay,
        audioPreloadLoadedDataMs: audioPreloadLoadedDataMs,
        audioPreloadCanPlayMs: audioPreloadCanPlayMs,
      );
    } catch (error) {
      debugPrint('Không thể gửi telemetry phát audio: $error');
    }
  }

  Future<void> submitReview(bool approved) async {
    final conversationId = result?.conversationId;
    if (conversationId == null) {
      return;
    }

    final previousValue = qualityApproved;
    qualityApproved = approved;
    notifyListeners();
    try {
      final learning = await _repository.review(
        conversationId: conversationId,
        approved: approved,
      );
      transientMessage = learning.message.isNotEmpty
          ? learning.message
          : approved
          ? 'Đã ghi nhận: đúng ý.'
          : 'Đã ghi nhận để cải thiện câu trả lời.';
      notifyListeners();
    } catch (error) {
      qualityApproved = previousValue;
      _setError(_friendlyError(error));
    }
  }

  Future<List<ConversationHistoryItem>> loadHistory() {
    return _repository.fetchHistory();
  }

  Future<void> playHistoryItem(ConversationHistoryItem item) async {
    final audioUri = item.audioUri;
    if (audioUri == null) {
      throw StateError('Lượt nói này chưa có âm thanh để phát lại.');
    }
    await _playbackService.play(audioUri);
  }

  Future<ConversationLearningOutcome> reviewHistoryItem(
    ConversationHistoryItem item,
    bool approved,
  ) {
    return _repository.review(
      conversationId: item.conversationId,
      approved: approved,
    );
  }

  Future<void> deleteHistoryItem(ConversationHistoryItem item) {
    return _repository.deleteHistoryItem(item.conversationId);
  }

  Future<void> clearHistory() {
    return _repository.clearHistory();
  }

  void selectContext(PracticeContext nextContext) {
    if (isBusy) {
      return;
    }
    context = nextContext;
    notifyListeners();
  }

  void selectAsrMode(AsrMode nextMode) {
    if (isBusy) {
      return;
    }
    if (nextMode == AsrMode.deviceStreaming) {
      if (!canUseInnotrikBle) {
        transientMessage =
            'Hãy quét và kết nối Mic INNOTRIK trước khi chọn BLE streaming.';
        notifyListeners();
        return;
      }
    }
    if (nextMode == AsrMode.hfpStreaming) {
      if (!canUseHfp) {
        transientMessage =
            'Hãy tìm và kết nối thiết bị HFP trước khi chọn HFP streaming.';
        notifyListeners();
        return;
      }
      if (_streamingSpeechInput == null && !supportsBrowserHfp) {
        transientMessage = 'HFP streaming chỉ khả dụng trên Android.';
        notifyListeners();
        return;
      }
    }
    if (nextMode == AsrMode.batchChunks) {
      transientMessage =
          'Đã chọn Cloudflare Batch Chunks; nhận dạng, dịch và phát âm đều dùng Cloudflare.';
    }
    if (nextMode == AsrMode.openAiRealtime) {
      transientMessage =
          'Chế độ Realtime cũ đã bị tắt. Ứng dụng chỉ dùng Cloudflare Batch Chunks.';
      notifyListeners();
      return;
    }
    if (nextMode == AsrMode.androidStreaming && _streamingSpeechInput == null) {
      transientMessage = 'Chế độ tiêu chuẩn không khả dụng trên nền tảng này.';
      notifyListeners();
      return;
    }
    asrMode = nextMode;
    notifyListeners();
  }

  void setVadSilence(int milliseconds) {
    if (isBusy) {
      return;
    }
    vadSilenceMs = milliseconds.clamp(400, 1600).toInt();
    notifyListeners();
  }

  void clearMessage() {
    transientMessage = null;
    if (phase == ConversationPhase.error) {
      _processingStageTimer?.cancel();
      phase = result == null ? ConversationPhase.idle : ConversationPhase.ready;
      errorMessage = null;
      unawaited(_syncAiv0AppState());
    }
    notifyListeners();
  }

  void _setError(String message) {
    _processingStageTimer?.cancel();
    errorMessage = message;
    phase = ConversationPhase.error;
    unawaited(_syncAiv0AppState(resultCode: Aiv0AppResult.internalError));
    if (!_disposed) {
      notifyListeners();
    }
  }

  static const _unclearSpeechMessage =
      'Mình chưa nghe rõ. Con đưa micro lại gần và nói rõ hơn nhé.';

  void _handleConversationError(Object error) {
    if (error is CodedConversationException &&
        error.errorCode == 'ASR_LOW_CONFIDENCE') {
      _setError(_unclearSpeechMessage);
      unawaited(_speakUnclearSpeechPrompt());
      return;
    }
    _setError(_friendlyError(error));
  }

  Future<void> _speakUnclearSpeechPrompt() async {
    await _voicePromptService?.speak(
      'Con đưa micro lại gần và nói rõ hơn nhé.',
    );
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'Kết nối backend quá chậm. Vui lòng thử lại.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeConnectionGeneration += 1;
    _realtimeConnectionFuture = null;
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _maximumDurationTimer?.cancel();
    _partialPreviewTimer?.cancel();
    _offlineFallbackTimer?.cancel();
    _processingStageTimer?.cancel();
    _h20HardwareRecordingTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_batchChunkSubscription?.cancel());
    unawaited(_batchPreviewSubscription?.cancel());
    unawaited(_realtimeChunkSubscription?.cancel());
    unawaited(_realtimePartialSubscription?.cancel());
    unawaited(_offlineIntentHypothesisSubscription?.cancel());
    final batchUpload = _batchChunkUpload;
    _batchSpeechGate = null;
    if (batchUpload != null) {
      unawaited(
        batchUpload
            .discard(reason: 'controller_dispose')
            .catchError((Object _) {}),
      );
    }
    final adaptiveWebUpload = _adaptiveWebUpload;
    if (adaptiveWebUpload != null) {
      unawaited(adaptiveWebUpload.discard());
    }
    final realtimeSession = _realtimeSession;
    if (realtimeSession != null) {
      unawaited(realtimeSession.discard().catchError((Object _) {}));
    }
    unawaited(_streamingCompletionSubscription?.cancel());
    unawaited(_partialTextSubscription?.cancel());
    unawaited(_bluetoothStatusSubscription?.cancel());
    unawaited(_hfpStatusSubscription?.cancel());
    unawaited(_aiv0StatusSubscription?.cancel());
    unawaited(_aiv0ButtonSubscription?.cancel());
    unawaited(_playbackPlayingSubscription?.cancel());
    if (_h20HardwareAudioInputStarted) {
      unawaited(_audioInput.cancel().catchError((Object _) {}));
    }
    unawaited(_stopHfpRoute());
    unawaited(_audioInput.dispose());
    unawaited(_streamingSpeechInput?.dispose());
    unawaited(_offlineIntentRecognizer?.dispose());
    unawaited(_hfpAudioControl?.dispose());
    unawaited(_aiv0BleControl?.dispose());
    unawaited(_playbackService.dispose());
    unawaited(_voicePromptService?.dispose());
    unawaited(_repository.dispose());
    super.dispose();
  }
}

class _AdaptiveWebChunkUpload {
  _AdaptiveWebChunkUpload({
    required this.repository,
    required this.promotionDelay,
  }) {
    _recordingStopwatch.start();
  }

  final ChunkedConversationRepository repository;
  final Duration promotionDelay;
  final List<Uint8List> _bufferedChunks = <Uint8List>[];
  final StreamController<ConversationPreview> _previewController =
      StreamController<ConversationPreview>.broadcast();

  static const _terminalPreviewDelay = Duration(milliseconds: 200);
  static const _pcmStableSilenceDuration = Duration(milliseconds: 50);
  static const _pcmConfirmedResumeDuration = Duration(milliseconds: 120);
  static const _pcmConfirmedResumeVariationDb = 3.0;
  static const _pcmSampleRate = 16000;
  static const _pcmAnalysisFrameSamples = _pcmSampleRate ~/ 100;

  Timer? _promotionTimer;
  Timer? _terminalPreviewTimer;
  Future<void>? _promotionFuture;
  BatchChunkUploadSession? _session;
  StreamSubscription<ConversationPreview>? _previewSubscription;
  PracticeContext? _previewContext;
  int? _previewChildAge;
  bool _speechDetected = false;
  bool _voiceActive = false;
  DateTime? _voiceInactiveAt;
  bool _terminalPreviewDispatched = false;
  bool _terminalPreviewPending = false;
  bool _acceptingChunks = true;
  final AdaptiveVoiceActivityDetector _pcmVoiceActivityDetector =
      AdaptiveVoiceActivityDetector();
  final Stopwatch _recordingStopwatch = Stopwatch();
  Duration _pcmElapsed = Duration.zero;
  Duration _pcmSilenceDuration = Duration.zero;
  Duration _pcmResumeDuration = Duration.zero;
  double _pcmResumeMinimumDbfs = 0;
  double _pcmResumeMaximumDbfs = -100;
  bool _pcmVoiceInactive = false;
  int? _pcmSilenceDetectedAtRecordingMs;
  int? _terminalTimerScheduledAtRecordingMs;
  int? _terminalRequestedAtRecordingMs;
  int? _stopRequestedAtRecordingMs;
  int _terminalTimerCanceledCount = 0;
  String? _terminalTimerLastCancelReason;
  String? _stopReason;

  Stream<ConversationPreview> get speculativePreviews =>
      _previewController.stream;

  void configureSpeculativePreview({
    required PracticeContext context,
    required int childAge,
  }) {
    _previewContext = context;
    _previewChildAge = childAge;
    final speculative = _session is SpeculativeBatchChunkUploadSession
        ? _session! as SpeculativeBatchChunkUploadSession
        : null;
    speculative?.configureSpeculativePreview(
      context: context,
      childAge: childAge,
    );
  }

  void markSpeculativeSpeechDetected() {
    if (_terminalPreviewDispatched || _terminalPreviewPending) {
      // A confirmed VAD speech-start event, rather than a raw noisy frame,
      // opens the next terminal generation.
      _terminalPreviewDispatched = false;
      _terminalPreviewPending = false;
    }
    _speechDetected = true;
    _pcmVoiceActivityDetector.confirmSpeech();
    final speculative = _session is SpeculativeBatchChunkUploadSession
        ? _session! as SpeculativeBatchChunkUploadSession
        : null;
    speculative?.markSpeculativeSpeechDetected();
  }

  void markSpeculativeVoiceActive({
    String resumeReason = 'primary_vad_resume',
  }) {
    final resumedAfterSilence = !_voiceActive && _voiceInactiveAt != null;
    if (resumedAfterSilence && resumeReason == 'primary_vad_resume') {
      // Safari's amplitude callback is useful for the UI/auto-stop timer but a
      // single post-silence frame is not proof that the child spoke again. Keep
      // the terminal alive until Raw PCM confirms a varying speech run; that
      // confirmation calls this method with pcm_confirmed_resume below.
      return;
    }
    _voiceActive = true;
    if (resumedAfterSilence) {
      _voiceInactiveAt = null;
      _cancelTerminalPreviewTimer(resumeReason);
    }
    final speculative = _session is SpeculativeBatchChunkUploadSession
        ? _session! as SpeculativeBatchChunkUploadSession
        : null;
    speculative?.markSpeculativeVoiceActive();
  }

  void markSpeculativeVoiceInactive() {
    final firstInactiveFrame = _voiceInactiveAt == null;
    _voiceActive = false;
    _voiceInactiveAt ??= DateTime.now();
    final speculative = _session is SpeculativeBatchChunkUploadSession
        ? _session! as SpeculativeBatchChunkUploadSession
        : null;
    if (firstInactiveFrame) {
      speculative?.markSpeculativeVoiceInactive();
    }
    if (!_acceptingChunks ||
        !_speechDetected ||
        _stopRequestedAtRecordingMs != null) {
      return;
    }
    // stopRecording() calls this method once more while the source is already
    // silent. Do not reset the early terminal timer at that boundary.
    if (_terminalPreviewDispatched ||
        _terminalPreviewPending ||
        _terminalPreviewTimer != null) {
      return;
    }
    _terminalTimerScheduledAtRecordingMs ??=
        _recordingStopwatch.elapsedMilliseconds;
    _terminalPreviewTimer = Timer(_terminalPreviewDelay, () {
      _terminalPreviewTimer = null;
      if (!_acceptingChunks || _voiceActive || !_speechDetected) {
        return;
      }
      _terminalRequestedAtRecordingMs ??=
          _recordingStopwatch.elapsedMilliseconds;
      _terminalPreviewDispatched = true;
      _terminalPreviewPending = true;
      final terminalSession = _session is SpeculativeBatchChunkUploadSession
          ? _session! as SpeculativeBatchChunkUploadSession
          : null;
      if (terminalSession != null) {
        _terminalPreviewPending = false;
        terminalSession.requestTerminalSpeculativePreview();
      }
    });
  }

  void markStopRequested({required bool manual}) {
    _stopRequestedAtRecordingMs ??= _recordingStopwatch.elapsedMilliseconds;
    _stopReason ??= manual ? 'manual' : 'vad';
    // A timer that fires while recorder.stop() drains its last frame has no
    // speculative lead. Cancel it here; the explicit recorder-stop request is
    // tagged late and therefore cannot add prepare/commit to the critical path.
    _cancelTerminalPreviewTimer('recorder_stop');
    _pushClientTerminalTelemetry();
  }

  void requestTerminalSpeculativePreview() {
    _cancelTerminalPreviewTimer('recorder_stop_snapshot');
    _terminalRequestedAtRecordingMs ??= _recordingStopwatch.elapsedMilliseconds;
    _terminalPreviewDispatched = true;
    _terminalPreviewPending = true;
    final speculative = _session is SpeculativeBatchChunkUploadSession
        ? _session! as SpeculativeBatchChunkUploadSession
        : null;
    if (speculative != null) {
      _terminalPreviewPending = false;
      speculative.requestTerminalSpeculativePreview(atRecorderStop: true);
    }
  }

  void addAudioChunk(Uint8List bytes) {
    if (!_acceptingChunks || bytes.isEmpty) {
      return;
    }
    _analyzePcmVoiceActivity(bytes);
    final session = _session;
    if (session != null) {
      session.addAudioChunk(bytes);
      return;
    }
    _bufferedChunks.add(Uint8List.fromList(bytes));
  }

  void _analyzePcmVoiceActivity(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount <= 0) {
      return;
    }
    final data = ByteData.sublistView(bytes);
    for (
      var frameStart = 0;
      frameStart < sampleCount;
      frameStart += _pcmAnalysisFrameSamples
    ) {
      final frameEnd = math.min(
        sampleCount,
        frameStart + _pcmAnalysisFrameSamples,
      );
      var energy = 0.0;
      for (
        var sampleIndex = frameStart;
        sampleIndex < frameEnd;
        sampleIndex += 1
      ) {
        final sample = data.getInt16(sampleIndex * 2, Endian.little) / 32768.0;
        energy += sample * sample;
      }
      final frameSamples = frameEnd - frameStart;
      final frameDuration = Duration(
        microseconds: ((frameSamples * 1000000) / _pcmSampleRate).round(),
      );
      _pcmElapsed += frameDuration;
      final rms = math.sqrt(energy / math.max(1, frameSamples));
      final dbfs = rms <= 1e-7
          ? -100.0
          : (20 * math.log(rms) / math.ln10).clamp(-100.0, 0.0).toDouble();
      final activity = _pcmVoiceActivityDetector.addSample(
        dbfs,
        elapsed: _pcmElapsed,
      );
      if (activity.speechStarted && !_speechDetected) {
        markSpeculativeSpeechDetected();
      }
      if (!_speechDetected || activity.isCalibrating) {
        continue;
      }
      if (activity.voiceActive) {
        _pcmSilenceDuration = Duration.zero;
        final requiresConfirmedResume =
            _pcmVoiceInactive || _voiceInactiveAt != null;
        if (requiresConfirmedResume) {
          if (_pcmResumeDuration == Duration.zero) {
            _pcmResumeMinimumDbfs = dbfs;
            _pcmResumeMaximumDbfs = dbfs;
          } else {
            _pcmResumeMinimumDbfs = math.min(_pcmResumeMinimumDbfs, dbfs);
            _pcmResumeMaximumDbfs = math.max(_pcmResumeMaximumDbfs, dbfs);
          }
          _pcmResumeDuration += frameDuration;
          final resumeVariation = _pcmResumeMaximumDbfs - _pcmResumeMinimumDbfs;
          if (_pcmResumeDuration < _pcmConfirmedResumeDuration ||
              resumeVariation < _pcmConfirmedResumeVariationDb) {
            // Do not let one noisy/reverberant frame cancel an ASR terminal
            // already scheduled during silence. A real new phrase supplies a
            // short, varying PCM run and is confirmed below.
            continue;
          }
          _pcmVoiceInactive = false;
          _resetPcmResumeCandidate();
          // A confirmed PCM speech resumption invalidates the old terminal
          // snapshot even when Safari's amplitude callback misses the start.
          markSpeculativeSpeechDetected();
          markSpeculativeVoiceActive(resumeReason: 'pcm_confirmed_resume');
          continue;
        }
        _resetPcmResumeCandidate();
        if (!_voiceActive) {
          markSpeculativeVoiceActive(resumeReason: 'pcm_voice_active');
        }
        continue;
      }
      _resetPcmResumeCandidate();
      _pcmSilenceDuration += frameDuration;
      if (!_pcmVoiceInactive &&
          _pcmSilenceDuration >= _pcmStableSilenceDuration) {
        _pcmVoiceInactive = true;
        _pcmSilenceDetectedAtRecordingMs ??=
            _recordingStopwatch.elapsedMilliseconds;
        markSpeculativeVoiceInactive();
      }
    }
  }

  void _resetPcmResumeCandidate() {
    _pcmResumeDuration = Duration.zero;
    _pcmResumeMinimumDbfs = 0;
    _pcmResumeMaximumDbfs = -100;
  }

  void _cancelTerminalPreviewTimer(String reason) {
    final timer = _terminalPreviewTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _terminalPreviewTimer = null;
    _terminalTimerCanceledCount += 1;
    _terminalTimerLastCancelReason = reason;
  }

  Map<String, dynamic> _clientTerminalTelemetry() {
    final stopAt = _stopRequestedAtRecordingMs;
    final terminalAt = _terminalRequestedAtRecordingMs;
    return <String, dynamic>{
      if (_stopReason != null) 'clientStopReason': _stopReason,
      if (_pcmSilenceDetectedAtRecordingMs != null)
        'clientPcmSilenceDetectedAtRecordingMs':
            _pcmSilenceDetectedAtRecordingMs,
      if (_terminalTimerScheduledAtRecordingMs != null)
        'clientTerminalTimerScheduledAtRecordingMs':
            _terminalTimerScheduledAtRecordingMs,
      'clientTerminalRequestedAtRecordingMs': ?terminalAt,
      'clientStopRequestedAtRecordingMs': ?stopAt,
      if (stopAt != null && terminalAt != null)
        'clientTerminalRequestedBeforeStopMs': math.max(0, stopAt - terminalAt),
      'clientTerminalTimerCanceledCount': _terminalTimerCanceledCount,
      if (_terminalTimerLastCancelReason != null)
        'clientTerminalTimerLastCancelReason': _terminalTimerLastCancelReason,
    };
  }

  void _pushClientTerminalTelemetry([
    SpeculativeBatchChunkUploadSession? target,
  ]) {
    final speculative =
        target ??
        (_session is SpeculativeBatchChunkUploadSession
            ? _session! as SpeculativeBatchChunkUploadSession
            : null);
    speculative?.updateClientTerminalTelemetry(_clientTerminalTelemetry());
  }

  void schedulePromotion() {
    if (_promotionFuture != null || _promotionTimer != null) {
      return;
    }
    if (promotionDelay == Duration.zero) {
      _promotionFuture = _promoteToChunkUpload();
      return;
    }
    _promotionTimer = Timer(promotionDelay, _startPromotionNow);
  }

  void _startPromotionNow() {
    _promotionTimer?.cancel();
    _promotionTimer = null;
    _promotionFuture ??= _promoteToChunkUpload();
  }

  Future<void> waitUntilPromoted() async {
    if (!_acceptingChunks || _session != null) {
      return;
    }
    _startPromotionNow();
    final promotion = _promotionFuture;
    if (promotion == null) {
      return;
    }
    try {
      await promotion.timeout(const Duration(milliseconds: 350));
    } on TimeoutException {
      // The WAV fallback remains available. Promotion may finish later and
      // will discard its session if stop has already sealed this manager.
    }
  }

  Future<void> _promoteToChunkUpload() async {
    try {
      final session = await repository.startBatchChunkUpload();
      if (!_acceptingChunks) {
        await session.discard().catchError((Object _) {});
        return;
      }
      _session = session;
      final speculative = session is SpeculativeBatchChunkUploadSession
          ? session as SpeculativeBatchChunkUploadSession
          : null;
      final previewContext = _previewContext;
      final previewChildAge = _previewChildAge;
      if (speculative != null &&
          previewContext != null &&
          previewChildAge != null) {
        speculative.configureSpeculativePreview(
          context: previewContext,
          childAge: previewChildAge,
        );
        if (_speechDetected) {
          speculative.markSpeculativeSpeechDetected();
        }
        if (_voiceActive) {
          speculative.markSpeculativeVoiceActive();
        } else if (_voiceInactiveAt != null) {
          speculative.markSpeculativeVoiceInactive();
        }
        _pushClientTerminalTelemetry(speculative);
        _previewSubscription = speculative.speculativePreviews.listen(
          (preview) {
            if (!_previewController.isClosed) {
              _previewController.add(preview);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_previewController.isClosed) {
              _previewController.addError(error, stackTrace);
            }
          },
        );
      }
      for (final bytes in _bufferedChunks) {
        session.addAudioChunk(bytes);
      }
      _bufferedChunks.clear();
      if (_terminalPreviewPending && !_voiceActive && speculative != null) {
        _terminalPreviewPending = false;
        speculative.requestTerminalSpeculativePreview();
      }
    } catch (error) {
      debugPrint(
        'Adaptive Web chunk upload was skipped; keeping WAV fallback: $error',
      );
    }
  }

  Future<BatchChunkUploadSession?> stopAndTakeSession() async {
    _cancelTerminalPreviewTimer('session_sealed');
    _acceptingChunks = false;
    _bufferedChunks.clear();
    final session = _session;
    if (session is SpeculativeBatchChunkUploadSession) {
      _pushClientTerminalTelemetry(
        session as SpeculativeBatchChunkUploadSession,
      );
    }
    _session = null;
    return session;
  }

  Future<void> finishPreviewForwarding() async {
    await _previewSubscription?.cancel();
    _previewSubscription = null;
    if (!_previewController.isClosed) {
      await _previewController.close();
    }
  }

  Future<void> discard({String reason = 'adaptive_cancelled'}) async {
    _promotionTimer?.cancel();
    _cancelTerminalPreviewTimer('discarded');
    _acceptingChunks = false;
    _bufferedChunks.clear();
    await _previewSubscription?.cancel();
    _previewSubscription = null;
    if (!_previewController.isClosed) {
      await _previewController.close();
    }
    final session = _session;
    _session = null;
    if (session != null) {
      await session.discard(reason: reason).catchError((Object _) {});
    }
  }
}
