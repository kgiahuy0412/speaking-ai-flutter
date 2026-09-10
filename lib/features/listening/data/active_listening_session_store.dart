import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ActiveListeningSessionCheckpoint {
  const ActiveListeningSessionCheckpoint({
    required this.childAge,
    required this.topicNumber,
    required this.lessonNumber,
    required this.updatedAtEpochMs,
  });

  factory ActiveListeningSessionCheckpoint.fromJson(Map<String, Object?> json) {
    return ActiveListeningSessionCheckpoint(
      childAge: (json['childAge'] as num?)?.toInt() ?? 0,
      topicNumber: (json['topicNumber'] as num?)?.toInt() ?? 0,
      lessonNumber: (json['lessonNumber'] as num?)?.toInt() ?? 0,
      updatedAtEpochMs: (json['updatedAtEpochMs'] as num?)?.toInt() ?? 0,
    );
  }

  final int childAge;
  final int topicNumber;
  final int lessonNumber;
  final int updatedAtEpochMs;

  bool get isValid => childAge > 0 && topicNumber > 0 && lessonNumber > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'childAge': childAge,
    'topicNumber': topicNumber,
    'lessonNumber': lessonNumber,
    'updatedAtEpochMs': updatedAtEpochMs,
  };
}

/// Durable pointer to the smallest safe lesson unit that can be reconstructed.
///
/// Sentence and authored activity progress remain in [ListeningProgressStore].
/// This file restores the route hierarchy after Android recreates its
/// foreground-service process or after iOS relaunches the app. A recording in
/// progress is deliberately never checkpointed and is therefore restarted
/// from the beginning of its item.
class ActiveListeningSessionStore {
  const ActiveListeningSessionStore();

  static const String _preferenceKey = 'active-listening-session-v1';

  Future<ActiveListeningSessionCheckpoint?> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _preferenceKey,
      );
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final checkpoint = ActiveListeningSessionCheckpoint.fromJson(decoded);
      return checkpoint.isValid ? checkpoint : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required int childAge,
    required int topicNumber,
    required int lessonNumber,
  }) async {
    try {
      final checkpoint = ActiveListeningSessionCheckpoint(
        childAge: childAge,
        topicNumber: topicNumber,
        lessonNumber: lessonNumber,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      final encoded = jsonEncode(checkpoint.toJson());
      await (await SharedPreferences.getInstance()).setString(
        _preferenceKey,
        encoded,
      );
    } catch (_) {
      // Checkpoint persistence must never delay or block lesson navigation.
    }
  }

  Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_preferenceKey);
    } catch (_) {
      // Recovery metadata must never block the normal lesson exit path.
    }
  }
}
