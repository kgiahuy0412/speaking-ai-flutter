import 'package:web/web.dart' as web;

final Set<String> _availableRecordingPaths = <String>{};

Future<String> createLessonRecordingPath(
  String lessonId,
  int sentenceNumber,
) async =>
    '$lessonId-sentence-$sentenceNumber-'
    '${DateTime.now().microsecondsSinceEpoch}.webm';

Future<String?> findLessonRecording(String path) async {
  final value = path.trim();
  return value.isNotEmpty && _availableRecordingPaths.contains(value)
      ? value
      : null;
}

Future<void> deleteLessonRecording(String path) async {
  _availableRecordingPaths.remove(path);
  if (path.startsWith('blob:')) {
    web.URL.revokeObjectURL(path);
  }
}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath,
) async {
  final path = recordedPath?.trim();
  if (path == null || path.isEmpty) {
    return null;
  }
  _availableRecordingPaths.add(path);
  return path;
}
