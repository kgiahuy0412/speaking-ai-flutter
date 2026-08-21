# HOMI iOS App Store release runbook

## What this branch prepares

- Bundle ID: `com.innotrik.aispeaking`.
- iOS display name: `HOMI App`.
- Minimum iOS version: 15.0.
- App-level privacy manifest and branded iOS icon.
- Parent disclosure/consent before any microphone permission request.
- Passive mode when voice permission or consent is unavailable.
- Parent-gated Privacy Policy, Terms, Support and consent withdrawal actions.
- Codemagic App Store signing, IPA archive and App Store Connect upload.

## Codemagic one-time setup

1. Enroll the correct company in the Apple Developer Program and create the app
   record in App Store Connect with bundle ID `com.innotrik.aispeaking`.
2. In App Store Connect, create an API key with App Manager access. Download the
   `.p8` once and keep its Issuer ID and Key ID outside Git.
3. In Codemagic, add the Apple Developer Portal integration and name it exactly
   `innotrik_app_store_connect`, matching `codemagic.yaml`.
4. In Codemagic **Code signing identities**, generate or upload an Apple
   Distribution certificate, then fetch/upload an App Store provisioning
   profile for `com.innotrik.aispeaking`. The API key alone is not a signing
   certificate or provisioning profile.
5. Create the Codemagic environment group `homi_app_store`. Add these non-secret
   release values (mark them secure if company policy requires it):
   - `PRIVACY_POLICY_URL`
   - `TERMS_URL`
   - `SUPPORT_URL`
   - `AI_SUBPROCESSORS`
   - `DATA_RETENTION_SUMMARY`
6. Run the `ios-app-store` workflow manually. It fetches the matching App Store
   signing assets, builds a signed IPA and uploads it to App Store Connect.
7. Wait for Apple processing, add internal TestFlight testers, and test on real
   iPhone/iPad before sending the build to external beta review or App Review.

No `.p8`, certificate, provisioning profile, Apple password or signing secret
belongs in this repository.

## Required product/legal decisions before App Review

The release workflow intentionally fails when legal URLs, provider disclosure,
or retention text are missing. Before supplying those values, confirm that the
production backend actually implements the same claims.

- Choose one primary Kids Category age band: 5 and under, 6–8, or 9–11. The
  current product range 3–15 does not map to one Apple Kids age band.
- Publish a Privacy Policy that names Railway/HOMI infrastructure, Cloudflare,
  OpenAI and every other real subprocessor that receives child data.
- Define separate TTL/retention for raw audio, transcripts, history, telemetry,
  caches and backups.
- Make `DELETE /api/history?deleteRelatedData=true` delete history, transcript,
  raw/generated child audio and associated cache references atomically. The app
  waits for a successful server response but cannot prove a cascade performed
  inside a backend that is not part of this repository.
- Add parent-scoped authentication/authorization; a long-lived `clientId` alone
  is not sufficient access control.
- Remove sensitive child speech/text from application, platform and provider
  logs; add rate limiting and abuse protection.
- Keep the App Store privacy labels exactly aligned with runtime/backend use:
  Audio Data, Other User Content, Device ID, Product Interaction, Performance,
  Diagnostics, and age/age group. Select Tracking only if cross-service tracking
  really occurs.

## Real-device acceptance checklist

- Fresh install: no system permission appears before the parent accepts.
- Decline consent and decline microphone: listening/vocabulary content remains
  usable, while every recording path is blocked.
- Accept consent, then grant/deny/regrant microphone from iOS Settings.
- Foreground/background/interruptions, speaker/Bluetooth audio routes, phone
  calls and screen locking do not leave recording active.
- Parent gate protects every external link and destructive privacy action.
- Consent withdrawal succeeds only after the server confirms deletion; the app
  then clears the local age and resets the iOS Keychain installation ID.
- Generate Xcode's Privacy Report from the release archive and compare it with
  App Store Connect privacy answers and all Flutter/plugin manifests.

## Android impact

iOS name, icon, deployment target, Swift code, signing and privacy manifest do
not change Android. The shared parent-consent screen and recording guard do
apply to Android as well: Android will no longer request microphone/Bluetooth at
startup, and voice features remain disabled until a parent accepts and grants
permission. Existing Android application ID, icon, signing, BLE/HFP paths and
`ANDROID_ID` identity behavior remain unchanged.
