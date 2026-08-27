import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/audio_playback_service.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../data/lesson_recording_history_store.dart';
import 'lesson_recording_storage.dart';

class LessonRecording {
  const LessonRecording({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;
}

class LessonMediaService {
  LessonMediaService({
    AudioRecorder? recorder,
    AudioPlaybackService? playbackService,
    HfpAudioControl? hfpAudioControl,
    LessonRecordingHistoryStore? historyStore,
  }) : _recorder = recorder,
       _playbackService = playbackService,
       _hfpAudioControl = hfpAudioControl,
       historyStore = historyStore ?? const LessonRecordingHistoryStore();

  final LessonRecordingHistoryStore historyStore;

  AudioRecorder? _recorder;
  AudioPlaybackService? _playbackService;
  final HfpAudioControl? _hfpAudioControl;
  DateTime? _recordingStartedAt;
  String? _activePath;
  _ActiveLessonRecording? _activeContext;
  Completer<void>? _activePlaybackCompletion;
  Future<void> _recordingOperation = Future<void>.value();
  bool _ownsActiveHfpRoute = false;

  AudioRecorder get _activeRecorder => _recorder ??= AudioRecorder();

  AudioPlaybackService get _activePlayback =>
      _playbackService ??= JustAudioPlaybackService();

  bool get _shouldUseSelectedHfp =>
      shouldUseSelectedLessonHfp(_hfpAudioControl?.status);

  Future<String> recordingPath({
    required String lessonId,
    required int sentenceNumber,
  }) => createLessonRecordingPath(lessonId, sentenceNumber);

  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async {
    try {
      final entries = await historyStore.readForSentence(
        lessonId,
        sentenceId ?? '$lessonId-sentence-$sentenceNumber',
      );
      for (final entry in entries) {
        final path = await findLessonRecording(entry.filePath);
        if (path != null) {
          return path;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> play(Uri uri) async {
    await _preparePlaybackRoute();
    await _activePlayback.play(uri);
  }

  Stream<bool> get playbackPlayingStream => _activePlayback.playingStream;

  Stream<Duration> get playbackPositionStream {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).positionStream
        : const Stream<Duration>.empty();
  }

  Stream<Duration?> get playbackDurationStream {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).durationStream
        : const Stream<Duration?>.empty();
  }

  Duration get playbackPosition {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).position
        : Duration.zero;
  }

  Duration? get playbackDuration {
    final playback = _activePlayback;
    return playback is ProgressAwareAudioPlaybackService
        ? (playback as ProgressAwareAudioPlaybackService).duration
        : null;
  }

  Future<void> preload(Uri uri) => _activePlayback.preload(uri);

  Future<void> unlockPlaybackForUserGesture() async {
    final playback = _activePlayback;
    if (playback is UserGestureAudioPlaybackService) {
      await (playback as UserGestureAudioPlaybackService)
          .unlockForUserGesture();
    }
  }

  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final playback = _activePlayback;
    await _preparePlaybackRoute();
    final completed = Completer<void>();
    final previousCompletion = _activePlaybackCompletion;
    if (previousCompletion != null && !previousCompletion.isCompleted) {
      previousCompletion.complete();
    }
    _activePlaybackCompletion = completed;
    var started = false;
    final CompletionAwareAudioPlaybackService? completionPlayback =
        playback is CompletionAwareAudioPlaybackService
        ? playback as CompletionAwareAudioPlaybackService
        : null;
    final subscription = playback.playingStream.listen(
      (playing) {
        if (playing) {
          started = true;
        } else if (completionPlayback == null &&
            started &&
            !completed.isCompleted) {
          completed.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completed.isCompleted) {
          completed.completeError(error, stackTrace);
        }
      },
    );
    StreamSubscription<void>? completionSubscription;
    try {
      await playback.play(uri);
      started = true;
      // Subscribe only after this source has actually started. just_audio's
      // state stream can replay ProcessingState.completed from the previous
      // source when a listener is attached, which must not finish the new
      // lesson intro early.
      completionSubscription = completionPlayback?.completionStream.listen(
        (_) {
          if (!completed.isCompleted) {
            completed.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completed.isCompleted) {
            completed.completeError(error, stackTrace);
          }
        },
      );
      await completed.future.timeout(timeout);
    } finally {
      await Future.wait<void>(<Future<void>>[
        subscription.cancel(),
        if (completionSubscription != null) completionSubscription.cancel(),
      ]);
      if (identical(_activePlaybackCompletion, completed)) {
        _activePlaybackCompletion = null;
      }
    }
  }

  Future<void> stopPlayback() async {
    await _stopPlayback(releaseAudioRoute: true);
  }

  Future<void> _stopPlayback({required bool releaseAudioRoute}) async {
    final completion = _activePlaybackCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    await _playbackService?.stop();
    if (releaseAudioRoute) {
      await _releaseHfpRoute();
    }
  }

  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
    bool saveToHistory = true,
  }) => _serializeRecordingOperation(() async {
    try {
      // Keep an already confirmed HFP route alive while switching from the final
      // guide clip to capture. Releasing it here makes iOS renegotiate to the
      // phone between "Con nói lại nhé" and AVAudioRecorder opening its input.
      await _stopPlayback(releaseAudioRoute: false);
      final recorder = _activeRecorder;
      if (!await recorder.hasPermission()) {
        throw const LessonMediaException(
          'Ứng dụng cần quyền micro để lưu bản ghi của con.',
        );
      }

      final useSelectedHfp = _shouldUseSelectedHfp;
      final session = await AudioSession.instance;
      await session.configure(
        lessonRecordingAudioSessionConfiguration(
          useSelectedHfp: useSelectedHfp,
        ),
      );

      if (useSelectedHfp) {
        await _activateSelectedHfpRoute();
      } else {
        await _releaseHfpRoute();
      }

      final recordingInput = await _resolveRecordingInput(
        recorder,
        useSelectedHfp: useSelectedHfp,
      );

      final path = await recordingPath(
        lessonId: lessonId,
        sentenceNumber: sentenceNumber,
      );
      await recorder.start(
        lessonRecordConfig(
          useSelectedHfp: useSelectedHfp,
          inputDevice: recordingInput,
        ),
        path: path,
      );
      _activePath = path;
      _activeContext = _ActiveLessonRecording(
        lessonId: lessonId,
        lessonTitle: lessonTitle ?? lessonId,
        sentenceId: sentenceId ?? '$lessonId-sentence-$sentenceNumber',
        sentenceNumber: sentenceNumber,
        english: english ?? '',
        vietnamese: vietnamese ?? '',
        saveToHistory: saveToHistory,
      );
      _recordingStartedAt = DateTime.now();
    } catch (_) {
      await _releaseHfpRoute();
      rethrow;
    }
  });

  Future<InputDevice?> _resolveRecordingInput(
    AudioRecorder recorder, {
    required bool useSelectedHfp,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    final devices = await recorder.listInputDevices();
    final selected = selectLessonRecordingInput(
      devices,
      useSelectedHfp: useSelectedHfp,
      selectedHfpDeviceId: _hfpAudioControl?.status.deviceId,
      selectedHfpDeviceName: _hfpAudioControl?.status.deviceName,
    );
    if (selected != null) {
      return selected;
    }
    if (useSelectedHfp) {
      throw const LessonMediaException(
        'iOS chưa mở được mic H20 đã chọn. Hãy kết nối lại H20 rồi thử lại.',
      );
    }
    throw const LessonMediaException(
      'iOS chưa tìm thấy mic tích hợp của iPhone/iPad.',
    );
  }

  Future<void> _preparePlaybackRoute() async {
    final playback = _activePlayback;
    final useSelectedHfp = _shouldUseSelectedHfp;
    if (playback is CommunicationRouteAwareAudioPlaybackService) {
      (playback as CommunicationRouteAwareAudioPlaybackService)
          .setCommunicationRouteActive(useSelectedHfp);
    }
    // Configure playAndRecord/voiceChat first, then re-assert the selected HFP
    // input. This order prevents just_audio's playback preparation from
    // replacing the route selected by the native H20 bridge.
    await playback.prepare();
    if (useSelectedHfp) {
      await _activateSelectedHfpRoute();
    } else {
      await _releaseHfpRoute();
    }
  }

  Future<void> _activateSelectedHfpRoute() async {
    final control = _hfpAudioControl;
    if (control == null) {
      return;
    }
    await control.startAudioRoute();
    _ownsActiveHfpRoute = true;
  }

  Future<void> _releaseHfpRoute() async {
    if (!_ownsActiveHfpRoute) {
      return;
    }
    _ownsActiveHfpRoute = false;
    await _hfpAudioControl?.stopAudioRoute();
  }

  @visibleForTesting
  static RecordConfig lessonRecordConfig({
    required bool useSelectedHfp,
    InputDevice? inputDevice,
  }) => RecordConfig(
    encoder: AudioEncoder.aacLc,
    sampleRate: 16000,
    bitRate: 64000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    device: inputDevice,
    iosConfig: IosRecordConfig(
      categoryOptions: useSelectedHfp
          ? const <IosAudioCategoryOption>[
              IosAudioCategoryOption.allowBluetooth,
            ]
          : const <IosAudioCategoryOption>[
              IosAudioCategoryOption.defaultToSpeaker,
            ],
    ),
  );

  Future<LessonRecording> stopRecording() =>
      _serializeRecordingOperation(() async {
        try {
          final recorder = _recorder;
          final startedAt = _recordingStartedAt;
          final expectedPath = _activePath;
          final context = _activeContext;
          if (recorder == null ||
              startedAt == null ||
              expectedPath == null ||
              context == null) {
            throw const LessonMediaException('Chưa có bản ghi đang thực hiện.');
          }
          final recordedPath = await recorder.stop();
          _recordingStartedAt = null;
          _activePath = null;
          _activeContext = null;
          final resolvedPath = await resolveLessonRecording(
            recordedPath,
            expectedPath,
          );
          if (resolvedPath == null) {
            throw const LessonMediaException('Không tìm thấy bản ghi vừa tạo.');
          }
          final recording = LessonRecording(
            filePath: resolvedPath,
            duration: DateTime.now().difference(startedAt),
          );
          if (context.saveToHistory) {
            final createdAt = DateTime.now();
            final evictedPaths = await historyStore.addSuccessful(
              LessonRecordingHistoryEntry(
                id: '${context.sentenceId}-${createdAt.microsecondsSinceEpoch}',
                lessonId: context.lessonId,
                lessonTitle: context.lessonTitle,
                sentenceId: context.sentenceId,
                sentenceNumber: context.sentenceNumber,
                english: context.english,
                vietnamese: context.vietnamese,
                filePath: resolvedPath,
                duration: recording.duration,
                createdAt: createdAt,
              ),
            );
            for (final path in evictedPaths) {
              await deleteLessonRecording(path);
            }
          }
          return recording;
        } finally {
          await _releaseHfpRoute();
        }
      });

  Future<void> cancelRecording() => _serializeRecordingOperation(() async {
    try {
      await _recorder?.cancel();
      _recordingStartedAt = null;
      _activePath = null;
      _activeContext = null;
    } finally {
      await _releaseHfpRoute();
    }
  });

  Future<T> _serializeRecordingOperation<T>(Future<T> Function() action) {
    final operation = _recordingOperation.then<T>((_) => action());
    _recordingOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> deleteRecording(String path) => deleteLessonRecording(path);

  Future<void> deleteRecordingsForLesson(String lessonId) async {
    final paths = await historyStore.removeLesson(lessonId);
    for (final path in paths) {
      await deleteLessonRecording(path);
    }
  }

  Future<void> dispose() async {
    await _recordingOperation;
    await _releaseHfpRoute();
    await _recorder?.dispose();
    await _playbackService?.dispose();
  }
}

@visibleForTesting
bool shouldUseSelectedLessonHfp(BluetoothAudioStatus? status) =>
    status != null &&
    status.isBridgeSupported &&
    (status.deviceId != null || status.isConnected);

@visibleForTesting
AudioSessionConfiguration lessonRecordingAudioSessionConfiguration({
  required bool useSelectedHfp,
}) => AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  avAudioSessionCategoryOptions: useSelectedHfp
      ? AVAudioSessionCategoryOptions.allowBluetooth
      : AVAudioSessionCategoryOptions.defaultToSpeaker,
  avAudioSessionMode: AVAudioSessionMode.voiceChat,
  androidAudioAttributes: const AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.voiceCommunication,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  androidWillPauseWhenDucked: true,
);

@visibleForTesting
InputDevice? selectLessonRecordingInput(
  List<InputDevice> devices, {
  required bool useSelectedHfp,
  String? selectedHfpDeviceId,
  String? selectedHfpDeviceName,
}) {
  if (!useSelectedHfp) {
    for (final device in devices) {
      if (device.type == InputDeviceType.builtIn) {
        return device;
      }
    }
    return null;
  }

  final selectedId = selectedHfpDeviceId?.trim();
  if (selectedId != null && selectedId.isNotEmpty) {
    for (final device in devices) {
      if (device.id == selectedId &&
          device.type == InputDeviceType.bluetoothSco) {
        return device;
      }
    }
  }

  final selectedName = selectedHfpDeviceName?.trim().toLowerCase();
  if (selectedName != null && selectedName.isNotEmpty) {
    for (final device in devices) {
      if (device.type == InputDeviceType.bluetoothSco &&
          device.label.trim().toLowerCase() == selectedName) {
        return device;
      }
    }
  }

  final hfpDevices = devices
      .where((device) => device.type == InputDeviceType.bluetoothSco)
      .toList(growable: false);
  return hfpDevices.length == 1 ? hfpDevices.single : null;
}

class _ActiveLessonRecording {
  const _ActiveLessonRecording({
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceNumber,
    required this.english,
    required this.vietnamese,
    required this.saveToHistory,
  });

  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceNumber;
  final String english;
  final String vietnamese;
  final bool saveToHistory;
}

class LessonMediaException implements Exception {
  const LessonMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}
