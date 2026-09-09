# Design QA — HOMI unified native learning surfaces

## Source and implementation

- Source visual truth: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-77aaa820-af17-40dc-8f36-d8c71a479ade.png` (1510 × 1042 px), containing the six requested target states.
- Combined comparison input: `output/design-qa/homi-six-screen-comparison.png` (1200 × 2580 px).
- Flutter capture viewport: 390 × 844 logical pixels. Settings, H20, audio/data, history, and challenge captures render at device-pixel ratio 3.0 (1170 × 2532 px); sentence practice renders at device-pixel ratio 1.0 (390 × 844 px). All six were normalized to the same portrait cell size in the combined comparison.
- Native scope: shared Flutter widgets used by both Android and iOS. Android APK output was compiled; the iOS-specific settings state was exercised with `TargetPlatform.iOS` in widget tests.
- Captured states:
  1. `test/features/settings/goldens/settings-turn-controls-390x844.png`
  2. `test/features/settings/goldens/settings-h20-390x844.png`
  3. `test/features/listening/goldens/lesson-v4-challenge-390x844.png`
  4. `test/features/settings/goldens/settings-audio-data-390x844.png`
  5. `test/features/settings/goldens/history-empty-390x844.png`
  6. `test/features/listening/goldens/lesson-practice-390x844.png`

## Comparison evidence

- Full-view evidence: the upper half of `output/design-qa/homi-six-screen-comparison.png` contains the supplied six-panel source; the lower half contains the six rendered native states in the same order.
- Focused evidence: each implementation capture remains readable as a full 390 × 844 portrait frame inside the same comparison input, including the H20 diagnostics rows, offline toggle, silence slider, history filters, listening choices, wave state, and pronunciation controls.
- Rendering note: the Flutter golden test font lacks Simplified Chinese glyphs, so the inactive Chinese language segment appears as fallback boxes in the test capture. Production Android/iOS builds use their system CJK fallback fonts; this is a test-renderer limitation, not a native UI defect.

## Findings

- P0: none.
- P1: none.
- P2: none after iteration.
- Structure: six surfaces now share one visual vocabulary for radii, borders, icon badges, status pills, input fields, chips, sliders, buttons, and navigation states.
- Frame density: related settings are grouped into one surface with internal dividers. H20 BLE, HFP, pin/firmware, technical details, and MAIN packet data no longer appear as a stack of unrelated cards.
- Hierarchy: navy headings, indigo actions, restrained lavender fills, coral warnings, and green success states follow the supplied reference while keeping the app bright.
- Voice feedback: circular busy indicators in the requested speaking/listening flows were replaced by an animated waveform that honors reduced-motion settings.
- Child experience: challenge and practice retain large touch targets, short labels, mascot imagery, and a calm sky background. Empty history now includes the HOMI mascot and explanatory copy.
- Content resilience: all long settings remain inside existing scroll containers; expandable technical sections keep diagnostics available without making the default screen excessively long.
- Accessibility: interactive controls retain Material semantics, visible selected/disabled states, and at least 48 logical pixel targets. Text is allowed to wrap rather than being clipped.
- Functional correction found during QA: history loading now copies repository results before sorting, so immutable empty lists no longer produce `Unsupported operation: Cannot modify an unmodifiable list`.

## Comparison history

1. Initial implementation unified the global component tokens and converted the six requested areas to shared HOMI surfaces.
2. First rendered pass exposed a white rectangle where a tinted raster waveform was used. The tinted state was replaced with a native equalizer glyph while the full blue raster waveform remains for static samples.
3. H20 was condensed into one grouped surface; technical and MAIN packet diagnostics were moved into collapsible sections.
4. The audio/data capture was aligned to the offline section and verified with the ready/on state. Privacy actions were grouped with internal dividers.
5. Empty history initially exposed immutable-list sorting and then lacked a loaded mascot in the golden frame. Both were corrected and the final capture was regenerated.
6. Final combined comparison showed no actionable P0, P1, or P2 mismatch. Analyzer, targeted functional tests, visual regression tests, and Android APK compilation passed.

final result: passed
