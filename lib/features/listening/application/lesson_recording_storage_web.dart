import 'package:web/web.dart' as web;

Future<String> createLessonRecordingPath(
  String lessonId,
  int sentenceNumber,
) async =>
    '$lessonId-sentence-$sentenceNumber-'
    '${DateTime.now().microsecondsSinceEpoch}.webm';

Future<String?> findLessonRecording(String path) async {
  final value = path.trim();
  return value.isEmpty ? null : value;
}

Future<void> deleteLessonRecording(String path) async {
  if (path.startsWith('blob:')) {
    web.URL.revokeObjectURL(path);
  }
}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath,
) async {
  final path = recordedPath?.trim();
  return path == null || path.isEmpty ? null : path;
}
