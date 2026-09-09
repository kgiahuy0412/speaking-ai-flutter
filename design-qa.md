# HOMI Option 2 — Design QA

## Result

Pass for the requested visual redesign. Final open findings: P0 0, P1 0, P2 0, P3 1.

The implementation applies the selected option-2 visual grammar across the current native Flutter surfaces: navy for primary actions and navigation, hot pink for selection/progress/recording, and mint-white for backgrounds and supporting surfaces. Existing product flows and content remain intact.

## Visual truth and captures

- Visual source of truth: `C:\Users\Windows\.codex\generated_images\019fac05-f74f-7952-9259-e708249b6185\exec-525673cd-cb5a-458c-9069-a82108d61810.png`
- Source board: 1490 × 1056 px, light theme.
- Native implementation captures: 390 × 844 logical px, light theme, idle communication, selected age 6–7, and vocabulary landing states.
- Final side-by-side comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\design-qa-option2-overview.png`
- The implementation captures were normalized to 1056 px height only for the combined comparison; no screenshot was stretched inside the app.

## Full-view comparison

Reviewed source and implementation in the same 1490 × 2112 comparison image. The final pass confirms:

- navy hierarchy is consistent across CTAs, arrows, MAIN and selected navigation;
- pink is restricted to stateful emphasis instead of becoming the page background;
- mint-white scenery keeps all three screens bright and gender-neutral;
- vocabulary uses open rows and separators instead of repeated framed cards;
- setup uses the same two-column radio form and visual hierarchy as the selected concept;
- mascot, supporting copy and CTA do not overlap at the 390 × 844 native viewport;
- conversation waveform is long, visible and integrated with the selected palette.

## Focused-region evidence

The full comparison is large enough to inspect the three critical regions without separate crops:

1. Conversation waveform and primary microphone CTA.
2. Setup progress, two-column age selector, information notice, mascot and CTA.
3. Vocabulary illustration rows, separators, counters, arrow buttons and bottom navigation.

## Iteration log

| Severity | Finding | Resolution | Status |
| --- | --- | --- | --- |
| P1 | A whole-screen color filter made the conversation screen appear magenta. | Removed the filter and implemented a responsive mint/pink waveform directly in the shared voice component. | Fixed |
| P2 | The conversation hero asset carried an opaque white rectangle. | Replaced it with a true-alpha version of the approved hero artwork. | Fixed |
| P2 | Vocabulary retained too many rounded cards. | Rebuilt the landing content as open full-width rows with subtle mint separators. | Fixed |
| P2 | Setup initially used a single-column selector and the mascot overlapped the information panel. | Moved to the two-column radio layout and reserved explicit mascot space above the CTA. | Fixed |
| P1 | Narrow waveform instances overflowed in H20 and lesson states. | Made every waveform bar flex to available width. | Fixed |
| P1 | Settings overflowed at 320 px width with 200% text. | Stacked section trailing status when needed, allowed status labels to wrap, and changed the language control to a wrapping choice layout at large text sizes. | Fixed |
| P3 | Some line wraps and illustration sizes differ from the concept board because the implementation preserves real copy and a 390 × 844 native viewport. | Accepted as responsive adaptation; hierarchy, palette and interaction targets remain aligned. | Accepted |

## Verification

- `flutter analyze`: passed with no issues.
- Golden suites for conversation, home, all three setup steps, settings/history, lesson flow and karaoke: passed.
- Home, onboarding, settings, vocabulary, display-language and 200%-text accessibility tests: passed.
- Android debug package: built successfully at `build\app\outputs\flutter-apk\app-debug.apk`.
- iOS shares the same Flutter presentation layer; an IPA/TestFlight archive still requires Xcode on macOS.

## Waveform motion QA — continuous translation and listening lessons

- Source visual truth path: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-6caf2c55-c8a4-4ed1-ba28-e46e3d325eb1.png`.
- Rendered implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\listening\goldens\lesson-practice-390x844.png`.
- Combined focused comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\waveform-motion-reference-vs-implementation.png`.
- Viewport and density: implementation 390 × 844 logical px at 1×; source 112 × 79 px; combined comparison 1120 × 540 px. The implementation crop is 350 × 300 px and both sides were resized proportionally without stretching.
- State: light-theme sentence-practice card. The static capture shows the shared mint/pink waveform styling; runtime motion uses a continuously repeating 2.2-second phase.
- Full-view evidence: the native 390 × 844 screenshot keeps the original lesson hierarchy, primary recording action, bottom navigation and readable spacing without new containers or overflow.
- Focused-region evidence: the combined comparison puts the supplied card and the rendered Flutter card in one image. Copy, mint/pink waveform, playback actions, rounded treatment and visual emphasis align; the implementation remains sharper at native density.
- Motion evidence: `processing_status_test.dart` samples three independently phased bars for 24 consecutive 16 ms frames, confirms visible travel, and caps the largest one-frame height change below 3.5 logical px. `lesson_flow_golden_test.dart` confirms the lesson sample waveform is always active. `accessibility_resilience_test.dart` confirms reduced-motion users retain a stable static waveform.
- Findings: P0 0, P1 0, P2 0. The only intentional difference is higher native rendering clarity than the compressed source thumbnail.
- Comparison history: the earlier implementation advanced the wave in 420 ms steps, leaving a visible pause between interpolations (P2 motion polish). It was replaced with Flutter's frame-synchronized animation controller, continuous sine phase, and a light secondary ripple. The post-fix 16 ms cadence test, navigation suite, accessibility test and full lesson golden suite pass.

## Non-design test note

The isolated test `virtual lesson buttons interrupt the current recording and change sentence` currently expects recording to have started immediately but observes `false`. The visual changes in `lesson_practice_screen.dart` only alter colors, not recording startup logic, so this behavior was not changed as part of the redesign.

## Dark mode adaptation QA

### Visual truth and captures

- Source visual truth: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\home\goldens\home-communication-390x844.png`, the approved option-2 light composition.
- Rendered implementation: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\home\goldens\dark-home-communication-390x844.png`.
- Same-screen comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\dark-home-reference-vs-implementation.png`.
- Full dark UI review board: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\homi-dark-mode-overview.png`.
- Viewport and density: both source and dark implementation are 390 × 844 logical/pixel px at 1×. The side-by-side canvas is 800 × 884 px and neither screen was rescaled.
- State: idle communication screen. The theme intentionally differs; geometry, content, hierarchy and interaction state are the direct comparison surfaces while color is evaluated as an option-2 dark adaptation.

### Full-view comparison evidence

- The approved header, mascot hero, waveform, translation area, CTA and five-item bottom navigation retain their original proportions and reading order.
- The dark version uses a deep navy scenic canvas rather than pure black, with two surface elevations and preserved illustration color.
- Blue, pink and mint keep the same semantic jobs as light mode: primary actions/navigation, voice/selection emphasis and positive/audio states.
- The seven-screen overview confirms the same rules on Home, Vocabulary, Topics, Settings and all three Setup steps. No persistent control is clipped or pushed below the 390 × 844 viewport.

### Focused-region evidence

The 1× side-by-side file is sufficient to inspect the critical text, waveform, translation surface, CTA and bottom navigation. The full overview additionally exposes the setup controls, vocabulary rows, topic journey and settings controls at one consistent scale, so no separate crop was required.

### Required fidelity surfaces

- Fonts and typography: Roboto family, hierarchy, weights, wrapping and line height remain unchanged; light-on-dark text uses the semantic `onSurface` roles.
- Spacing and layout rhythm: no frame, padding, radius or vertical-position changes were introduced for dark mode.
- Colors and visual tokens: canvas `#07172F`, surfaces `#0B2146`/`#123055`, primary `#A9C7F5`, pink `#FF79AA`, mint `#71D8BE`, primary text `#F7FBFF`, secondary text `#C2CEE0`.
- Image quality and asset fidelity: the approved HOMI mascot, topic and vocabulary assets are unchanged; only the scenery receives a navy readability overlay.
- Copy and content: unchanged across themes.
- Accessibility: tested text combinations meet at least 4.5:1; primary body text exceeds 7:1. Reduced-motion behavior remains supported by the shared waveform.

### Dark iteration history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P1 | Vocabulary titles, setup CTA text and some dialog copy inherited light-only navy and became difficult to read. | Replaced fixed foregrounds with semantic dark roles and added explicit dark CTA foregrounds. | Dark Vocabulary and all three Setup screens on the overview board. |
| P2 | The first dark scenery pass remained too bright and grey, weakening the dark-mode distinction. | Increased the navy overlay while preserving the cloud, hill and flower silhouettes. | Home, Vocabulary and Topics captures now share a calm deep-navy lower field. |
| P2 | Success/status accents and metadata chips used light-theme fills or low-contrast green. | Remapped shared status pills, badges, history chips and settings controls to dark mint/raised surfaces. | Settings capture and shared token contrast test. |
| P2 | The MAIN button and vocabulary arrows used a dark light-theme fill against the dark navigation/screen. | Switched interactive dark controls to the light-blue primary with navy foreground. | Home, Vocabulary and Topics captures. |

### Verification

- Primary interactions exercised: switch theme immediately, navigate Home → Vocabulary → Topics, and advance through all three Setup steps.
- Dark golden captures: Home, Vocabulary, Topics, Settings, Setup Privacy, Setup Profile and Setup Permissions.
- `flutter analyze`: passed with no issues.
- Dark semantic contrast test: passed.
- Dark home/setup/settings golden tests: passed.

No actionable P0, P1 or P2 findings remain. Minor platform-specific text rasterization differences between Android and iOS are acceptable and do not change layout or contrast.

final result: passed
