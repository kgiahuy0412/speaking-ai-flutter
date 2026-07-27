import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';

import '../../../core/audio/audio_playback_service.dart';
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
    LessonRecordingHistoryStore? historyStore,
  }) : _recorder = recorder,
       _playbackService = playbackService,
       historyStore = historyStore ?? const LessonRecordingHistoryStore();

  final LessonRecordingHistoryStore historyStore;

  AudioRecorder? _recorder;
  AudioPlaybackService? _playbackService;
  DateTime? _recordingStartedAt;
  String? _activePath;
  _ActiveLessonRecording? _activeContext;

  AudioRecorder get _activeRecorder => _recorder ??= AudioRecorder();

  AudioPlaybackService get _activePlayback =>
      _playbackService ??= JustAudioPlaybackService();

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
    await _activePlayback.play(uri);
  }

  Future<void> stopPlayback() async {
    await _playbackService?.stop();
  }

  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
  }) async {
    await stopPlayback();
    final recorder = _activeRecorder;
    if (!await recorder.hasPermission()) {
      throw const LessonMediaException(
        'Ứng dụng cần quyền micro để lưu bản ghi của con.',
      );
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    final path = await recordingPath(
      lessonId: lessonId,
      sentenceNumber: sentenceNumber,
    );
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 64000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
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
    );
    _recordingStartedAt = DateTime.now();
  }

  Future<LessonRecording> stopRecording() async {
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
    return recording;
  }

  Future<void> cancelRecording() async {
    await _recorder?.cancel();
    _recordingStartedAt = null;
    _activePath = null;
    _activeContext = null;
  }

  Future<void> dispose() async {
    await _recorder?.dispose();
    await _playbackService?.dispose();
  }
}

class _ActiveLessonRecording {
  const _ActiveLessonRecording({
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceNumber,
    required this.english,
    required this.vietnamese,
  });

  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceNumber;
  final String english;
  final String vietnamese;
}

class LessonMediaException implements Exception {
  const LessonMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}
