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

# Design QA — Cổng cài PWA trên iOS (2026-08-12)

## Comparison target

- Source visual truth: `design-qa-assets/ios-pwa-install-reference-original.png` — 870 × 1885 px, gồm chrome của trình duyệt iOS và vùng nội dung web.
- Normalized source: `design-qa-assets/ios-pwa-install-reference-app.png` — 435 × 809 px; crop vùng nội dung từ `x=0, y=197, width=870, height=1618`, sau đó downsample 2:1.
- Browser-rendered implementation: `design-qa-assets/ios-pwa-install-actual.png` — 435 × 809 px.
- Combined comparison input: `design-qa-assets/ios-pwa-install-comparison.png` — 870 × 809 px; reference ở trái, implementation ở phải.
- CSS viewport: 435 × 809; browser chrome được loại khỏi cả hai phía trước khi so sánh.
- Density normalization: ảnh nguồn @2x được đưa về 435 × 809; bản render của Codex in-app Browser được chụp ở cùng kích thước CSS và crop đúng vùng 435 × 809. Khác biệt raster do DPR 0.8 của trình duyệt kiểm tra không được tính là design drift.
- State: iOS web chưa cài PWA, đang mở trong in-app browser nên hiển thị đủ 4 bước, gồm “Mở bằng Safari”.

## Findings

- Không còn khác biệt P0/P1/P2 có thể hành động. Khung thẻ, vị trí mascot, tiêu đề, mô tả, bốn hàng hướng dẫn, ghi chú cuối và nền phong cảnh cùng nhịp dọc với ảnh nguồn.
- Không có P3 cần xử lý trong phạm vi khôi phục màn đã mất.

## Required fidelity surfaces

- Fonts and typography: Roboto, cấp độ chữ, độ đậm, line-height và wrapping trùng với ảnh nguồn; không có cắt chữ hoặc tràn dòng.
- Spacing and layout rhythm: lề ngang 24 px, card rộng 387 px, bo góc 28 px, khoảng cách giữa mascot/tiêu đề/mô tả/các bước và vị trí card theo trục dọc khớp sau chuẩn hóa.
- Colors and visual tokens: nền trời xanh nhạt, card trắng, indigo cho số/icon, vòng tròn lavender, chữ chính và muted text giữ đúng token hiện có.
- Image quality and asset fidelity: dùng lại `penguin-wave.png` và `learning-minimal-sky-background.png`; không thay bằng placeholder, emoji, CSS art hay SVG tự dựng.
- Copy and content: đủ tiêu đề, mô tả, 4 bước và câu lưu ý cuối như ảnh nguồn.

## Interaction and runtime verification

- In-app browser iOS: gate chặn màn chính và hiện 4 bước.
- Safari iOS: gate hiện 3 bước, bỏ bước “Mở bằng Safari”.
- PWA đã cài, Android, desktop và native app: gate đi thẳng vào app.
- Primary interaction: đây là màn hướng dẫn thủ công, không có CTA giả; Safari không cho website tự thực hiện Add to Home Screen.
- Console: không có lỗi; chỉ có cảnh báo thông tin của Flutter về việc thay meta viewport, không ảnh hưởng giao diện.

## Full-view and focused evidence

- Full-view comparison: `design-qa-assets/ios-pwa-install-comparison.png` cho thấy bố cục và tỷ lệ các vùng khớp ở cùng viewport/state.
- Focused crop riêng không cần thiết: comparison 870 × 809 giữ chữ, icon, mascot, bán kính card và khoảng cách ở kích thước đọc được; các chi tiết quan trọng đều rõ trong cùng một input.

## Comparison history

- Pass 1: không phát hiện P0/P1/P2; không cần vòng sửa hình ảnh.
- Post-check: widget tests, `flutter analyze`, release Web build và browser capture đều qua; không có regression nhìn thấy.

## Implementation checklist

- [x] Nối lại `PwaInstallGate` ở root app mà không khôi phục splash chặn mọi nền tảng.
- [x] Giữ `PwaUpdateGate` bên trong install gate để kiểm tra bản cập nhật chỉ xuất hiện một lần.
- [x] Bao phủ ba nhánh runtime bằng widget tests.
- [x] Xác minh release Web và so sánh trình duyệt ở đúng viewport.

final result: passed

---

# Design QA — Hướng dẫn sử dụng lần đầu trên APK và Web (2026-08-05)

## Evidence

- Source visual truth: `.codex-tmp/onboarding-reference-audit/contact-sheet.png` — 1000 × 2788 px, extracted from the supplied INNOTRIK onboarding video.
- Android implementation:
  - `.codex-tmp/onboarding-design-qa/android-first-launch.png` — 1080 × 2400 physical px, 360 × 800 logical px at DPR 3, including Android system bars.
  - `.codex-tmp/onboarding-design-qa/android-step-6-fixed.png` — the same viewport with the Settings/HFP spotlight active.
  - `.codex-tmp/onboarding-design-qa/android-complete.png` — the same viewport at the completion CTA.
- Browser-rendered implementation:
  - `.codex-tmp/onboarding-design-qa/web-first-launch-1440x900.png` — 1440 × 900 CSS px at device scale factor 1.
  - `.codex-tmp/onboarding-design-qa/web-step-6-1440x900.png` — the desktop Settings/HFP spotlight state.
  - `.codex-tmp/onboarding-design-qa/web-mobile-replay-390x844.png` — 390 × 843 captured px at the narrow Web breakpoint.
  - `.codex-tmp/onboarding-design-qa/web-dark-tour-390x844.png` — the narrow Web breakpoint in dark mode.
- Same-input full-view comparison: `.codex-tmp/onboarding-design-qa/onboarding-full-comparison.png` — 2160 × 2400 px.
- Focused Settings comparison: `.codex-tmp/onboarding-design-qa/onboarding-settings-comparison.png` — 1080 × 1200 px.
- Density normalization: the source contact sheet and Android capture were each contained in 1080 × 2400 comparison columns. For the focused board, one 250 × 558 source frame and the Android screen were independently scaled into equal 540 × 1200 columns while preserving aspect ratio.

## State and interaction coverage

- First launch opens a branded welcome card over the real home screen.
- Six spotlight steps cover speaking, translated results, vocabulary, topic listening, history, and Settings/HFP.
- Back, next, skip, completion, persistence, and manual replay from Settings were exercised on Android.
- Desktop Web, 390 px Web, light mode, dark mode, reload persistence, and manual replay from Settings were exercised in the in-app browser.
- The microphone permission prompt appears only after the user taps `Thử nói ngay`; the tour itself does not request it.
- Browser console check returned no error or warning.

## Required fidelity surfaces

- Fonts and typography: the implementation uses the app's established Roboto hierarchy with heavier child-friendly headings, readable Vietnamese wrapping, stable button labels, and no clipped text at 360 × 800, 390 × 843, or 1440 × 900.
- Spacing and layout rhythm: spotlight cards choose the opposite vertical region from their targets; the welcome/completion cards remain centered; rounded 28 px surfaces and practical tap targets match the existing home design system.
- Colors and visual tokens: the source's dimmed page, bright target ring, and high-contrast callout direction are retained with existing indigo/lavender tokens. Light and dark cards use theme surfaces rather than hard-coded light text.
- Image quality and asset fidelity: existing high-resolution INNOTRIK mascot assets are reused for welcome and completion; no emoji, placeholder, handcrafted SVG, or code-drawn mascot is introduced.
- Copy and content: Vietnamese and Simplified Chinese copy covers every step. The final Settings step explicitly explains that the current microphone remains usable and HFP is optional through Settings.

## Findings and comparison history

- Pass 1 found one P2 obstruction: on the Settings step, the top-right `Bỏ qua` action covered the highlighted Settings button, weakening the source's clear target-focus relationship.
- Fix: the skip action now moves to the opposite top corner whenever a highlighted header target occupies the upper-right region.
- Pass 2 evidence in `onboarding-settings-comparison.png` shows the Settings icon fully exposed with its two-ring spotlight while `Bỏ qua` remains reachable at the upper left. No actionable P0, P1, or P2 issue remains.
- Accepted P3 difference: the implementation uses a larger explanatory card than the source's small speech bubbles. This is intentional for young learners, Vietnamese wrapping, back/next controls, and consistent APK/Web behavior.

## Verification

- `flutter analyze`: passed with no issues.
- 49 focused startup, onboarding, home, settings, theme, conversation, accessibility, and golden tests: passed.
- Android debug install and emulator interaction: passed; no Flutter, framework, fatal, or RenderFlex error was found in the checked runtime logs.
- Release Web build: passed; local preview returned HTTP 200.
- Release APK build: passed.
- Residual test gap: one global concurrent `flutter test` run left a `flutter_tester` process waiting beyond ten minutes. It was stopped, then all suites touched by this feature were rerun serially and passed; this does not leave a visual or functional onboarding finding.

## Implementation checklist

- [x] Show the tour only on first use and persist its version.
- [x] Allow skip, back, next, completion, and replay from Settings.
- [x] Focus all six real home controls without routing to duplicate screens.
- [x] Explain phone/browser microphone fallback and optional INNOTRIK HFP.
- [x] Support Vietnamese and Simplified Chinese.
- [x] Support Android APK, responsive Web, light mode, and dark mode.
- [x] Verify visual comparison, runtime interactions, console, analyzer, tests, and release builds.

final result: passed

---

# Design QA — Startup loading experience (2026-08-05)

## Evidence

- Source visual truth: `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-2610f2d6-0c24-44b8-a5d0-233c8f7b3f45.png` — 848 × 1901 physical pixels.
- Browser-rendered implementation: `.codex-tmp/design-qa/startup-implementation-390x844.png` — Web viewport 390 × 844 CSS pixels, DPR 1.
- Same-input comparison: `.codex-tmp/design-qa/startup-comparison.png` — the source normalized to 376 × 844 and the implementation retained at 390 × 844.
- State: initial Web engine bootstrap followed by the Flutter startup screen. The Flutter screen remains visible for at least 1,800 ms, shows “Sẵn sàng!” for 160 ms, and then fades into the app.

## Full-view comparison

- Both views use a sparse vertical hierarchy: centered app icon, product name, short subtitle, one central progress/status surface, and generous breathing room.
- The red/cat reference was intentionally adapted to the existing INNOTRIK pale-blue palette and current penguin app icon instead of introducing a second brand identity.
- The status surface explains that only essential data is loaded before entry; non-critical warming continues in the background.
- The Web HTML bootstrap and Flutter startup screen share the same colors, icon, wording, spacing direction, and motion timing, preventing a blank-canvas flash during engine startup.
- No focused crop was needed because the icon, title, progress indicator, status copy, and bottom version area are legible in the normalized full-view comparison.

## Fidelity and accessibility

- Typography: bold INNOTRIK wordmark, compact supporting copy, and clear progress hierarchy remain readable on 390 × 844 and 320 × 568 viewports.
- Spacing: the centered column and compact fallback layout avoid overflow while preserving practical visual rhythm.
- Colors: `#EAF4FF` background, navy ink, indigo progress, and white translucent surfaces match the app's current design system.
- Assets: Web reuses `icons/Icon-512.png`; Android/Flutter uses the optimized 512 px `assets/icon/app_icon_splash.png`, avoiding the previous 1.9 MB first-frame decode.
- Motion: the icon pulse and transition respect reduced-motion preferences. Live startup status is exposed through semantics without adding an interactive blocker.
- Copy: all visible startup copy is Vietnamese and avoids implying that every dataset must finish before entry.

## Comparison history

- Pass 1 found a P2 issue: the Flutter-stage icon could appear blank briefly because the original 1.9 MB launcher image had not decoded before the transition.
- Fix: generated a 512 px optimized startup asset for native Flutter and reused the already requested Web manifest icon from browser cache.
- Pass 2: focused widget tests render the branded state at regular and compact viewports; analyzer, Web release build, and Android release build pass. The final in-app-browser recapture was unavailable under browser URL policy, but the visual structure was unchanged and the asset-loading regression is covered by the optimized resource plus widget/build verification.
- No actionable P0, P1, or P2 issue remains. The HTML-only bootstrap omits the package version because plugin data is not yet available; the Flutter startup screen displays it immediately afterward (accepted P3).

## Verification

- `flutter analyze --no-pub`: passed with no issues.
- `test/app/startup_splash_screen_test.dart`: 4 tests passed, covering the 1,800 ms minimum, branded state, compact layout, and shared listening-catalog preload.
- Release Web build with the Railway backend define: passed.
- Release APK `1.0.3+5` with the Railway backend define: passed; output size 78.9 MB.
- Initial browser console inspection: no errors.

final result: passed

---

# Design QA — Compact staggered home edge rails (2026-08-03)

- Source visual truth: `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-c84e2ddb-64af-45b2-a6bb-9772dd54fa3f.png`.
- Implementation: `test/features/home/goldens/home-communication-390x844.png` and `test/features/home/goldens/home-vocabulary-390x844.png`, 390 × 844 logical pixels at DPR 1.
- Comparison evidence: `.codex/design-qa/home-edge-rails/rails-before-after-full.png` and `.codex/design-qa/home-edge-rails/rails-before-after-focused.png`.
- Result: both collapsed rails changed from 51 × 270 to 47 × 224; the vocabulary rail now sits above the topic rail while the topic expansion remains 154 × 270.
- Fonts, spacing, color tokens, source assets, and copy were checked. No P0/P1/P2 issue remains.
- Analyze, six focused tests, release Web/APK builds, local Web navigation, and browser console checks passed.
- Detailed report: `.codex/design-qa/home-edge-rails/design-qa.md`.

final result: passed

+# Design QA — Nền tối giản và bỏ nút Đúng/Sai

## Evidence

- Source visual truth: `C:/Users/Windows/.codex/generated_images/019fac05-f74f-7952-9259-e708249b6185/exec-4d8df4a0-1f82-4c50-9978-8a536aa5e669.png` — 942 × 1672 px.
- Flutter mobile implementation: `test/goldens/conversation-ready-shortcut-450x1025.png` — 450 × 1025 logical px, DPR 1.
- Browser-rendered implementation: `.codex/design-qa/minimal-background/conversation-web.png` — 1280 × 720 px.
- Combined comparison input: `.codex/design-qa/minimal-background/source-vs-mobile.png` — 924 × 1077 px.
- State: màn giao tiếp đã có câu tiếng Anh; không hiển thị nút “Đúng ý” hoặc “Sai ý”.
- Density normalization: ảnh nguồn được crop trung tâm và chuẩn hóa về 450 × 1025 trước khi đặt cạnh ảnh Flutter mobile.

## Full-view comparison

- Nền giữ đúng bảng màu xanh trời, mint và blue-gray của nguồn nhưng giảm mạnh độ bão hòa và chi tiết.
- Vùng giữa có khoảng thở lớn; các thẻ trắng/lavender vẫn là điểm tập trung.
- Mây chỉ nằm ở mép trên, đồi chỉ nằm sát đáy nên không cạnh tranh với chữ hoặc CTA.
- Hai nút phản hồi đã được gỡ; bố cục kết quả tự khép lại tự nhiên, không để khoảng trống bất thường.

## Required fidelity surfaces

- Fonts and typography: Roboto, trọng lượng chữ, line-height và hierarchy không thay đổi; không có chữ bị cắt ngoài các quy tắc ellipsis sẵn có.
- Spacing and layout rhythm: khoảng cách giữa hero, result panel và CTA giữ nhịp cũ; vùng trước đây chứa feedback buttons được thu gọn.
- Colors and visual tokens: nền powder-blue/mint mới có độ tương phản thấp; indigo, lavender, success và surface token của UI giữ nguyên.
- Image quality and asset fidelity: nền raster 942 × 1672 rõ nét ở mobile lẫn Web, không có watermark, text, nhân vật hay chi tiết giả UI.
- Copy and content: nội dung giao tiếp không đổi; “Đúng ý” và “Sai ý” không còn trong DOM màn chính.
- Accessibility and responsiveness: 13 golden trạng thái mobile qua; không có overflow ở 450 × 1025.

## Interaction verification

- Topic shortcut mở được màn “Luyện nghe theo chủ đề” và quay lại màn giao tiếp.
- Browser DOM không chứa “Đúng ý” hoặc “Sai ý”.
- Web console không có error/warning; chỉ có log debug khởi tạo Flutter.

## Findings

- Không còn P0, P1 hoặc P2.
- Không cần focused crop riêng vì thay đổi chỉ liên quan nền toàn màn hình và việc loại bỏ hai control; cả hai đều đọc rõ ở full-view comparison.

## Comparison history

- Pass 1: nền nhiều chi tiết được thay bằng nền phẳng, ít bão hòa; hai nút feedback được gỡ. So sánh kết hợp xác nhận hierarchy, độ tương phản và nhịp dọc đều ổn, không cần vòng sửa P0/P1/P2.

final result: passed


---

# Design QA — Hành trình luyện nghe theo chủ đề

## Bằng chứng

- Nguồn thiết kế được chọn: `C:/Users/Windows/.codex/generated_images/019fb5fc-945a-7330-bd0d-b6ad15b55359/exec-fd883c65-d221-40f5-bdb8-491074a964b4.png` — 852 × 1846 px, tương ứng khung logic 426 × 923 ở DPR 2.
- Bản Flutter Web: `.codex/design-qa/topic-listening-web-426x923.png` — 426 × 922 px tại viewport logic 426 × 923, DPR 1.
- Bản Web màn hình rộng: `.codex/design-qa/topic-listening-web-1280x900.png` — nội dung giới hạn 760 px và căn giữa trong viewport rộng.
- Trạng thái mở chủ đề: `.codex/design-qa/topic-first-open-426x923.png`.
- So sánh cùng một đầu vào: `.codex/design-qa/topic-listening-comparison.png`; ảnh nguồn được thu về đúng 426 × 923 trước khi đặt cạnh bản Web.
- Golden Flutter: `test/goldens/topic-listening-426x923.png` — 426 × 923 logical px.

## Trạng thái và hành vi đã kiểm tra

- Nhóm tuổi 6–7 được chọn; thẻ “Tiếp tục học”, 10 chủ đề, thanh điều hướng và đường cong hành trình cùng hiển thị.
- Chọn nhóm 3–5 thay đúng danh mục, ảnh chủ đề và bài tiếp tục.
- Chạm chủ đề đầu tiên mở danh sách bài học đúng chủ đề; nút quay lại trở về đúng vị trí hành trình.
- Web console không có lỗi hoặc cảnh báo trong luồng đã kiểm tra.

## Đánh giá fidelity

- Bố cục: giữ đúng nhịp header → nhóm tuổi → tiếp tục học → hành trình; các điểm dừng xen kẽ hai bên và nối bằng Bézier mềm, không dùng đường thẳng cứng.
- Typography: tiêu đề và metadata có độ tương phản cao hơn sau vòng sửa thứ hai; bóng chữ trắng giúp nội dung đọc được trên nền phong cảnh mà không thêm nhiều khung AI.
- Màu sắc và hình ảnh: giữ nền phong cảnh mùa hè hiện có của sản phẩm, ảnh chủ đề thật, indigo cho đường đi/checkpoint và bề mặt trắng mờ cho thẻ tiếp tục học.
- Responsive: 426 × 923 không tràn hoặc che nút; màn hình rộng giữ chiều rộng nội dung tối đa 760 px và thanh điều hướng căn giữa.
- Accessibility: điểm chạm lớn, nội dung cuộn được, widget test bao phủ text scale 200% và compact phone.

## Lịch sử so sánh

- Pass 1: phát hiện metadata và số lượng chủ đề hơi chìm trên vùng núi/tàu (P2 về độ tương phản).
- Fix: đổi metadata sang màu ink đậm hơn, tăng font weight và tinh chỉnh bóng chữ trắng; không thêm hộp nền mới.
- Pass 2: so sánh cùng khung 426 × 923 cho thấy không còn P0, P1 hoặc P2 cần xử lý. Việc dùng nền tàu và mascot hiện có thay vì nền minh họa trong mock là lựa chọn giữ nhận diện sản phẩm, không làm thay đổi cấu trúc hành trình.

## Xác minh kỹ thuật

- `flutter analyze`: qua, không có issue.
- 9/9 test của `topic_listening_screen_test.dart`: qua.
- Golden riêng của màn topic listening: qua khi chạy độc lập.
- `flutter build web --release`: qua.
- `flutter build apk --release`: qua, APK 82.5 MB.
- Lần chạy toàn bộ suite trước vòng polish có 13 test lỗi trong `core_audio_streaming_fallback_test.dart`; đây là nhóm timing/fallback audio có sẵn và không thuộc các file giao diện hành trình.

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

---

# Design QA — Bỏ mascot VoiceHero và tăng độ cong hành trình

## Bằng chứng

- Nguồn VoiceHero: `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-16183f2a-2577-44f0-b214-1d7222af8b15.png` — 904 × 296 px, trạng thái idle có chim cánh cụt ở góc trái.
- Bản VoiceHero sau chỉnh sửa: `.codex/design-qa/conversation-no-penguin-426x923.png` — ảnh Web tại viewport 426 × 923 CSS px, DPR 1.
- Nguồn hành trình: `C:/Users/Windows/.codex/generated_images/019fb5fc-945a-7330-bd0d-b6ad15b55359/exec-fd883c65-d221-40f5-bdb8-491074a964b4.png` — 852 × 1846 px, chuẩn hóa về 426 × 923.
- Bản hành trình sau chỉnh sửa: `.codex/design-qa/topic-more-curved-426x923.png` — 426 × 923 CSS px, DPR 1.
- So sánh cùng một đầu vào: `.codex/design-qa/penguin-removal-and-curve-comparison.png`.
- Trạng thái: giao tiếp idle và danh mục luyện nghe nhóm 6–7 tuổi.

## So sánh và phát hiện

- VoiceHero không còn chim cánh cụt hoặc khoảng chồng hình ở góc trái; nội dung, bề mặt, icon trạng thái, waveform và CTA giữ nguyên.
- Mỗi chặng chủ đề nay dùng hai cubic Bézier nối tiếp với tangent liên tục. Phần giữa uốn rõ hơn và đoạn vào checkpoint vẫn tròn, không xuất hiện góc gãy.
- Font, hierarchy, màu indigo, bề mặt trắng mờ, ảnh chủ đề và copy không thay đổi ngoài phạm vi yêu cầu.
- Viewport 426 × 923 không có overflow; các checkpoint, đường nét và thanh điều hướng vẫn đọc được trên nền phong cảnh.
- Không cần focused crop riêng: vùng VoiceHero đã được so sánh ở kích thước component, còn đường đi chiếm phần lớn full-view 426 × 923.
- Không còn P0, P1 hoặc P2 cần xử lý.

## Lịch sử

- Pass 1: mascot được gỡ khỏi mọi trạng thái VoiceHero; không để lại asset reference hoặc semantic label thừa.
- Pass 2: đường cubic đơn được thay bằng hai cubic Bézier liên tục cho mỗi chặng; ảnh Web sau build xác nhận độ cong sâu hơn và không tạo gãy nét.

## Xác minh

- `flutter analyze`: qua, không có issue.
- 12 test chức năng liên quan VoiceHero và topic listening: qua.
- 4 golden của conversation/topic listening: qua sau khi cập nhật đúng thay đổi hình ảnh.
- Web console: không có error hoặc warning trong hai màn đã kiểm tra.

final result: passed
## 2026-08-02 — Shared minimal background

- Applied `learning-minimal-sky-background.png` to every non-song app surface.
- Kept `song-karaoke-sunrise.webp` as the karaoke-only artwork.
- Verified with focused analyze, 24 widget/golden tests, Web build, APK build, and Web browser inspection.
- Detailed evidence: `.codex/design-qa/all-app-background/design-qa.md`

final result: passed

---

# Design QA — Home, vocabulary, and topic-listening entry flow (2026-08-02)

## Evidence

- References: `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-68fbc637-f44e-4a44-8ddc-c905afcbc86f.png`, `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-cc63ad2b-2cf3-4128-9739-1e69356c31bb.png`, and `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-2dad1955-e825-4cd0-beff-6d80afb6d75d.png`; each source is 852 × 1840 px and was normalized to the 390 × 844 test viewport.
- Flutter captures: `test/features/home/goldens/home-communication-390x844.png`, `test/features/home/goldens/home-vocabulary-390x844.png`, and `test/features/home/goldens/home-add-vocabulary-390x844.png` at DPR 1.
- Combined same-input comparison: `design-qa-assets/home-vocabulary-flow-comparison.png`.
- States covered: communication home, persisted vocabulary list, and the add-vocabulary modal.

## Visual and interaction review

- Typography, hierarchy, indigo/lavender palette, translucent surfaces, mascot imagery, copy, spacing, controls, and scenic background were checked in the full-view comparison.
- The two edge destinations stay visible: the left rail opens vocabulary and changes to “Giao tiếp” on that page so it can return; the right rail opens the existing 50-topic listening screen.
- Vocabulary search, local persistence, add, delete mode, English pronunciation, history/settings access, Android back navigation, and the practice CTA were exercised through widget tests.
- The background intentionally reuses the app's existing high-quality train-field scenery; this is more saturated than the reference watercolor but was explicitly permitted by the product direction.

## Comparison history

- Pass 1 found P2 issues: the vocabulary title wrapped, the long bottom CTA clipped, the communication mascot was undersized, and the result/dialog surfaces had weak source proportions.
- Fixes: constrained the title to one line, rebuilt the CTA as a fixed full-width row, enlarged the mascot, and tightened the communication result panel plus modal spacing.
- Pass 2: no remaining P0, P1, or P2 issue. The modal remains slightly more compact than the reference to preserve legibility and keyboard space on small devices (P3, accepted).

## Verification

- `flutter analyze`: passed with no issues.
- 10 focused functional, accessibility, localization, persistence, navigation, and golden tests: passed.
- 4 existing conversation/topic-listening goldens: updated and passed again without diffs.
- Release Web build and release APK build: passed; local Web preview returned HTTP 200.

final result: passed

---

# Design QA — Expanded “Chủ đề” edge transition (2026-08-03)

## Evidence

- Source motion truth: `C:/Users/Windows/Downloads/2aOboQoit8DB2wy9p4aNmdPCcApiS5fYoEfcupoO.mp4`.
- Selected source frame: `outputs/coach-reference-frames/frame-06.jpg`, 544 × 1233 px; the app-owned area was cropped and normalized to a 390 px comparison width.
- Flutter implementation: `test/features/home/goldens/home-topic-expanded-390x844.png`, 390 × 844 logical pixels at DPR 1.
- Same-input full-view comparison: `design-qa-assets/topic-expanded-video-comparison.png`.
- State: the right edge destination after tapping and immediately before the topic catalog slides in.

## Findings

- No P0, P1, or P2 mismatch remains. The implementation preserves the source interaction pattern: an edge-anchored rail widens inward, swaps its vertical label for a centered icon and horizontal title, then reveals the destination with a right-to-left slide.
- Typography and copy: the long “Luyện nghe theo chủ đề” label is replaced by “Chủ đề” on both the rail and destination header; the “50 chủ đề” rail badge is absent.
- Spacing and layout: the expanded panel remains attached to the right edge, with centered content and rounded inner corners. It intentionally stays taller than the video reference for a more noticeable 300 ms child-friendly transition (P3, accepted).
- Colors and tokens: the existing purple gradient, white foreground, border, radius, and shadow are preserved.
- Image quality: no source raster was replaced or synthesized; the change uses the existing Material headphones icon and app scenery.
- The full-view board keeps both the transition panel and surrounding layout readable, so an additional focused crop was not required.

## Comparison history

- Pass 1: the implementation had the correct width expansion, but the first golden captured the animation's initial frame and appeared collapsed.
- Fix: started the animation on one frame, then captured at 280 ms before the 300 ms navigation delay; the revised comparison visibly shows the expanded panel.
- Post-fix: no actionable P0/P1/P2 issue remains.

## Verification

- `flutter analyze`: passed with no issues.
- 19 focused navigation, motion, accessibility, responsive, topic-content, and golden tests: passed.
- Compact 320 × 568 layout with 200% text and reduced motion: passed without overflow.
- Release Web and APK builds: passed; the local Web server returned HTTP 200. Automated in-app-browser navigation to the loopback URL was unavailable under browser URL policy, so the browser interaction was not claimed as evidence.

final result: passed
