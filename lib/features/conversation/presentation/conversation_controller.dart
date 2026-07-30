import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/audio_playback_service.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/audio/offline_intent_recognizer.dart';
import '../../../core/audio/realtime_fallback_buffer.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/network/browser_network_quality.dart';
import '../../../l10n/display_language.dart';
import '../domain/conversation_models.dart';
import '../domain/conversation_repository.dart';

class ConversationController extends ChangeNotifier {
  ConversationController({
    required AudioInput audioInput,
    StreamingSpeechInput? streamingSpeechInput,
    HfpAudioControl? hfpAudioControl,
    required AudioPlaybackService playbackService,
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
       _playbackService = playbackService,
       _repository = repository,
       _offlineIntentRecognizer = offlineIntentRecognizer,
       _displayLanguageStore = displayLanguageStore,
       _childAge = childAge,
       _preferBleStreaming = preferBleStreaming,
       _realtimeBatchFallback = realtimeBatchFallback,
       _isWebRuntime = webRuntimeOverride ?? kIsWeb,
       _adaptiveWebUploadDelay =
           adaptiveWebUploadDelay ??
           (browserNetworkLooksSlow()
               ? const Duration(milliseconds: 600)
               : const Duration(seconds: 2)),
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
    if (displayLanguageStore != null) {
      unawaited(_loadDisplayLanguage());
    }
    unawaited(_primeExactIntentCatalog());
  }

  final AudioInput _audioInput;
  final BluetoothAudioInputControl? _bluetoothAudioControl;
  final StreamingSpeechInput? _streamingSpeechInput;
  final HfpAudioControl? _hfpAudioControl;
  final AudioPlaybackService _playbackService;
  final ConversationRepository _repository;
  final OfflineIntentRecognizer? _offlineIntentRecognizer;
  final DisplayLanguageStore? _displayLanguageStore;
  final int _childAge;
  final bool _preferBleStreaming;
  final bool _realtimeBatchFallback;
  final bool _isWebRuntime;
  final Duration _adaptiveWebUploadDelay;
  final RealtimeFallbackBuffer _realtimeFallbackBuffer;

  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<BluetoothAudioStatus>? _bluetoothStatusSubscription;
  StreamSubscription<BluetoothAudioStatus>? _hfpStatusSubscription;
  StreamSubscription<void>? _streamingCompletionSubscription;
  StreamSubscription<String>? _partialTextSubscription;
  StreamSubscription<Uint8List>? _batchChunkSubscription;
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
  DateTime? _recordingStartedAt;
  DateTime? _stoppedAt;
  bool _stopInProgress = false;
  bool _speechDetected = false;
  bool _usingStreamingSpeech = false;
  bool _usingHfpRoute = false;
  bool _usingRealtimeTranscription = false;
  bool _usingOfflineIntent = false;
  BatchChunkUploadSession? _batchChunkUpload;
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

  ConversationPhase phase = ConversationPhase.idle;
  ConversationProcessingStage processingStage =
      ConversationProcessingStage.recognizing;
  PracticeContext context = PracticeContext.home;
  AsrMode asrMode;
  int vadSilenceMs = 700;
  double amplitude = 0;
  ConversationResult? result;
  bool? qualityApproved;
  String? errorMessage;
  String? transientMessage;
  DisplayLanguage displayLanguage = DisplayLanguage.vietnamese;
  bool bleDiagnosticRunning = false;

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
  bool get isBusy =>
      bleDiagnosticRunning ||
      hfpAudioStatus.isBusy ||
      phase == ConversationPhase.recording ||
      phase == ConversationPhase.processing;

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
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      final previousAdaptiveWebUpload = _adaptiveWebUpload;
      _adaptiveWebUpload = null;
      if (previousAdaptiveWebUpload != null) {
        await previousAdaptiveWebUpload.discard();
      }
      final previousBatchUpload = _batchChunkUpload;
      _batchChunkUpload = null;
      if (previousBatchUpload != null) {
        await previousBatchUpload.discard().catchError((Object _) {});
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
      _listenToAmplitude(
        _usingStreamingSpeech
            ? _streamingSpeechInput!.amplitudeDbfs
            : _audioInput.amplitudeDbfs,
      );
      _maximumDurationTimer = Timer(
        const Duration(seconds: 12),
        () => unawaited(stopRecording(manual: false)),
      );
      _noSpeechTimer = Timer(const Duration(seconds: 2), () {
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
    final firstSpeechResult = !_speechDetected;
    _speechDetected = true;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    if (firstSpeechResult) {
      _scheduleOfflineFallback();
    }
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
        debugPrint('OpenAI Realtime audio stream failed: $error');
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
          debugPrint('OpenAI Realtime transcript failed: $error');
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
      debugPrint('OpenAI Realtime background connection failed: $error');
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

    BatchChunkUploadSession? upload;
    final bufferedChunks = <Uint8List>[];
    try {
      _batchChunkSubscription = chunkedInput.audioChunks.listen(
        (bytes) {
          final activeUpload = upload;
          if (activeUpload == null) {
            bufferedChunks.add(Uint8List.fromList(bytes));
            return;
          }
          activeUpload.addAudioChunk(bytes);
        },
        onError: (Object error) {
          debugPrint('Batch audio stream failed: $error');
        },
      );
      final inputStart = chunkedInput.startChunked();
      final uploadStart = chunkedRepository.startBatchChunkUpload().then((
        session,
      ) {
        upload = session;
        _batchChunkUpload = session;
        for (final bytes in bufferedChunks) {
          session.addAudioChunk(bytes);
        }
        bufferedChunks.clear();
      });
      await Future.wait<void>(<Future<void>>[inputStart, uploadStart]);
    } catch (error) {
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
      _batchChunkUpload = null;
      await chunkedInput.cancel().catchError((Object _) {});
      final activeUpload = upload;
      if (activeUpload != null) {
        await activeUpload.discard().catchError((Object _) {});
      }
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
    _adaptiveWebUpload = upload;
    _batchChunkSubscription = chunkedInput.audioChunks.listen(
      upload.addAudioChunk,
      onError: (Object error) {
        debugPrint('Adaptive Web audio stream failed: $error');
      },
    );

    try {
      await chunkedInput.startChunked();
      upload.schedulePromotion();
    } catch (_) {
      await _batchChunkSubscription?.cancel();
      _batchChunkSubscription = null;
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

  void _listenToAmplitude(Stream<double> amplitudeStream) {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = amplitudeStream.listen((dbfs) {
      if (phase != ConversationPhase.recording) {
        return;
      }

      amplitude = ((dbfs + 60) / 48).clamp(0.0, 1.0).toDouble();
      if (dbfs > -38) {
        final firstSpeechFrame = !_speechDetected;
        _speechDetected = true;
        if (firstSpeechFrame) {
          _scheduleOfflineFallback();
        }
        _noSpeechTimer?.cancel();
        _noSpeechTimer = null;
        _silenceTimer?.cancel();
        _silenceTimer = null;
      } else if (_speechDetected && _silenceTimer == null) {
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
    _speechDetected = true;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
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
    _partialPreviewTimer?.cancel();
    _previewGeneration += 1;
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _maximumDurationTimer?.cancel();
    _offlineFallbackTimer?.cancel();
    _offlineFallbackTimer = null;
    await _amplitudeSubscription?.cancel();
    _stoppedAt = DateTime.now();

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
        if (batchUpload != null) {
          await batchUpload.discard().catchError((Object _) {});
        }
        phase = ConversationPhase.idle;
        transientMessage = 'Hãy nói lâu hơn một chút nhé.';
        _stopInProgress = false;
        notifyListeners();
        return;
      }

      if (!_speechDetected && !manual) {
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
        if (batchUpload != null) {
          await batchUpload.discard().catchError((Object _) {});
        }
        phase = ConversationPhase.idle;
        transientMessage =
            'Mình chưa nghe thấy giọng nói, nên chưa gửi lên backend. Thử nói gần micro hơn nhé.';
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
        audioCapture = await _audioInput.stop();
        final adaptiveUpload = _adaptiveWebUpload;
        _adaptiveWebUpload = null;
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
            'OpenAI Realtime finalize failed; preparing Batch Chunks fallback: $error',
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
      _realtimeFallbackBuffer.clear();
      _usingOfflineIntent = false;
      phase = ConversationPhase.processing;
      _beginProcessingStages();
      amplitude = 0;
      notifyListeners();

      if (streamingCapture != null) {
        _applyLocalExactPreview(
          streamingCapture.sourceText,
          targetContext: context,
        );
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
        _playbackService.prepare(),
        resultFuture,
      ]);
      final nextResult = processing[1]! as ConversationResult;
      final preview = _preview;
      if (preview?.audioUri != null &&
          preview!.englishText.trim() == nextResult.englishText.trim()) {
        _preferredPlaybackUri = preview.audioUri;
      }
      result = nextResult;
      _processingStageTimer?.cancel();
      processingStage = ConversationProcessingStage.preparingAudio;
      errorMessage = null;
      notifyListeners();

      if (nextResult.audioUri != null) {
        await playResult(reportLatency: true);
      }
      phase = ConversationPhase.ready;
      notifyListeners();
    } catch (error) {
      _setError(_friendlyError(error));
    } finally {
      final adaptiveWebUpload = _adaptiveWebUpload;
      _adaptiveWebUpload = null;
      if (adaptiveWebUpload != null) {
        await adaptiveWebUpload.discard();
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
    await _hfpAudioControl?.stopAudioRoute().catchError((Object error) {
      debugPrint('Cannot stop HFP audio route: $error');
    });
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
      debugPrint('OpenAI Realtime connection failed while stopping: $error');
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
      await upload?.discard().catchError((Object _) {});
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
      debugPrint('Batch chunk finalize failed; uploading WAV fallback: $error');
      await upload.discard().catchError((Object _) {});
      transientMessage =
          'Mạng chunk không ổn định; đã chuyển sang gửi file WAV dự phòng.';
      notifyListeners();
      return _repository.processAudio(
        capture: capture,
        context: context,
        childAge: _childAge,
        vadSilenceMs: vadSilenceMs,
      );
    }
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

    try {
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
        final firstAudio = DateTime.now().difference(_stoppedAt!);
        debugPrint(
          jsonEncode(<String, dynamic>{
            'event': 'playback_latency_client',
            'conversationId': currentResult.conversationId,
            'audioStartedAfterStopMs': firstAudio.inMilliseconds,
            'audioLoadMs': metrics.audioLoadDuration.inMilliseconds,
            'audioFromDeviceCache': metrics.fromDeviceCache,
          }),
        );
        unawaited(
          _reportPlaybackLatency(
            currentResult: currentResult,
            timeToFirstAudioMs: firstAudio.inMilliseconds,
            audioLoadMs: metrics.audioLoadDuration.inMilliseconds,
            audioFromDeviceCache: metrics.fromDeviceCache,
          ),
        );
      }
    } catch (error) {
      transientMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> _reportPlaybackLatency({
    required ConversationResult currentResult,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
  }) async {
    try {
      await _repository.patchPlaybackLatency(
        conversationId: currentResult.conversationId,
        timeToFirstAudioMs: timeToFirstAudioMs,
        audioLoadMs: audioLoadMs,
        audioFromDeviceCache: audioFromDeviceCache,
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
          'Đã chọn Cloudflare Batch Chunks; OpenAI chỉ được backend dùng khi Cloudflare lỗi.';
    }
    if (nextMode == AsrMode.openAiRealtime) {
      transientMessage =
          'Chế độ AI hiện chưa được bật. Ứng dụng sẽ dùng xử lý dự phòng.';
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
    }
    notifyListeners();
  }

  void _setError(String message) {
    _processingStageTimer?.cancel();
    errorMessage = message;
    phase = ConversationPhase.error;
    if (!_disposed) {
      notifyListeners();
    }
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
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_batchChunkSubscription?.cancel());
    unawaited(_realtimeChunkSubscription?.cancel());
    unawaited(_realtimePartialSubscription?.cancel());
    unawaited(_offlineIntentHypothesisSubscription?.cancel());
    final batchUpload = _batchChunkUpload;
    if (batchUpload != null) {
      unawaited(batchUpload.discard().catchError((Object _) {}));
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
    unawaited(_stopHfpRoute());
    unawaited(_audioInput.dispose());
    unawaited(_streamingSpeechInput?.dispose());
    unawaited(_offlineIntentRecognizer?.dispose());
    unawaited(_hfpAudioControl?.dispose());
    unawaited(_playbackService.dispose());
    unawaited(_repository.dispose());
    super.dispose();
  }
}

class _AdaptiveWebChunkUpload {
  _AdaptiveWebChunkUpload({
    required this.repository,
    required this.promotionDelay,
  });

  final ChunkedConversationRepository repository;
  final Duration promotionDelay;
  final List<Uint8List> _bufferedChunks = <Uint8List>[];

  Timer? _promotionTimer;
  Future<void>? _promotionFuture;
  BatchChunkUploadSession? _session;
  bool _acceptingChunks = true;

  void addAudioChunk(Uint8List bytes) {
    if (!_acceptingChunks || bytes.isEmpty) {
      return;
    }
    final session = _session;
    if (session != null) {
      session.addAudioChunk(bytes);
      return;
    }
    _bufferedChunks.add(Uint8List.fromList(bytes));
  }

  void schedulePromotion() {
    _promotionTimer ??= Timer(promotionDelay, () {
      _promotionFuture = _promoteToChunkUpload();
    });
  }

  Future<void> _promoteToChunkUpload() async {
    try {
      final session = await repository.startBatchChunkUpload();
      if (!_acceptingChunks) {
        await session.discard().catchError((Object _) {});
        return;
      }
      _session = session;
      for (final bytes in _bufferedChunks) {
        session.addAudioChunk(bytes);
      }
      _bufferedChunks.clear();
    } catch (error) {
      debugPrint(
        'Adaptive Web chunk upload was skipped; keeping WAV fallback: $error',
      );
    }
  }

  Future<BatchChunkUploadSession?> stopAndTakeSession() async {
    _promotionTimer?.cancel();
    final promotion = _promotionFuture;
    if (promotion != null && _session == null) {
      try {
        await promotion.timeout(const Duration(milliseconds: 900));
      } on TimeoutException {
        _acceptingChunks = false;
        _bufferedChunks.clear();
        return null;
      }
    }

    _acceptingChunks = false;
    _bufferedChunks.clear();
    final session = _session;
    _session = null;
    return session;
  }

  Future<void> discard() async {
    _promotionTimer?.cancel();
    _acceptingChunks = false;
    _bufferedChunks.clear();
    final session = _session;
    _session = null;
    if (session != null) {
      await session.discard().catchError((Object _) {});
    }
  }
}
