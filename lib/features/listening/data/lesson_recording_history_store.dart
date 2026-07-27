import 'dart:convert';

import 'lesson_recording_history_persistence.dart';

class LessonRecordingHistoryEntry {
  const LessonRecordingHistoryEntry({
    required this.id,
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceNumber,
    required this.english,
    required this.vietnamese,
    required this.filePath,
    required this.duration,
    required this.createdAt,
  });

  factory LessonRecordingHistoryEntry.fromJson(Map<String, Object?> json) {
    return LessonRecordingHistoryEntry(
      id: json['id'] as String? ?? '',
      lessonId: json['lessonId'] as String? ?? '',
      lessonTitle: json['lessonTitle'] as String? ?? '',
      sentenceId: json['sentenceId'] as String? ?? '',
      sentenceNumber: json['sentenceNumber'] as int? ?? 0,
      english: json['english'] as String? ?? '',
      vietnamese: json['vietnamese'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceNumber;
  final String english;
  final String vietnamese;
  final String filePath;
  final Duration duration;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'lessonId': lessonId,
    'lessonTitle': lessonTitle,
    'sentenceId': sentenceId,
    'sentenceNumber': sentenceNumber,
    'english': english,
    'vietnamese': vietnamese,
    'filePath': filePath,
    'durationMs': duration.inMilliseconds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class LessonRecordingHistoryStore {
  const LessonRecordingHistoryStore({this.customPath, this.maxPerSentence = 3});

  final String? customPath;
  final int maxPerSentence;

  LessonRecordingHistoryPersistence get _persistence =>
      LessonRecordingHistoryPersistence(customPath: customPath);

  Future<List<LessonRecordingHistoryEntry>> readAll() async {
    try {
      final raw = await _persistence.read();
      if (raw == null || raw.trim().isEmpty) {
        return <LessonRecordingHistoryEntry>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return <LessonRecordingHistoryEntry>[];
      }
      final entries = decoded
          .whereType<Map<String, Object?>>()
          .map(LessonRecordingHistoryEntry.fromJson)
          .where((entry) => entry.id.isNotEmpty && entry.filePath.isNotEmpty)
          .toList();
      entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return entries;
    } catch (_) {
      return <LessonRecordingHistoryEntry>[];
    }
  }

  Future<List<LessonRecordingHistoryEntry>> readForSentence(
    String lessonId,
    String sentenceId,
  ) async {
    return (await readAll())
        .where(
          (entry) =>
              entry.lessonId == lessonId && entry.sentenceId == sentenceId,
        )
        .take(maxPerSentence)
        .toList(growable: false);
  }

  Future<List<String>> addSuccessful(LessonRecordingHistoryEntry entry) async {
    final entries = await readAll();
    entries.insert(0, entry);
    final matching = entries
        .where(
          (candidate) =>
              candidate.lessonId == entry.lessonId &&
              candidate.sentenceId == entry.sentenceId,
        )
        .toList();
    final evicted = matching.skip(maxPerSentence).toList(growable: false);
    final evictedIds = evicted.map((candidate) => candidate.id).toSet();
    entries.removeWhere((candidate) => evictedIds.contains(candidate.id));
    await _persistence.write(
      jsonEncode(entries.map((candidate) => candidate.toJson()).toList()),
    );
    return evicted
        .map((candidate) => candidate.filePath)
        .toList(growable: false);
  }
}
