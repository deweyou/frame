# Recording And Capture Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the requested recording and capture polish issues across shortcuts, overlays, history, Quick Access, and copy.

**Architecture:** Keep deterministic shortcut validation in `FrameCore`, route app behavior through `FrameApp` controllers, and preserve existing native AppKit surfaces. Add small test seams instead of broad UI rewrites.

**Tech Stack:** Swift 6, SwiftPM, AppKit, SwiftUI Settings, Carbon hot keys, AVKit, ImageIO, XCTest.

---

### Task 1: Shortcut Model And Store

**Files:**
- Modify: `Sources/FrameCore/KeyboardShortcut.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Test: `Tests/FrameCoreTests/FrameCoreTests.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [x] Add failing tests for a default recording shortcut of `⌘⇧R`, recording shortcut persistence, and duplicate screenshot/recording validation.
- [x] Generalize shortcut validation so both screenshot and recording shortcuts use the same supported key/modifier rules.
- [x] Preserve screenshot shortcut migration from legacy preset strings.
- [x] Add `SettingsStore.recordingShortcut()` and `SettingsStore.setRecordingShortcut(_:)`.
- [x] Run `swift test --filter FrameCoreTests --filter SettingsStoreTests`.

### Task 2: Hot Key Routing

**Files:**
- Modify: `Sources/FrameApp/HotKeyController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Test: `Tests/FrameAppTests/HotKeyControllerTests.swift`
- Test: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [x] Add failing tests that Carbon parameters map the recording shortcut and that dispatched hot key IDs call separate screenshot/recording callbacks.
- [x] Register screenshot and recording hot keys with distinct Carbon IDs.
- [x] Add `onRecording` routing in `HotKeyController`.
- [x] Add an AppDelegate recording-shortcut entry point that starts selection in recording setup mode.
- [x] Run `swift test --filter HotKeyControllerTests --filter AppDelegateRecordingTests`.

### Task 3: Settings UI For Recording Shortcut

**Files:**
- Modify: `Sources/FrameApp/SettingsWindowController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/SettingsWindowControllerTests.swift`
- Test: `Tests/FrameAppTests/AppStringsTests.swift`

- [x] Add failing tests for two shortcut rows and duplicate shortcut error copy.
- [x] Add a recording shortcut recorder row in General or Recording settings using the existing recorder button.
- [x] Reject a new shortcut when it duplicates the other shortcut.
- [x] Suspend both global hot keys while either shortcut recorder is active, then re-register both.
- [x] Run `swift test --filter SettingsWindowControllerTests --filter AppStringsTests`.

### Task 4: Overlay Modes, Delay Countdown, And Window Selection

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/WindowCandidateProvider.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`
- Test: `Tests/FrameAppTests/WindowCandidateProviderTests.swift`

- [x] Add failing tests for initial recording setup mode, passive delay countdown mouse behavior, bottom-center countdown frame, prominent countdown colors, and Settings/History window eligibility.
- [x] Add an initial overlay mode parameter.
- [x] During delay countdown, snapshot selection and switch overlay windows to mouse-passive while keeping countdown visible.
- [x] Move the countdown to the current screen's bottom-center area and apply stronger accent styling.
- [x] Refine Frame window exclusion so Settings and Capture History can be selected by double-click.
- [x] Run `swift test --filter SelectionOverlayCompletionTests --filter WindowCandidateProviderTests`.

### Task 5: Recording Startup Smoothness

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Sources/FrameApp/RecordingBoundaryOverlayController.swift`
- Test: `Tests/FrameAppTests/RecordingBoundaryOverlayControllerTests.swift`
- Test: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [x] Add failing tests for reusing/updating the boundary overlay during preparation instead of closing and recreating it.
- [x] Show the passive recording boundary before dismissing the selection overlay and update it in place when recording starts.
- [x] Avoid unnecessary close/reopen transitions in `RecordingBoundaryOverlayController.show`.
- [x] Run `swift test --filter RecordingBoundaryOverlayControllerTests --filter AppDelegateRecordingTests`.

### Task 6: History Thumbnails And Copy

**Files:**
- Modify: `Sources/FrameApp/CaptureHistoryWindowController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/CaptureHistoryWindowControllerTests.swift`
- Test: `Tests/FrameAppTests/AppStringsTests.swift`

- [x] Add failing tests that recording records show first-frame thumbnails when available.
- [x] Inject or use `RecordingThumbnailProvider` in Capture History.
- [x] Update Chinese copy from screenshot-only history language to capture-history language.
- [x] Keep fallback video placeholder for undecodable recordings.
- [x] Run `swift test --filter CaptureHistoryWindowControllerTests --filter AppStringsTests`.

### Task 7: Quick Access Card Polish And Hover Preview

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Sources/FrameApp/CapturePreviewMetrics.swift`
- Test: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`

- [x] Add failing tests that screenshot and recording Quick Access panels share one card size.
- [x] Add failing tests for hover preview delay, right-side popover placement, image rendering, and muted recording playback.
- [x] Move screenshot cards to the same size baseline as recording cards.
- [x] Improve the MP4/GIF setup icon/label treatment so selected GIF is obvious.
- [x] Add a Quick Access hover preview panel that opens after two seconds and closes on hover exit.
- [x] Run `swift test --filter RecordingQuickAccessPanelControllerTests`.

### Task 8: Docs, README, And Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `DESIGN.md`
- Review: `README.md`
- Review: `README_ZH.md`

- [x] Update durable docs for recording shortcut, passive delay countdown, history thumbnails, and hover preview.
- [x] Check whether `README.md` and `README_ZH.md` need user-facing updates and keep them aligned if changed.
- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `scripts/package-app.sh`.
- [ ] For GUI handoff, ask whether to replace the local test app unless already done in this turn.
