import 'package:shared_preferences/shared_preferences.dart';

/// Persists completion of the parent/teacher-only first-run setup.
///
/// Keep this separate from the child-facing feature tour: changing the parent
/// setup contract can intentionally require an existing installation to review
/// privacy, profile and audio-source choices again without replaying the tour.
class ParentSetupProgressStore {
  const ParentSetupProgressStore();

  static const currentVersion = 1;
  static const _versionKey = 'homi.parent-setup.version';

  Future<bool> isComplete() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getInt(_versionKey) ?? 0) >= currentVersion;
  }

  Future<void> markComplete() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_versionKey, currentVersion);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_versionKey);
  }
}
