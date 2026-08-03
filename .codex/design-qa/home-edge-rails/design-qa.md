# Design QA — Compact staggered home edge rails (2026-08-03)

## Source and implementation evidence

- Source visual truth: `C:/Users/Windows/AppData/Local/Temp/codex-clipboard-c84e2ddb-64af-45b2-a6bb-9772dd54fa3f.png` (504 × 1019 px, including the phone frame).
- Source normalization: the app-owned screen was cropped to `(28, 0, 493, 1019)` and fitted to the 390 × 844 logical-pixel target.
- Implementation screenshot: `test/features/home/goldens/home-communication-390x844.png` (390 × 844 px, DPR 1).
- Secondary implementation screenshot: `test/features/home/goldens/home-vocabulary-390x844.png` (390 × 844 px, DPR 1).
- Full-view comparison: `.codex/design-qa/home-edge-rails/rails-before-after-full.png`.
- Focused rail comparison: `.codex/design-qa/home-edge-rails/rails-before-after-focused.png`.
- State: communication home with both collapsed edge rails; the vocabulary state was also checked to confirm that the longer `Giao tiếp` label fits.

## Findings

- No actionable P0, P1, or P2 issue remains.
- Fonts and typography: the existing Roboto hierarchy and vertical uppercase rail labels are unchanged; `Từ vựng`, `Chủ đề`, and the longer return label `Giao tiếp` remain readable without clipping.
- Spacing and layout rhythm: both collapsed rails are now 47 × 224 px instead of 51 × 270 px. The vocabulary rail is aligned at `-0.20`, while the topic rail is aligned at `-0.05`, creating a clear stagger without colliding with the header or bottom CTA.
- Colors and visual tokens: the existing indigo and purple gradients, white border, rounded inner corners, shadows, and icon colors are preserved.
- Image quality and asset fidelity: the approved minimal sky background and penguin assets are unchanged and remain sharp at the tested viewport.
- Copy and content: no product copy or destination behavior changed.

## Comparison history

- Pass 1 source issue: both rails were visually long for their short labels and appeared almost level with each other (P2 visual rhythm).
- Fix: reduced only the collapsed rail dimensions and raised the vocabulary rail relative to the topic rail; retained the larger topic-rail expansion size.
- Pass 2 evidence: the full and focused comparison boards show shorter rails and an approximately 46 px top offset at 390 × 844. No P0/P1/P2 mismatch remains.

## Verification

- Focused Flutter analyze: passed with no issues.
- Six focused functional, accessibility, navigation, motion, and golden checks: passed.
- Release Web build: passed.
- Release APK build: passed (`build/app/outputs/flutter-apk/app-release.apk`, 84.0 MB).
- In-app browser: the local Web build opened, the vocabulary rail navigated to the vocabulary page, and console warnings/errors were empty.
- A focused comparison was required because the rail-size and vertical-offset changes are small relative to the full screen.

final result: passed
