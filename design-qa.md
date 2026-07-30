# Design QA — Nghe tổng quan

## Subtitle-removal update

- Current source visual truth: `design-qa-assets/source-header-with-subtitle.png` — 217 × 75 px, with the user explicitly requesting removal of its second line.
- Current rendered implementation: `design-qa-assets/implementation-overview-no-subtitle.png` — 1080 × 2400 physical px (360 × 800 logical px, DPR 3, including Android system bars).
- Focused implementation crop: `design-qa-assets/implementation-header-no-subtitle-crop.png` — 950 × 190 px.
- Combined comparison input: `design-qa-assets/header-subtitle-removal-comparison.png` — 1040 × 220 px.
- State: the “Nghe tổng quan” overview is open during automatic playback; the header contains only its title between the existing back and replay controls.
- Density normalization: the small source crop was enlarged to 434 × 150 and the emulator header crop reduced to 500 × 100 on one comparison board. The comparison targets content removal and header alignment, not exact font raster density.
- Full-view evidence: the emulator screenshot shows the subtitle absent without affecting the sentence list, active border, replay action, or “Học ngay” CTA.
- Focused evidence: the side-by-side board confirms the second line is removed and the remaining title is vertically balanced with the two header controls.
- Required fidelity surfaces: title typography and indigo token remain unchanged; header spacing is balanced; Material icons stay sharp; no image asset is involved; the obsolete copy is absent.
- Findings: no actionable P0, P1, P2, or P3 issue remains for this change.

## Active-border update

- Current source visual truth: `design-qa-assets/source-active-card.png` — 435 × 103 px.
- Current rendered implementation: `design-qa-assets/implementation-active-overview-emulator-final.png` — 1080 × 2400 physical px (360 × 800 logical px, DPR 3, including Android system bars).
- Focused implementation crop: `design-qa-assets/implementation-active-card-crop-final.png` — 990 × 220 px.
- Combined comparison input: `design-qa-assets/active-card-comparison-final.png` — 980 × 150 px.
- State: sentence 3 is being spoken during automatic overview playback; its equalizer icon and indigo outline are active while every other sentence retains the pale lavender outline.
- Density normalization: the 435 × 103 source card was scaled to 465 × 110 and the emulator crop to 450 × 100 on one comparison board. The small size difference preserves each crop's aspect ratio and does not affect border-color evaluation.
- Full-view evidence: the emulator screenshot shows only sentence 3 outlined in indigo, with no layout, spacing, typography, or CTA regression elsewhere on the screen.
- Focused evidence: the side-by-side board confirms that the active card retains the white surface, blue number, English sentence weight, and equalizer control while adding the requested stronger indigo border.
- Required fidelity surfaces: Roboto typography, card spacing/radius, indigo/lavender tokens, Material icon sharpness, and dynamic sentence copy remain consistent with the reference. No photographic or custom image asset is involved.
- Interaction verification: a widget test confirms the active border moves from sentence 1 to sentence 2 after the playback gap; the emulator capture independently confirms sentence 3 active during real automatic playback.

## Evidence

- Source visual truth:
  - `design-qa-assets/source-review-original.png` — 440 × 890 px.
  - `design-qa-assets/source-neutral-card.png` — 435 × 103 px.
- Rendered implementation:
  - `design-qa-assets/implementation-overview-390x844.png` — Flutter widget render at 390 × 844 logical px, DPR 1.
  - `design-qa-assets/implementation-overview-emulator.png` — Android emulator capture at 1080 × 2400 physical px (360 × 800 logical px, DPR 3, including system bars).
- Combined comparison input: `design-qa-assets/overview-comparison-board.png`.
- State: “Nghe tổng quan” opened by tapping “Bỏ qua” on the lesson introduction; automatic sentence playback active; “Học ngay” in its timed locked state.
- Density normalization: the full source and 390 × 844 Flutter render were aligned to the same visual height on the comparison board. The reference card and implementation card crop were both normalized to 440 × 105 px for the focused comparison.

## Full-view comparison

- The title is now “Nghe tổng quan”; the sentence count subtitle and replay action retain the source hierarchy.
- The automatic-play hero and unrecorded-sentence banner are absent, as required.
- The list moves directly under the header and keeps the same page margins and vertical rhythm.
- Every sentence uses the requested neutral white surface, pale lavender border, blue number, and blue play control.
- The primary CTA uses “Học ngay” and preserves the existing timed locked state as “Học ngay sau N giây”.
- The emulator capture contains six sentences because the selected real lesson has six items; the reference contains five. This is expected dynamic content, not layout drift.

## Focused card comparison

- The normalized card comparison confirms the same neutral surface, pale lavender outline, rounded corners, blue circular number badge, bold English sentence, and circular play affordance.
- No additional focused region was needed: the header and CTA are clearly readable in the full-view comparison, and the removed regions are unambiguous.

## Required fidelity surfaces

- Fonts and typography: Roboto hierarchy, weights, line height, and single-line sentence treatment are consistent with the reference direction; no clipping or unintended wrapping is visible.
- Spacing and layout rhythm: 20 px page margins, consistent card gaps, rounded corners, and generous tap areas remain balanced at both 390 × 844 and 360 × 800 logical viewports.
- Colors and visual tokens: indigo text/actions, lavender borders and button disabled state, white cards, and warm page background match the supplied visual language.
- Image quality and assets: this screen contains no photographic or illustrative assets; Material icons remain sharp and visually consistent at emulator density.
- Copy and content: “Nghe tổng quan” and “Học ngay” are present; removed status copy does not appear.
- Accessibility and responsiveness: widget tests cover the compact-phone route and large text scale; controls retain practical mobile tap targets and the page scrolls when needed.

## Interaction verification

- Tapping “Bỏ qua” on the introduction opens “Nghe tổng quan”.
- The screen automatically plays sentence audio and still supports replaying individual sentences.
- After the six-second lock expires, tapping “Học ngay” opens the sentence-practice screen.
- Android logcat contained no Flutter exception, fatal exception, or framework exception entry during the verified flow.

## Findings

- No actionable P0, P1, or P2 differences remain.
- No P3 follow-up is required for the requested scope.

## Comparison history

- Pass 1: no actionable P0/P1/P2 mismatch was found. The large regions visible only in the original screenshot were intentionally removed by the user's specification, and the focused sentence-card treatment matches the supplied third image. No visual correction loop was required.
- Pass 2: the user requested a clearer active state. The previously neutral active border was changed to a 1.5 px indigo outline; the post-fix widget test and emulator comparison show that the outline follows the currently spoken sentence. No actionable P0/P1/P2 mismatch remains.
- Pass 3: the user requested removal of the learned-sentence subtitle. The second header line was removed, the title was vertically rebalanced, and the post-fix golden/emulator comparison shows no layout regression. No actionable P0/P1/P2 mismatch remains.

## Implementation checklist

- [x] Rename the screen.
- [x] Remove both obsolete boxes.
- [x] Normalize sentence-card colors and state styling.
- [x] Move the indigo active border with the currently spoken sentence.
- [x] Remove the learned-sentence subtitle and rebalance the header.
- [x] Rename and wire the primary CTA.
- [x] Verify the skip-to-overview-to-practice journey.
- [x] Verify compact layout, tests, analyzer, emulator render, and runtime logs.

## Reminder-popup timeout and input-blocking update

- Source visual truth:
  - `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-a68e556d-414b-495a-b259-a151206b6349.png` - 426 x 335 px.
  - `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-23d4db92-dbec-4b35-a9e0-bd62b9a6e0b9.png` - 410 x 313 px.
- Rendered implementation:
  - `design-qa-assets/popup-reminder-implementation.png` - 1080 x 2400 physical px (360 x 800 logical px, DPR 3, including Android system bars).
  - `design-qa-assets/popup-second-reminder-implementation.png` - 1080 x 2400 physical px (360 x 800 logical px, DPR 3, including Android system bars).
  - `design-qa-assets/popup-reminder-after-timeout.png` - the same Android viewport after automatic dismissal.
- Combined comparison input: `design-qa-assets/popup-reminders-comparison.png` - 900 x 760 px.
- State: the first reminder is visible four seconds after sentence activation; the second reminder is visible four seconds later. Both enter with the existing animation and close immediately when their 2.5-second display timer expires.
- Density normalization: focused Android popup regions were cropped from the 1080 x 2400 captures and scaled to 426 x 335 and 410 x 313 so each could be compared beside its corresponding source crop.
- Full-view evidence: both Android captures preserve the modal dimming, centered card, mascot, decorative icons, title, message, rounded border, and underlying lesson context. The after-timeout capture confirms the popup is removed without altering the sentence state.
- Focused evidence: the combined board confirms the supplied colors, typography hierarchy, card proportions, mascot asset, and copy remain intact. Small mascot-scale differences are expected frames of the existing continuous mascot animation, not design drift.
- Required fidelity surfaces: Roboto hierarchy and wrapping remain legible; modal spacing and radii match the reference direction; indigo, lavender, amber, and coral tokens are unchanged; the original high-quality mascot image remains in use; Vietnamese copy is unchanged.
- Interaction verification: the widget test holds the first popup through 2,499 ms and verifies removal at 2,500 ms. While the second popup is visible, tapping the covered `Bo qua cau nay` control is absorbed and the active sentence remains unchanged. All 98 tests pass, `flutter analyze` reports no issues, and the Android log check contains no Flutter/framework/fatal exception.
- Findings: no actionable P0, P1, P2, or P3 issue remains for this update.
- Comparison history: pass 1 found no visual regression because this change intentionally affects only timeout and hit testing. No visual correction loop was required.
- [x] Auto-dismiss the first reminder after 2.5 seconds.
- [x] Auto-dismiss the second reminder after 2.5 seconds.
- [x] Prevent popup taps and click-through to covered controls.
- [x] Verify timing, behavior, full test suite, analyzer, Android rendering, and runtime logs.

## Opt-in automatic-play control update

- Source visual truth: `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-3033f0f9-f8f9-478e-ba79-9244e04e9bc1.png` - 455 x 1000 px.
- Rendered implementation:
  - `design-qa-assets/auto-overview-default.png` - 1080 x 2400 physical px (360 x 800 logical px, DPR 3, including Android system bars).
  - `design-qa-assets/auto-overview-active.png` - the same Android viewport with automatic play active and sentence 1 playing.
  - `design-qa-assets/auto-overview-stopped.png` - the same Android viewport after the control is toggled off.
- Combined comparison input: `design-qa-assets/auto-overview-comparison.png` - 1425 x 1050 px.
- State: the page initially shows no active sentence and performs no playback. The new `Tu dong phat` control is on the left of `Hoc ngay`; activating it fills the control with indigo, changes its icon to an equalizer, and starts sequential playback from sentence 1. Tapping it again stops playback and clears the active sentence.
- Density normalization: the 455 x 1000 source was kept at native size; both 1080 x 2400 Android captures were downsampled to 450 x 1000 on one comparison board. Android status/navigation bars are runtime-owned and were treated as expected chrome.
- Full-view evidence: the header, six neutral sentence cards, number badges, play controls, spacing, and warm page background remain consistent with the supplied reference. The requested second action fits beside `Hoc ngay` without clipping or changing the list layout.
- Focused evidence: no separate crop was needed because both action labels, active button fill, sentence-1 active border, and equalizer icons are clearly readable in the full-view comparison.
- Required fidelity surfaces: Roboto hierarchy and weights remain consistent; the two 60 px action buttons align to the existing 20 px page margins and 10 px gap; indigo/lavender/white tokens match the existing screen; only standard Material icons are used and no image asset is involved; Vietnamese action copy matches the request.
- Primary interactions tested: default idle state, enable automatic playback, sentence active-state progression, disable automatic playback, individual sentence playback compatibility, and unchanged `Hoc ngay` navigation behavior.
- Runtime verification: all 98 Flutter tests pass, `flutter analyze` reports no issues, the refreshed review golden passes, and Android logcat contains no Flutter/framework/fatal exception for the verified flow.
- Findings: no actionable P0, P1, P2, or P3 issue remains for this update.
- Comparison history: pass 1 found no P0/P1/P2 visual mismatch. The only structural difference from the source - splitting the original full-width action into two equal actions - is the explicit user-requested change, so no visual correction loop was required.
- [x] Keep the overview idle by default.
- [x] Add `Tu dong phat` to the left of `Hoc ngay`.
- [x] Show clear inactive and active button states.
- [x] Play sentences sequentially and move the active border.
- [x] Stop playback when the active control is tapped again.
- [x] Verify golden, behavior tests, analyzer, Android render, and runtime logs.

## Learned-review navigation update

- Source visual truth: `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-04cbc09a-e7b0-48c9-8029-dff9790b14aa.png` - 468 x 781 px.
- Rendered implementation: `design-qa-assets/emulator-learned.png` - Android emulator capture at 1080 x 2400 physical px, including system bars.
- Combined comparison input: `design-qa-assets/comparison-learned-review.png` - the source and running emulator state aligned to the same visual height.
- State: lesson 1 of a two-lesson topic is complete. The title is `Đã học`; the left action is `Bài tiếp theo`; the right action is `Luyện lại từ đầu`.
- Full-view evidence: all six dynamic lesson sentences fit without clipping; card margins, lavender borders, number badges, play controls, header actions, and bottom action alignment remain consistent with the supplied direction.
- Interaction verification: the emulator opens lesson 2's introduction after `Bài tiếp theo`. Widget tests also verify restarting at sentence 1 and returning to the selected topic through `Luyện nghe` when the completed lesson is the topic's last lesson.
- Responsive and regression verification: the 320 x 568 compact-phone test keeps both learned-review actions reachable. `flutter analyze` reports no issues and all 101 Flutter tests pass.
- Findings: no actionable P0, P1, P2, or P3 issue remains for this update.
- [x] Separate pre-lesson overview and post-lesson learned states.
- [x] Rename the post-lesson title to `Đã học`.
- [x] Wire `Bài tiếp theo`, `Luyện lại từ đầu`, and final-lesson `Luyện nghe` behavior.
- [x] Verify source comparison, emulator navigation, compact layout, analyzer, and full test suite.

## Post-recording fireworks update

- Source visual truth: `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-f3fdd1ba-b9af-441d-be03-36096ad9d1b3.png` - 439 x 350 px, showing the response box that the user requested to remove.
- Rendered implementation: `test/features/listening/goldens/lesson-praise-fireworks-390x844.png` - Flutter component render at 390 x 844 logical px, DPR 1.
- Focused implementation crop: `design-qa-assets/fireworks-implementation-crop.png` - 390 x 670 px.
- Combined comparison input: `design-qa-assets/fireworks-comparison.png` - 1079 x 672 px, with both source and implementation normalized to 520 px visual height.
- State: recording has just finished successfully; the recording card and four post-recording actions are visible while two animated celebration bursts rise from the left and right sides.
- Full-view evidence: the green modal surface, dim backdrop, mascot, title, and message are absent. The sentence, recording result, and actions remain fully readable and usable beneath the transient effect.
- Focused evidence: the comparison board confirms the requested structural replacement. Standard Material celebration, star, and sparkle icons preserve the existing indigo, periwinkle, coral, and amber palette without introducing a new raster asset.
- Fonts and typography: no new visible copy is introduced; the underlying lesson hierarchy and Roboto weights remain unchanged.
- Spacing and layout rhythm: the effect uses a full-screen, non-layout overlay, so no card, button, or scroll position moves when it appears or disappears.
- Colors and visual tokens: the celebration uses existing app tokens and the established warm accent colors; contrast of lesson content is unchanged because there is no dim layer.
- Image quality and assets: the removed mascot is not replaced by a fake illustration; all visible celebration marks use sharp standard Material icons appropriate for a transient interface effect.
- Copy and content: `Con làm tuyệt lắm!` and the saved-recording message no longer appear visually. The GUIDE_PRAISE audio remains active as the spoken success feedback.
- Interaction verification: the overlay is wrapped in `IgnorePointer`; a widget test confirms `Câu tiếp theo` works while the fireworks are visible and immediately clears the effect. The animation automatically expires after 2.5 seconds.
- Runtime and regression verification: the refreshed debug APK is installed and running on the Android emulator; logcat contains no Flutter/framework/fatal exception. `flutter analyze` reports no issues and all 101 Flutter tests pass.
- Findings: no actionable P0, P1, P2, or P3 issue remains for this update.
- Comparison history: pass 1 found no P0/P1/P2 mismatch. The large visual difference is the explicit requested removal of the old modal response; the replacement preserves the two-sided celebratory intent without blocking content or controls.
- [x] Remove the post-recording response box, dim layer, mascot, and visible copy.
- [x] Add rising celebration bursts on both the left and right sides.
- [x] Preserve GUIDE_PRAISE playback.
- [x] Keep all lesson actions interactive during the effect.
- [x] Verify visual comparison, golden, behavior, analyzer, full tests, emulator build, and runtime logs.

## Overview play-button redesign

- Source visual truth:
  - `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-0cc8d49c-5ad4-48f7-97ba-963f14772cfe.png` — 74 × 74 px, the previous control.
  - `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-262e1e60-54e0-4c38-9390-529d898ea599.png` — 1256 × 1256 px, the selected cream play-button and pointing-robot direction.
- Rendered implementation: `test/features/listening/goldens/lesson-review-390x844.png` — Flutter widget render at 390 × 844 logical px, DPR 1.
- Generated production asset: `assets/images/mascot-robot-pointing.png` — 627 × 760 px transparent PNG.
- Combined full-view and focused comparison: `design-qa-assets/lesson-review-play-control-comparison.png` — 1100 × 950 px.
- State: “Nghe tổng quan” idle state, before automatic or individual sentence playback; the six-second “Học ngay” lock is active.
- Density normalization: the full source and implementation were contained in equal 540 × 540 regions. The focused source and implementation control crops were separately contained in equal 540 × 390 regions so the component silhouette, pointing gesture, palette, and layering could be judged at comparable visual scale.

### Full-view and focused evidence

- The full Flutter view confirms that all overview rows use the new cream rounded-square control with a white circular center and indigo play icon, while the first row alone contains the pointing mascot.
- Sentence rows 2–5 contain no mascot, and the post-lesson “Đã học” review retains its previous control style so the redesign stays scoped to “Nghe tổng quan”.
- The focused comparison confirms the mascot hand overlaps the white play circle and points directly at the icon, matching the source composition. The component is scaled down appropriately for a list-row affordance rather than copying the source banner or oversized square.
- The supplied reference defines the play-control component rather than the full page. Unspecified header, sentence content, and bottom actions were therefore checked for regression, not redesigned.

### Required fidelity surfaces

- Fonts and typography: existing Roboto title, sentence, number, and action hierarchy is unchanged; no source-banner copy was incorrectly added to the list row.
- Spacing and layout rhythm: the featured first tile expands only enough to hold the mascot and 64 px control; later tiles use consistent 64 px controls, 9 px gaps, 20 px page margins, and preserve scrolling on compact phones.
- Colors and visual tokens: the control uses a warm cream/peach surface, white circular center, indigo icon, lavender border, and restrained peach/indigo shadows consistent with the selected source and existing app palette.
- Image quality and asset fidelity: the pointing mascot is a real generated raster asset grounded in both supplied references, rendered from a 627 × 760 transparent source with high-quality filtering. No emoji, custom SVG, or code-drawn mascot is used, and no visible background halo appears at the 390 × 844 render size.
- Copy and content: “Nghe tổng quan”, every English sentence, and both bottom actions remain unchanged. The source ribbon text is intentionally excluded because the user requested a button redesign, not an additional banner.

### Findings and comparison history

- Pass 1 found one P2 scale mismatch: the full-body mascot was visibly smaller than the character emphasis in the source. The implementation was changed to an upper-body crop at 100 × 92 px while preserving the complete pointing hand.
- Pass 2 evidence in `design-qa-assets/lesson-review-play-control-comparison.png` shows the larger mascot, direct pointing gesture, cream control, white inner circle, and indigo icon without overlap or clipping that affects use. No actionable P0, P1, or P2 issue remains.
- No P3 follow-up is required for the requested scope.

### Interaction and responsive verification

- Individual sentence controls retain the existing playback callback and playing equalizer state.
- The golden suite verifies exactly one overview mascot and no mascot on the learned-review screen.
- A 320 × 568 logical-pixel test at 1.3× text scale confirms the fifth control remains built and no Flutter layout exception occurs.
- The full analyzer reports no issue, and all 107 Flutter tests pass, including the nine lesson-flow golden tests and the 17 guided-flow/navigation tests.

### Implementation checklist

- [x] Restyle every “Nghe tổng quan” sentence play control.
- [x] Add a pointing mascot only to sentence 1.
- [x] Keep sentences 2 onward free of mascot imagery.
- [x] Preserve playback behavior and active state.
- [x] Keep the “Đã học” screen outside the redesign scope.
- [x] Verify 390 × 844 fidelity and compact-phone responsiveness.

## Learned-review recording-status highlights

- Source visual truth: `C:/Users/DELL/AppData/Local/Temp/codex-clipboard-93859412-8c7c-4f5d-aa58-730c3d2e03ec.png` — 447 × 783 px, showing the previous neutral “Đã học” list.
- Rendered implementation: `test/features/listening/goldens/lesson-completion-390x844.png` — 1170 × 2532 physical px, representing a 390 × 844 logical Flutter viewport at DPR 3.
- Combined full-view and focused comparison: `design-qa-assets/learned-recording-status-comparison.png` — 920 × 1464 px.
- State: learned review with sentences 1, 3, and 5 recorded; sentences 2 and 4 unrecorded; the fixture has another lesson available.
- Density normalization: the implementation was downsampled from DPR 3 to 390 × 844 logical pixels. Both full views were contained in equal 440 × 844 regions, and both sentence-list crops were contained in equal 440 × 580 regions.
- State difference noted before comparison: the supplied screenshot contains six sentences and the final-lesson “Luyện nghe” action, while the implementation fixture contains five dynamic sentences and a next lesson. Those content/action differences are existing lesson data and navigation behavior, not visual drift in the requested recording-status treatment.

### Full-view and focused evidence

- Recorded rows use a pale success-green surface, green outline, green number badge, check-circle icon, and the label “Đã ghi âm”.
- Unrecorded rows use a pale coral surface, coral outline, coral number badge, muted-microphone icon, and the label “Chưa ghi âm”.
- The focused comparison confirms that the two states remain immediately distinguishable without obscuring sentence text or changing the play-button affordance.
- The overview screen remains neutral because status styling is applied only when `LessonReviewMode.learned` is active.

### Required fidelity surfaces

- Fonts and typography: Roboto sentence hierarchy remains unchanged; the 12 px bold status labels support one line with ellipsis on constrained devices and remain readable at the standard viewport.
- Spacing and layout rhythm: status sits three pixels below the sentence inside the existing card structure. Card radius, page margins, row gaps, number badge, play target, and bottom-action alignment remain consistent with the supplied screen.
- Colors and visual tokens: recorded state maps to `AppColors.success` / `successSoft`; unrecorded state maps to `AppColors.coral` / `coralSoft`. Both retain strong foreground contrast and a 1.5 px semantic outline.
- Image quality and assets: no custom raster illustration is required for this change. Standard Material check-circle and muted-microphone icons remain sharp at DPR 3; no emoji, inline SVG, or placeholder asset is used.
- Copy and content: Vietnamese labels are exactly “Đã ghi âm” and “Chưa ghi âm”; Chinese display mode uses “已录音” and “尚未录音”. Lesson sentences and navigation copy remain data-driven.

### Findings and comparison history

- Pass 1 found one P2 responsive issue: at a 320 × 568 logical viewport with 1.3× text scale, the unrecorded label could overflow its row by 39 px.
- Fix: the status label now consumes only the remaining width and uses single-line ellipsis when necessary.
- Pass 2: the compact-phone regression test passes with both bottom actions still reachable. No actionable P0, P1, or P2 issue remains in the post-fix implementation.
- No P3 follow-up is required for the requested scope.

### Interaction and data verification

- Learned-review status is calculated from `existingRecording(...)` for every lesson sentence immediately before the review opens, so highlights reflect stored recording files rather than hard-coded lesson indexes.
- Individual play controls, replay, next lesson, restart, and return-to-listening behavior remain unchanged.
- The full Flutter analyzer reports no issue, and all 107 Flutter tests pass, including mixed recorded/unrecorded state assertions, golden comparison, and compact-phone accessibility coverage.

### Implementation checklist

- [x] Show a status label on every learned sentence.
- [x] Highlight recorded and unrecorded rows with distinct semantic colors and icons.
- [x] Read status from actual stored recording availability.
- [x] Keep overview rows neutral.
- [x] Preserve playback and learned-review navigation.
- [x] Verify DPR 3 rendering, 320 px compact layout, analyzer, and full test suite.

final result: passed

---

# Design QA — Summer train visual system

## Evidence

- Source visual truth:
  - `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-6f973d27-18e5-4536-a70a-866d9272e26c.png` — communication.
  - `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-52b5d6df-69aa-4af2-8cdc-e7dc3dbfad89.png` — topic catalog.
  - `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-4dd979b2-58e3-4457-9a10-23b38b080de1.png` — sentence practice.
  - `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-13269f4c-2447-4884-bf21-0c50f3787bf8.png` — karaoke.
- Rendered Flutter implementation:
  - `test/goldens/conversation-idle-compact-450x1025.png`.
  - `test/goldens/topic-listening-426x923.png`.
  - `test/features/listening/goldens/lesson-practice-390x844.png`.
  - `test/features/listening/goldens/song-karaoke-390x844.png`.
- Same-input side-by-side comparison: `design-qa-assets/implementation-comparison.png`.
- Production illustration: `assets/images/learning-train-field-background.webp` — original 853 × 1844 WebP, optimized to 267 KB.

## Comparison findings

- The four screens share the requested bright blue sky, cloud, mountain, train and green-field visual language without reducing the prominence of the topic shortcut, Vietnamese/English result panel, topic cards, lesson sentence or karaoke lyrics.
- Warm ivory surfaces, navy typography, indigo primary controls, green progress and coral micro-accents remain consistent across the journey.
- Phone layouts preserve practical tap targets and scroll when required. Web layouts cap interactive content at 720 logical pixels while the scenery fills the viewport.
- The sentence-practice evidence is the existing-recording state, so it intentionally shows the recording card and post-recording actions. The fresh-sentence state additionally shows the requested mascot coaching strip before recording.
- Karaoke retains three-second autoplay, word highlighting, end confirmation and practice routing. The mascot now sits above the player without obscuring lyrics or controls.
- No actionable P0, P1 or P2 visual mismatch remains. Dynamic lesson counts and fixture copy differ from the supplied examples but remain data-driven and do not change the visual hierarchy.

## Verification

- `flutter analyze`: passed with no issues.
- Full Flutter suite: 157 tests passed, including compact-phone, 200% text, HFP/BLE fallback, recording, topic navigation and karaoke.
- Web release `1.0.3+5`: built successfully with the Railway backend define.
- Android APK release `1.0.3+5`: built successfully; output size 78.5 MB.

final result: passed

---

# Design QA — HFP Recognition Mode

## Comparison target

- Source visual truth: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-b70a2346-3659-440a-8b69-8295bc0fa000.png`.
- Rendered implementation: `C:\Users\Windows\Documents\ai-speaking-flutter-app\artifacts\hfp-settings.png`.
- Recognition-mode state: `C:\Users\Windows\Documents\ai-speaking-flutter-app\artifacts\hfp-settings-modes.png`.
- Empty HFP state: `C:\Users\Windows\Documents\ai-speaking-flutter-app\artifacts\hfp-empty-dialog.png`.
- Full-view comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\artifacts\hfp-design-comparison.png`.
- Focused mode comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\artifacts\hfp-modes-comparison.png`.
- Source pixels: 505 × 1020, including device bezel and Android chrome; density metadata unavailable.
- Implementation pixels: 1080 × 2400 at Android emulator density 420 dpi, approximately 411 × 914 logical px, including Android chrome.
- Normalization: both full-view images were scaled to 1200 px high without changing aspect ratio for the side-by-side structural comparison. Exact pixel matching was not used because the source includes a different device frame and viewport.
- State: Vietnamese, Android 16 emulator, no paired HFP device, BLE and HFP modes disabled until their respective devices are connected.

## Findings

Không còn khác biệt P0, P1 hoặc P2 cần xử lý.

- Fonts and typography: Roboto, weights, hierarchy, line wrapping and muted secondary copy remain consistent with the source. The new HFP labels use the same title/subtitle treatment as the INNOTRIK card and the existing radio modes.
- Spacing and layout rhythm: the 20 px sheet gutters, card radius, border weight, section gaps and radio-row rhythm are preserved. The extra HFP card extends the existing scroll region and does not hide persistent controls.
- Colors and visual tokens: indigo actions, green active state, lavender sheet background, muted disabled mode and neutral card borders reuse the existing app tokens.
- Image and icon fidelity: no new raster asset was needed. Material `headset_mic` and `manage_search` icons match the weight and visual language of the existing microphone/Bluetooth icons.
- Copy and content: “Mic Bluetooth HFP”, “Tìm HFP” and “HFP streaming” clearly distinguish Bluetooth Classic HFP/SCO from BLE streaming. The empty-state dialog explains the Android pairing prerequisite in Vietnamese and Simplified Chinese.
- Interaction and accessibility: opening Settings, scrolling, pressing “Tìm HFP”, reading the empty state and dismissing it were exercised on the emulator. Semantics exposed the HFP action and disabled HFP radio state correctly. Android logcat showed no Flutter or runtime exception.

## Comparison history

### Iteration 1

- P2: the first empty-device response used the root `ScaffoldMessenger`, which was visually hidden behind the full-height settings sheet.
- Fix: replaced the hidden snackbar with an in-sheet alert dialog containing pairing guidance and a clear dismiss action.
- Post-fix evidence: `artifacts/hfp-empty-dialog.png` shows the message above the settings sheet with readable copy and an accessible action.

## Follow-up polish

- P3: the emulator has no physical HFP headset, so the real-device SCO microphone path still needs a short hardware smoke test. The controller route lifecycle is covered by an automated test and the Android bridge compiles into the APK.

## Verification

- `flutter analyze --no-pub`: passed.
- Full Flutter test suite: 105 passed, including the HFP route lifecycle test.
- Android debug APK build: passed.
- Emulator interaction: settings open, scroll, HFP empty state and dismiss affordance passed.

final result: passed

## Song karaoke — 6 tuổi trở lên

- Reference: `C:\Users\Windows\.codex\generated_images\019fac05-f74f-7952-9259-e708249b6185\exec-a47c2850-92cf-4c45-af88-85f7002d63c3.png`.
- Flutter capture: `test/features/listening/goldens/song-karaoke-390x844.png` at 390 × 844 logical pixels.
- Same-input comparison: `C:\Users\Windows\.codex\visualizations\2026\07\29\019fac05-f74f-7952-9259-e708249b6185\song-karaoke-design-qa.png`.
- P0 blockers: none.
- P1 major mismatches: none.
- P2 polish issues: none.
- The implementation keeps the selected bright sunrise direction, full-screen illustration, left-aligned karaoke hierarchy, white pill exit control, bottom progress panel, and one large play/pause control.
- Dynamic song and topic titles truncate safely before the exit action. Previous/next controls are absent as requested.
- Functional checks pass for age filtering, three-second autoplay, synchronized active-line/word highlighting, both end-dialog actions, and reuse of the existing sentence-practice route.

final result: passed
