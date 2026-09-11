# Audio session modularization baseline

Baseline production commit: `97261f92ec542b0ac7c0159649648288719a205e`

Refactor branch: `codex/audio-session-modularization`

This document records the cross-feature behavior that must remain stable while
the audio architecture is separated into modules. It is a regression contract,
not a request to change the current user experience.

## Locked behavior

| Boundary | Regression coverage |
| --- | --- |
| Physical MAIN interrupts continuous translation before the assistant opens | `main_speaking_session_controller_test.dart`: `physical MAIN cancels translation before opening the assistant` |
| MAIN pauses and resumes an active listening lesson | `lesson_practice_navigation_test.dart`: `MAIN commands pause, resume, and leave the lesson for home` |
| A spoken prompt completes before navigation requests the microphone | `voice_navigation_controller_test.dart`: `does not reopen the microphone until the wake reply finishes` |
| A late lesson capture/evaluation callback cannot reclaim a newer MAIN turn | `lesson_guided_flow_test.dart`: `MAIN invalidates an evaluation that finishes after pause` and `MAIN detaches a pending lesson microphone start before takeover` |
| Stopping translation hands control to the navigation microphone | `voice_navigation_controller_test.dart`: `translation stop opens its navigation menu and microphone` |
| A caller-provided lesson evaluator is used and remains caller-owned | `lesson_guided_flow_test.dart`: `keeps an injected lesson evaluator caller-owned` |
| Android online-first evaluation and offline fallback preserve good/retry/unclear | `lesson_attempt_evaluator_test.dart`: `Android backend-first offline fallback` group |

## Phase 0 verification

- `flutter analyze --no-pub`: passed.
- `voice_navigation_controller_test.dart`: passed (33 tests).
- The two navigation timing cases that failed only during one parallel full-suite
  run both passed alone and when the complete file was rerun. They are recorded
  as baseline parallel-run timing flakes, not product regressions.
- Complete non-golden suite: passed, 661 tests across 93 files
  (`--concurrency=1`).
- The complete non-golden test suite must pass before every phase is committed.

## Platform invariants

Android and iOS use separate native audio adapters, but both must retain these
observable rules:

1. Only one feature owns capture or prompt playback at a time.
2. MAIN takeover invalidates late callbacks from the previous feature.
3. Prompt completion precedes the next microphone opening.
4. A custom evaluator supplied by a caller is never replaced or disposed by the
   lesson screen.
5. Refactoring must not change backend routes, request ordering, matching rules,
   offline fallback decisions, or lesson navigation text.
