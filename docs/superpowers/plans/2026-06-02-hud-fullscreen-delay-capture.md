# HUD Full-Screen And Delay Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full-screen and five-second delay capture actions to the screenshot HUD.

**Architecture:** The overlay emits a new full-screen completion for all-screen capture, while delayed capture remains a normal capture completion emitted after a HUD-owned countdown. The app delegate routes full-screen completion to a CaptureService API that captures each attached screen independently.

**Tech Stack:** Swift, AppKit, CoreGraphics, SwiftPM XCTest.

---

### Task 1: Completion And Full-Screen Capture Model

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayCompletion.swift`
- Modify: `Sources/FrameApp/CaptureService.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`
- Test: `Tests/FrameAppTests/CaptureServiceTests.swift`

- [ ] Add a failing test that `SelectionOverlayCompletion.fullScreen` has no selection.
- [ ] Add a failing test that full-screen rect planning returns one rect per screen frame.
- [ ] Add `.fullScreen` to `SelectionOverlayCompletion`.
- [ ] Add `CaptureService.fullScreenRects(from:)` and `captureFullScreens()`.
- [ ] Run targeted tests.

### Task 2: HUD Buttons And Delay Countdown

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [ ] Add failing tests that a test overlay exposes "全屏截图" and "延迟截图" HUD buttons.
- [ ] Add a failing async test that delay capture completes after the injected short countdown.
- [ ] Add two HUD icon buttons, tooltips, and theme updates.
- [ ] Add delay countdown state that freezes selection edits and emits `.capture(snapshotSelection)` after five seconds.
- [ ] Run targeted tests.

### Task 3: App Flow Integration

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] Route `.fullScreen` completion to `CaptureService.captureFullScreens()`.
- [ ] Store and show each full-screen screenshot independently.
- [ ] Preserve Quick Access restoration and capture failure handling.
- [ ] Run `swift test`.

### Task 4: Verification And Local Replacement

**Files:**
- Generated: `.build/app/Frame.app`
- Replace: `/Users/bytedance/Applications/Frame.app`

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh`.
- [ ] Replace `/Users/bytedance/Applications/Frame.app`.
- [ ] Verify code signature and launch the app.
