import 'package:shared_preferences/shared_preferences.dart';

const currentUserOnboardingVersion = 1;

abstract interface class OnboardingProgressStore {
  Future<bool> shouldShow({int version = currentUserOnboardingVersion});

  Future<void> markSeen({int version = currentUserOnboardingVersion});
}

class SharedPreferencesOnboardingProgressStore
    implements OnboardingProgressStore {
  const SharedPreferencesOnboardingProgressStore();

  static const _versionKey = 'innotrik.user-onboarding.version';

  @override
  Future<bool> shouldShow({int version = currentUserOnboardingVersion}) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getInt(_versionKey) ?? 0) < version;
  }

  @override
  Future<void> markSeen({int version = currentUserOnboardingVersion}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_versionKey, version);
  }
}
