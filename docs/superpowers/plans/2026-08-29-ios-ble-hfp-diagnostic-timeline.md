# iOS BLE-HFP Diagnostic Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record and display one persistent, timestamped iOS timeline that proves when MAIN, HFP routing, BLE disconnect/reconnect, MAIN notification readiness, and Parent-screen opening occurred.

**Architecture:** Reuse `IOSAudioSessionCoordinator` as the single native timeline buffer because BLE and HFP already report into it. Add canonical diagnostic stages at the exact native callbacks, expose the bounded buffer through the AIV0 BLE status snapshot, decode it into typed Dart events, and render it in the existing H20 diagnostics card. The Parent screen records its open marker explicitly through the method channel before the sheet is displayed; opening the sheet does not initiate a connection.

**Tech Stack:** Swift/CoreBluetooth/AVAudioSession, Flutter/Dart method channels, `flutter_test`, XCTest (compile coverage on Codemagic).

**Spec:** User request in the current task, including the test sequence of two physical MAIN presses before opening Parent settings.

---

### Task 1: Lock the Dart timeline contract with a failing test

**Files:**
- Modify: `test/core_device_aiv0_ble_control_test.dart`
- Modify: `lib/core/device/aiv0_ble_control.dart`

- [x] Add a test with an unsorted native `diagnosticTimeline` payload and assert typed event decoding, timestamp ordering, and retained metadata.
- [x] Run the focused test and confirm it fails because the timeline contract does not exist.
- [x] Add the minimal Dart event model and `Aiv0BleStatus` decoder.
- [x] Run the focused test and confirm it passes.

### Task 2: Add the native merged timeline and canonical event boundaries

**Files:**
- Modify: `ios/Runner/IOSAudioSessionCoordinator.swift`
- Modify: `ios/Runner/Aiv0BleControlBridge.swift`
- Modify: `ios/Runner/HfpAudioBridge.swift`
- Modify: `ios/RunnerTests/RunnerTests.swift`

- [x] Expose a bounded copy of the coordinator trace buffer without attaching a live trace sink.
- [x] Record canonical stages for `MAIN_RAW_RECEIVED`, `HFP_ROUTE_START_REQUESTED`, `HFP_ROUTE_CONFIRMED`, `BLE_DISCONNECT_REQUESTED`, `BLE_DISCONNECTED`, `BLE_CONNECTED`, `MAIN_NOTIFY_ENABLED`, and `PARENT_SCREEN_OPENED` at the exact native boundary.
- [x] Include the trace snapshot in each AIV0 BLE status payload and add a method-channel operation for the Parent marker.
- [x] Add/update XCTest coverage for bounded ordering and any pure policy behavior used by the timeline.

### Task 3: Mark Parent opening and render the timeline

**Files:**
- Modify: `lib/core/device/aiv0_ble_control.dart`
- Modify: `lib/features/conversation/presentation/conversation_controller.dart`
- Modify: `lib/features/home/presentation/home_learning_shell.dart`
- Modify: `lib/features/conversation/presentation/conversation_screen.dart`
- Modify: `lib/features/settings/presentation/settings_sheet.dart`
- Modify: relevant Flutter tests/fakes under `test/`

- [x] Add `markParentDiagnosticsOpened()` to the BLE control contract and method-channel implementation.
- [x] Expose a controller method that records the marker and refreshes the returned status.
- [x] Invoke it immediately before presenting the settings sheet, after parental access succeeds and before the sheet can trigger UI work.
- [x] Render a selectable `Timeline BLE / HFP` list using `HH:mm:ss.SSS`, canonical stage, caller, route, and relevant values.
- [x] Ensure existing fake controls compile and tests prove the marker method and visible timeline behavior.

### Task 4: Verify and ship the diagnostic build

**Files:**
- Verify all modified files.

- [x] Run focused Flutter tests.
- [x] Run `flutter analyze` and the relevant broader test suite.
- [x] Inspect `git diff --check` and the final diff for unrelated changes.
- [ ] Commit and push `codex/ios-app-store-release`.
- [ ] Start and monitor a new Codemagic iOS build; report the build URL and exact physical test steps.
