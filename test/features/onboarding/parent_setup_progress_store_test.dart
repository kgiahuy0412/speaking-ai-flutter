import 'package:ai_speaking_flutter_app/features/onboarding/application/parent_setup_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = ParentSetupProgressStore();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists and clears completion independently', () async {
    expect(await store.isComplete(), isFalse);

    await store.markComplete();
    expect(await store.isComplete(), isTrue);

    await store.clear();
    expect(await store.isComplete(), isFalse);
  });
}
