# HOMI three-screen design QA

## Comparison setup

- Visual source of truth: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-0e27c836-b150-414a-9035-4524567f663d.png`
- Flutter captures:
  - `test/features/home/goldens/home-communication-390x844.png`
  - `test/features/onboarding/goldens/startup-profile-390x844.png`
  - `test/features/home/goldens/home-vocabulary-390x844.png`
- Combined comparison: `output/design-qa/homi-three-screen-comparison.png`
- Viewport: 390 x 844 logical pixels, device pixel ratio 1.0.
- States: home idle; setup profile with age 6–7 selected; vocabulary empty state.
- Normalization: each reference panel was cropped from the supplied three-screen board and scaled to the same 390 x 844 frame as its Flutter capture.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the setup mascot is intentionally smaller in the responsive Flutter layout so the age list, locked-setting notice, and primary action remain visible without clipping on shorter Android devices.
- P3: the home hero uses the supplied HOMI mascot plus a generated raster background asset instead of recreating the reference artwork with vector/CSS-like primitives.
- Typography, hierarchy, primary actions, selected states, navigation placement, and asset roles match the selected visual direction.
- The three core screens remain usable at the target viewport with no overflow, clipped controls, or unreadable text.

## Comparison history

1. Initial implementation comparison completed on 2026-09-08 using the combined side-by-side evidence image.
2. No actionable P0, P1, or P2 mismatch remained after inspection.

## Result

passed
