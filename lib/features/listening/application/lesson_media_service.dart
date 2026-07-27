import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';

import '../../../core/audio/audio_playback_service.dart';
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
  }) : _recorder = recorder,
       _playbackService = playbackService;

  AudioRecorder? _recorder;
  AudioPlaybackService? _playbackService;
  DateTime? _recordingStartedAt;
  String? _activePath;

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
  }) async {
    try {
      final path = await recordingPath(
        lessonId: lessonId,
        sentenceNumber: sentenceNumber,
      );
      return findLessonRecording(path);
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
    await deleteLessonRecording(path);
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
    _recordingStartedAt = DateTime.now();
  }

  Future<LessonRecording> stopRecording() async {
    final recorder = _recorder;
    final startedAt = _recordingStartedAt;
    final expectedPath = _activePath;
    if (recorder == null || startedAt == null || expectedPath == null) {
      throw const LessonMediaException('Chưa có bản ghi đang thực hiện.');
    }
    final recordedPath = await recorder.stop();
    _recordingStartedAt = null;
    _activePath = null;
    final resolvedPath = await resolveLessonRecording(
      recordedPath,
      expectedPath,
    );
    if (resolvedPath == null) {
      throw const LessonMediaException('Không tìm thấy bản ghi vừa tạo.');
    }
    return LessonRecording(
      filePath: resolvedPath,
      duration: DateTime.now().difference(startedAt),
    );
  }

  Future<void> cancelRecording() async {
    await _recorder?.cancel();
    _recordingStartedAt = null;
    _activePath = null;
  }

  Future<void> dispose() async {
    await _recorder?.dispose();
    await _playbackService?.dispose();
  }
}

class LessonMediaException implements Exception {
  const LessonMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}
