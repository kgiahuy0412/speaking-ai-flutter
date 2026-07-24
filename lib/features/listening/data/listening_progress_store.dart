import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ListeningProgressStore {
  const ListeningProgressStore({this.progressFilePath});

  static const String _resumeSuffix = '::current-sentence';

  final String? progressFilePath;

  Future<File> _progressFile() async {
    final customPath = progressFilePath;
    if (customPath != null) {
      return File(customPath);
    }
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}listening-progress.json',
    );
  }

  Future<Map<String, int>> readAll() async {
    final progress = await _readRaw();
    progress.removeWhere((key, _) => key.endsWith(_resumeSuffix));
    return progress;
  }

  Future<Map<String, int>> _readRaw() async {
    try {
      final file = await _progressFile();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return <String, int>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key, value is int ? value : 0),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<int> readLesson(String lessonId) async {
    return (await readAll())[lessonId] ?? 0;
  }

  Future<int> readCurrentSentence(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_resumeSuffix'] ?? progress[lessonId] ?? 0;
  }

  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress['$lessonId$_resumeSuffix'] = sentenceIndex < 0 ? 0 : sentenceIndex;
    await _writeRaw(progress);
  }

  Future<void> saveLesson(String lessonId, int completedSentences) async {
    final progress = await _readRaw();
    final previous = progress[lessonId] ?? 0;
    if (completedSentences <= previous) {
      return;
    }
    progress[lessonId] = completedSentences;
    await _writeRaw(progress);
  }

  Future<void> _writeRaw(Map<String, int> progress) async {
    final file = await _progressFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(progress), flush: true);
  }
}
