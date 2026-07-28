# Design QA — INNOTRIK APK download page (clean revision)

## Evidence

- Source visual truth: browser annotation screenshot selecting the “Ba bước thật dễ” installation block.
- Previous implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\apk-download-page\implementation-mobile-roboto.png`.
- Revised implementation URL: `http://127.0.0.1:4173/`.
- Revised screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\apk-download-page\implementation-mobile-clean.png`.
- Side-by-side evidence: `C:\Users\Windows\Documents\ai-speaking-flutter-app\apk-download-page\design-comparison-clean.png`.
- CSS viewport: 390 × 844 at 1× browser capture density.
- State: default Android download landing page after the entrance animation completed.

## Findings

- No P0, P1 or P2 differences remain for the requested annotation.
- The `.install-card`, its three `.step` rows and the “Ba bước thật dễ” text are absent from the rendered DOM.
- The page has no horizontal overflow at the mobile viewport.
- Roboto remains the computed font, the supplied INNOTRIK icon loads successfully and the APK link is unchanged.
- Browser console contains no errors or warnings.

## Required fidelity surfaces

- Fonts and typography: Roboto remains active with the same hierarchy, weights and Vietnamese rendering.
- Spacing and layout rhythm: the selected installation block is removed and the footer follows the Zalo note; no unrelated spacing was redesigned.
- Colors and tokens: all existing colors and component tokens remain unchanged.
- Image quality: `app_icon.png` remains sharp, correctly proportioned and unchanged.
- Copy and content: only the annotated “Ba bước thật dễ” section and its three instructions were removed.

## Comparison history

- Earlier state: the page included the annotated three-step installation card beneath the Zalo note.
- Fix applied: removed the entire installation section and all now-unused CSS selectors.
- Post-fix evidence: `design-comparison-clean.png` visibly shows that the annotated block is gone while the rest of the page remains intact.
- No focused crop was needed because the removed block occupies a large, clearly readable region in the full-view comparison.

final result: passed
