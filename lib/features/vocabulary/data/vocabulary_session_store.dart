import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';
import 'vocabulary_store.dart';

enum VocabularyPracticeMode { today, review, speakAgain }

class VocabularyPracticeSession {
  const VocabularyPracticeSession({
    required this.id,
    required this.mode,
    required this.entryIds,
    required this.currentIndex,
    required this.results,
    required this.correctAudioPaths,
    required this.createdAt,
    this.dayKey,
  });

  factory VocabularyPracticeSession.fromJson(Map<String, Object?> json) {
    return VocabularyPracticeSession(
      id: json['id'] as String? ?? '',
      mode: VocabularyPracticeMode.values.firstWhere(
        (value) => value.name == json['mode'],
        orElse: () => VocabularyPracticeMode.today,
      ),
      entryIds: (json['entryIds'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      results: (json['results'] as Map<String, Object?>? ?? const {}).map(
        (key, value) => MapEntry(key, value == true),
      ),
      correctAudioPaths:
          (json['correctAudioPaths'] as Map<String, Object?>? ?? const {}).map(
            (key, value) => MapEntry(key, value as String),
          ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dayKey: json['dayKey'] as String?,
    );
  }

  final String id;
  final VocabularyPracticeMode mode;
  final List<String> entryIds;
  final int currentIndex;
  final Map<String, bool> results;
  final Map<String, String> correctAudioPaths;
  final DateTime createdAt;
  final String? dayKey;

  bool get isValid => id.isNotEmpty && entryIds.isNotEmpty;

  VocabularyPracticeSession copyWith({
    List<String>? entryIds,
    int? currentIndex,
    Map<String, bool>? results,
    Map<String, String>? correctAudioPaths,
  }) => VocabularyPracticeSession(
    id: id,
    mode: mode,
    entryIds: entryIds ?? this.entryIds,
    currentIndex: currentIndex ?? this.currentIndex,
    results: results ?? this.results,
    correctAudioPaths: correctAudioPaths ?? this.correctAudioPaths,
    createdAt: createdAt,
    dayKey: dayKey,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'mode': mode.name,
    'entryIds': entryIds,
    'currentIndex': currentIndex,
    'results': results,
    'correctAudioPaths': correctAudioPaths,
    'createdAt': createdAt.toIso8601String(),
    if (dayKey != null) 'dayKey': dayKey,
  };
}

class VocabularySessionStore {
  const VocabularySessionStore();

  static const _activeKey = 'innotrik.vocabulary-active-session.v2';
  static const _todaySuppressedKey = 'innotrik.vocabulary-today-suppressed.v2';
  static const _playbackCheckpointPrefix =
      'innotrik.vocabulary-playback-checkpoint.v2.';
  static const _parentPlaybackEntryCountKey =
      'innotrik.vocabulary-parent-playback-entry-count.v3';
  static const _lastVocabularyEntryDayKey =
      'innotrik.vocabulary-last-entry-day.v3';

  Future<VocabularyPracticeSession?> readActive() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_activeKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final session = VocabularyPracticeSession.fromJson(decoded);
      return session.isValid ? session : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActive(VocabularyPracticeSession session) async {
    await (await SharedPreferences.getInstance()).setString(
      _activeKey,
      jsonEncode(session.toJson()),
    );
  }

  Future<void> clearActive() async {
    await (await SharedPreferences.getInstance()).remove(_activeKey);
  }

  Future<VocabularyPracticeSession?> prepareToday(
    VocabularyStore vocabularyStore, {
    DateTime? now,
    bool forceNextGroup = false,
  }) async {
    final currentTime = now ?? DateTime.now();
    final today = _dayKey(currentTime);
    final active = await readActive();
    if (!forceNextGroup &&
        active?.mode == VocabularyPracticeMode.today &&
        active?.dayKey == today) {
      return _reconcile(active!, vocabularyStore);
    }
    if (!forceNextGroup && await isTodaySuppressed(currentTime)) {
      return null;
    }
    final pending = await vocabularyStore.pendingParentEntries();
    if (pending.isEmpty) {
      await clearActive();
      return null;
    }
    final session = VocabularyPracticeSession(
      id: 'today:$today:${currentTime.microsecondsSinceEpoch}',
      mode: VocabularyPracticeMode.today,
      entryIds: pending
          .take(5)
          .map((entry) => entry.id)
          .toList(growable: false),
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
      dayKey: today,
    );
    await saveActive(session);
    return session;
  }

  Future<VocabularyPracticeSession?> prepareReview(
    VocabularyStore vocabularyStore, {
    DateTime? now,
    bool forceNextGroup = false,
    Set<String> excludeEntryIds = const <String>{},
  }) async {
    final active = await readActive();
    if (!forceNextGroup && active?.mode == VocabularyPracticeMode.review) {
      return _reconcile(active!, vocabularyStore);
    }
    final entries = (await vocabularyStore.reviewEntries())
        .where((entry) => !excludeEntryIds.contains(entry.id))
        .toList(growable: false);
    if (entries.isEmpty) {
      return null;
    }
    final currentTime = now ?? DateTime.now();
    final session = VocabularyPracticeSession(
      id: 'review:${currentTime.microsecondsSinceEpoch}',
      mode: VocabularyPracticeMode.review,
      entryIds: entries
          .take(5)
          .map((entry) => entry.id)
          .toList(growable: false),
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
    );
    await saveActive(session);
    return session;
  }

  Future<VocabularyPracticeSession> prepareSpeakAgain(
    VocabularyEntry entry, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final session = VocabularyPracticeSession(
      id: 'speak-again:${entry.id}:${currentTime.microsecondsSinceEpoch}',
      mode: VocabularyPracticeMode.speakAgain,
      entryIds: <String>[entry.id],
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
    );
    await saveActive(session);
    return session;
  }

  Future<VocabularyPracticeSession?> _reconcile(
    VocabularyPracticeSession session,
    VocabularyStore vocabularyStore,
  ) async {
    final entries = await vocabularyStore.read();
    final available = entries.map((entry) => entry.id).toSet();
    final originalCurrentId = session.entryIds.isEmpty
        ? null
        : session.entryIds[session.currentIndex.clamp(
            0,
            session.entryIds.length - 1,
          )];
    final entryIds = session.entryIds
        .where(available.contains)
        .toList(growable: true);
    if (session.mode == VocabularyPracticeMode.today && entryIds.length < 5) {
      final pending = await vocabularyStore.pendingParentEntries();
      for (final entry in pending) {
        if (entryIds.length >= 5) break;
        if (!entryIds.contains(entry.id)) entryIds.add(entry.id);
      }
    }
    if (entryIds.isEmpty) {
      await clearActive();
      return null;
    }
    final retainedCurrentIndex = originalCurrentId == null
        ? -1
        : entryIds.indexOf(originalCurrentId);
    final reconciled = session.copyWith(
      entryIds: entryIds,
      currentIndex: retainedCurrentIndex >= 0
          ? retainedCurrentIndex
          : session.currentIndex.clamp(0, entryIds.length - 1),
      results: Map<String, bool>.fromEntries(
        session.results.entries.where((entry) => available.contains(entry.key)),
      ),
      correctAudioPaths: Map<String, String>.fromEntries(
        session.correctAudioPaths.entries.where(
          (entry) => available.contains(entry.key),
        ),
      ),
    );
    await saveActive(reconciled);
    return reconciled;
  }

  Future<bool> isTodaySuppressed(DateTime now) async {
    final value = (await SharedPreferences.getInstance()).getString(
      _todaySuppressedKey,
    );
    return value == _dayKey(now);
  }

  Future<void> suppressToday(DateTime now) async {
    await (await SharedPreferences.getInstance()).setString(
      _todaySuppressedKey,
      _dayKey(now),
    );
  }

  Future<int> readPlaybackCheckpoint(String branch) async {
    return (await SharedPreferences.getInstance()).getInt(
          '$_playbackCheckpointPrefix$branch',
        ) ??
        0;
  }

  Future<void> savePlaybackCheckpoint(String branch, int index) async {
    await (await SharedPreferences.getInstance()).setInt(
      '$_playbackCheckpointPrefix$branch',
      index < 0 ? 0 : index,
    );
  }

  Future<void> clearPlaybackCheckpoint(String branch) async {
    await (await SharedPreferences.getInstance()).remove(
      '$_playbackCheckpointPrefix$branch',
    );
  }

  /// Persists the first vocabulary entry of the local day across app restarts.
  Future<bool> markAndCheckFirstEntryToday(DateTime now) async {
    final preferences = await SharedPreferences.getInstance();
    final today = _dayKey(now);
    if (preferences.getString(_lastVocabularyEntryDayKey) == today) {
      return false;
    }
    await preferences.setString(_lastVocabularyEntryDayKey, today);
    return true;
  }

  /// Returns true only for the first two deliberate entries into
  /// "Ba mẹ đã thêm". Resuming an existing playback never calls this method.
  Future<bool> recordParentPlaybackEntry() async {
    final preferences = await SharedPreferences.getInstance();
    final count = preferences.getInt(_parentPlaybackEntryCountKey) ?? 0;
    await preferences.setInt(_parentPlaybackEntryCountKey, count + 1);
    return count < 2;
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
