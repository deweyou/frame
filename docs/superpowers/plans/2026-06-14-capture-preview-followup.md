# Capture Preview Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or inline TDD execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine delay countdown, Quick Access hover previews, recording preview preservation, and zero-size HUD behavior after local testing feedback.

**Architecture:** Keep changes in the existing AppKit controllers. `SelectionOverlayWindow` owns countdown and selection-size HUD behavior. `QuickAccessPanelController` owns preview stack lifecycle and hover popover geometry.

**Tech Stack:** Swift 6, SwiftPM, AppKit, AVKit, XCTest.

---

### Task 1: Delay Countdown And Zero-size HUD

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [x] Add failing tests that the delay countdown uses red styling and full-screen bottom-center placement.
- [x] Add a failing test that no valid selection hides the HUD instead of exposing `0 x 0`.
- [x] Change `CountdownView` to use a red background.
- [x] Stop updating the size control to `0 x 0` when no valid selection exists.
- [x] Run `swift test --filter SelectionOverlayCompletionTests`.

### Task 2: Quick Access Hover Preview

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Test: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`

- [x] Add failing tests that hover preview delay is 2 seconds.
- [x] Add failing tests that the popover frame is larger, has no arrow, and uses aspect-fit media sizing.
- [x] Change the default hover delay to 2 seconds.
- [x] Keep the hover preview as a rounded right-side popover without an arrow.
- [x] Size the popover from the media's original aspect ratio, capped by a larger maximum.
- [x] Use aspect-fit image/video rendering so full media is visible.
- [x] Run `swift test --filter RecordingQuickAccessPanelControllerTests`.

### Task 3: Preserve Existing Quick Access During Recording

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Test: `Tests/FrameAppTests/ScreenshotDragItemProviderTests.swift`

- [x] Replace the stale expectation that recording start closes managed previews with a failing preservation test.
- [x] Change recording start behavior to temporarily hide managed previews and clean only orphan panels.
- [x] Ensure recording completion restores hidden previews before adding the new recording card.
- [x] Run `swift test --filter ScreenshotDragItemProviderTests`.

### Task 4: Docs And Verification

**Files:**
- Modify: `DESIGN.md`
- Modify: `docs/architecture.md`

- [x] Update durable docs for red countdown, aspect-fit popover, 2-second delay, and recording preview preservation.
- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `scripts/package-app.sh`.
- [x] Replace local stable-signed app after verification.
