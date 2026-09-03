import 'package:ai_speaking_flutter_app/features/privacy/data/privacy_consent_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'requires renewed consent after third-party disclosure changes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'homi.parental-privacy-consent.version': 2,
      });

      expect(await const PrivacyConsentStore().readGranted(), isFalse);
    },
  );

  test('persists limited mode without granting voice-data consent', () async {
    const store = PrivacyConsentStore();

    await store.chooseLimitedMode();

    expect(await store.readLimitedMode(), isTrue);
    expect(await store.readGranted(), isFalse);
  });

  test('grant and revoke keep consent states mutually exclusive', () async {
    const store = PrivacyConsentStore();
    await store.chooseLimitedMode();

    await store.grant();

    expect(await store.readGranted(), isTrue);
    expect(await store.readLimitedMode(), isFalse);

    await store.revoke();
    expect(await store.readGranted(), isFalse);
    expect(await store.readLimitedMode(), isFalse);
  });
}
