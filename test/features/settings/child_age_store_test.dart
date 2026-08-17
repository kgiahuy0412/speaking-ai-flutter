import 'package:ai_speaking_flutter_app/features/settings/data/child_age_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('child age is absent until a parent selects a group', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = ChildAgeStore();

    expect(await store.read(), isNull);

    await store.write(8);

    expect(await store.read(), 8);
  });
}
