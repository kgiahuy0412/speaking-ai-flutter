import 'package:shared_preferences/shared_preferences.dart';

const _childAgeKey = 'innotrik.child-age.v1';

/// Persists the age used to resolve the child's listening catalog.
///
/// The UI currently stores the first age of the selected catalog (for example
/// `6` for the 6-7 group). Keeping an integer instead of a catalog index makes
/// the preference resilient if catalog ordering changes later.
class ChildAgeStore {
  const ChildAgeStore();

  Future<int?> read() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_childAgeKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(int age) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_childAgeKey, age);
  }
}
