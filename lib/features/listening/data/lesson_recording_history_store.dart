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

  /// Removes every saved attempt for [lessonId] and returns the associated
  /// media paths so the caller can delete/revoke the actual audio files.
  ///
  /// An explicit "learn again from the beginning" action represents a fresh
  /// practice session. Keeping attempts from the previous run would make the
  /// first sentence look completed and can prevent the guided recorder from
  /// starting again.
  Future<List<String>> removeLesson(String lessonId) async {
    final entries = await readAll();
    final removedPaths = entries
        .where((entry) => entry.lessonId == lessonId)
        .map((entry) => entry.filePath)
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    entries.removeWhere((entry) => entry.lessonId == lessonId);
    await _persistence.write(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    return removedPaths;
  }
}
