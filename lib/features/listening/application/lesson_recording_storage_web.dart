Future<String> createLessonRecordingPath(
  String lessonId,
  int sentenceNumber,
) async => '$lessonId-sentence-$sentenceNumber.webm';

Future<String?> findLessonRecording(String path) async => null;

Future<void> deleteLessonRecording(String path) async {}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath,
) async {
  final path = recordedPath?.trim();
  return path == null || path.isEmpty ? null : path;
}
