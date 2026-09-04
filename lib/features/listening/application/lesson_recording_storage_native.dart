import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String lessonRecordingFileExtension({TargetPlatform? platform}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.android
    ? 'wav'
    : 'm4a';

Future<String> createLessonRecordingPath(
  String lessonId,
  int sentenceNumber,
) async {
  final directory = await getApplicationDocumentsDirectory();
  final recordings = Directory(
    '${directory.path}${Platform.pathSeparator}lesson_recordings',
  );
  await recordings.create(recursive: true);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final extension = lessonRecordingFileExtension();
  return '${recordings.path}${Platform.pathSeparator}'
      '$lessonId-sentence-$sentenceNumber-$timestamp.$extension';
}

Future<String?> findLessonRecording(String path) async =>
    await File(path).exists() ? path : null;

Future<void> deleteLessonRecording(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath,
) async {
  final path = recordedPath ?? expectedPath;
  return await File(path).exists() ? path : null;
}
