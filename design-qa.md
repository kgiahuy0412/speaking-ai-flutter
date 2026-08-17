# Design QA — Vocabulary journey screen

## Source and implementation

- Reference: `C:\Users\DELL\AppData\Local\Temp\codex-clipboard-b834531c-c2d3-467a-9134-be99aa2d5599.png`
- Reference size: 853 × 1882 px, portrait.
- Rendered implementation: `test/features/home/goldens/home-vocabulary-390x844.png`
- Test viewport: 390 × 844 logical px at device-pixel ratio 1.
- State: Vietnamese, assistant ready, three persisted starter vocabulary entries.

## Comparison evidence

- Full-screen comparison: `design-qa/vocabulary-reference-vs-implementation.png`
- Focused card comparison: `design-qa/vocabulary-cards-reference-vs-implementation.png`

Both comparison files place the resized/cropped reference on the left and the Flutter render on the right at the same 390 × 844 viewport.

## Findings

- Header hierarchy, centered title/subtitle, pastel scenery, three-card rhythm, rounded corners, shadows, accent colors, mascot placement, and circular arrow actions match the reference direction.
- The search and add controls remain functional and use the requested top-right placement.
- Family, Stars, and Review cards are tappable and open their corresponding vocabulary collection state.
- Counts intentionally use persisted application data instead of the reference image's fixed mock values (`12`, `8`, and `5`).
- Existing global side navigation rails are retained as product shell chrome; the redesigned content remains readable and tappable around them.
- The generated star and review-book assets are transparent, correctly scaled, and not visibly cropped or stretched.
- No text overflow, broken constraints, inaccessible primary action, or blocking visual mismatch was found at the target viewport.

## QA history

1. Initial render exposed asynchronous blank image slots in the golden test; all new image assets were added to the precache set.
2. Header action sizes, title/card vertical positions, and card widths were adjusted against the full-screen comparison.
3. Card text padding was reduced so Vietnamese count labels fit the same visual rhythm as the reference.
4. Full and focused comparisons were reopened after the final render; no P0, P1, or P2 issue remained.

final result: passed
