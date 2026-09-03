import 'package:shared_preferences/shared_preferences.dart';

const _consentVersionKey = 'homi.parental-privacy-consent.version';
const _consentGrantedAtKey = 'homi.parental-privacy-consent.granted-at';
const _limitedModeKey = 'homi.parental-privacy-consent.limited-mode';

class PrivacyConsentStore {
  const PrivacyConsentStore();

  // Version 3 explicitly names Railway, Cloudflare Workers AI and Cloudinary,
  // together with the data each provider receives and its purpose. Existing
  // grants must be confirmed again because Apple requires this disclosure to
  // be shown before voice data is sent to third parties.
  static const int currentVersion = 3;

  Future<bool> readGranted() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getInt(_consentVersionKey) == currentVersion;
    } catch (_) {
      return false;
    }
  }

  Future<bool> readLimitedMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_limitedModeKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> grant() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_consentVersionKey, currentVersion);
    await preferences.setString(
      _consentGrantedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    await preferences.remove(_limitedModeKey);
  }

  Future<void> chooseLimitedMode() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_limitedModeKey, true);
  }

  Future<void> clearLimitedMode() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_limitedModeKey);
  }

  Future<void> revoke() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait<bool>(<Future<bool>>[
      preferences.remove(_consentVersionKey),
      preferences.remove(_consentGrantedAtKey),
      preferences.remove(_limitedModeKey),
    ]);
  }
}
