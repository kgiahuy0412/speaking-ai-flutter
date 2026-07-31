# Design QA — Penguin mascot refresh

## Evidence

- Selected mascot direction: `C:/Users/Windows/.codex/generated_images/019fac05-f74f-7952-9259-e708249b6185/exec-e1308f83-31bb-4d31-9382-e56a15d538f3.png`.
- Flutter Web at 1280 × 900: `conversation-web-1280x900.png`.
- Flutter Web at 390 × 844: `conversation-web-mobile-390x844.png`.
- Topic listening at 390 × 844: `topic-listening-web-mobile-390x844.png`.
- Same-input comparison board: `reference-vs-web.png`.
- Flutter golden coverage: conversation idle/recording/ready, topic listening, lesson intro/practice/reminders/review and karaoke.

## Visual findings

- Mascot identity is consistent with the selected navy-and-cream penguin: coral cape, gold clasp, orange beak/feet and large blue eyes.
- Five independent production assets are used by context: avatar, wave, listen, speak and sing. The implementation does not crop a character sheet or reuse one pose everywhere.
- The listening shortcut uses the headphone pose, the conversation hero changes pose with the recording state, the lesson coach uses the speaking pose, and karaoke/completion use the singing pose.
- The new summer train background remains bright and legible on APK-sized and Web-sized layouts. No character is baked into the background, preventing duplicate mascots on screens that render a foreground pose.
- App launcher, Android launcher sizes, PWA favicon and Web manifest icons use the new penguin icon.
- No clipping, unintended black/magenta matte, text overlap or responsive overflow was visible in the inspected 390 × 844 and 1280 × 900 states.
- No actionable P0, P1 or P2 visual issue remains.

## Verification

- `flutter analyze`: passed with no issues; the final VoiceHero change also passed focused analysis.
- 31 relevant functional and golden tests passed; the four conversation/topic golden tests passed again after final Web verification.
- Web release `1.0.3+5`: built successfully with the Railway backend define.
- Android APK release `1.0.3+5`: built successfully at 82.5 MB with the same backend define.
- Flutter Web console: no warnings or errors during the verified conversation and topic-listening flow.

final result: passed
