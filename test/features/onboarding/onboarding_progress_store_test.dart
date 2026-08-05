import 'package:ai_speaking_flutter_app/features/onboarding/application/onboarding_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = SharedPreferencesOnboardingProgressStore();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('shows the current onboarding version only once', () async {
    expect(await store.shouldShow(), isTrue);

    await store.markSeen();

    expect(await store.shouldShow(), isFalse);
  });

  test('shows onboarding again when its content version increases', () async {
    await store.markSeen(version: 1);

    expect(await store.shouldShow(version: 1), isFalse);
    expect(await store.shouldShow(version: 2), isTrue);
  });
}
