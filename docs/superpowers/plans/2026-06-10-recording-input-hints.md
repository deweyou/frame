# Recording Input Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Finish CleanShot X-style recording input hints by using one mouse-hint control for cursor plus click highlights, showing held keyboard input during recording, and preventing capture shortcut re-entry during active flows.

**Architecture:** Reuse the existing `RecordingOverlayEventStore`, `RecordingOverlayRenderer`, and `RecordingLiveOverlayController` added by the recording overlay work. Add the missing option and HUD toggle, track active key state, and add a small AppDelegate busy-state guard around capture entry.

**Tech Stack:** Swift 6.2, AppKit, ScreenCaptureKit, CoreVideo/CoreGraphics, XCTest, Swift Package Manager.

---

### Task 1: Add Click Highlight Option

**Files:**
- Modify: `Sources/FrameCore/RecordingOptions.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Modify: `Sources/FrameApp/RecordingOverlayRenderer.swift`
- Test: `Tests/FrameAppTests/RecordingServiceTests.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [x] **Step 1: Write failing tests**
  - Add a `RecordingServiceTests` assertion that default overlay configuration records click highlights.
  - Add a `SettingsStoreTests` assertion that persisted cursor and click-highlight values are normalized into one mouse hint setting.
  - Run: `swift test --filter RecordingServiceTests --filter SettingsStoreTests`
  - Expected: FAIL because `RecordingOptions` has no `showsMouseClickHighlights`.

- [x] **Step 2: Implement minimal option support**
  - Add `showsMouseClickHighlights: Bool` to `RecordingOptions`, defaulting to `true`.
  - Add `recordingShowsMouseClickHighlightsKey` to `SettingsStore`.
  - Read/write the new option with default-on behavior and normalize split legacy values to one mouse hint value.
  - Change `RecordingOverlayConfiguration.recordsMouseClicks` to use `options.showsMouseClickHighlights`, not `options.showsCursor`.

- [x] **Step 3: Verify**
  - Run: `swift test --filter RecordingServiceTests`
  - Run: `swift test --filter SettingsStoreTests`
  - Expected: PASS.

### Task 2: Add Recording HUD Toggle For Click Highlights

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [x] **Step 1: Write failing HUD tests**
  - Update recording setup HUD expectations to include `显示鼠标提示`.
  - Add a test that clicking `显示鼠标提示` toggles cursor and click-highlight options passed to `onStartRecording`.
  - Run: `swift test --filter SelectionOverlayCompletionTests`
  - Expected: FAIL because the HUD has no click highlight button.

- [x] **Step 2: Implement HUD button**
  - Add `makeShowMouseClickHighlightsButton()`.
  - Insert it in setup controls beside format and keyboard hint controls, replacing the separate cursor button.
  - Add `showMouseClickHighlightsButtonClicked()`.
  - Thread `showsMouseClickHighlights` and `showsCursor` through `updateRecordingOptions` together.

- [x] **Step 3: Verify**
  - Run: `swift test --filter SelectionOverlayCompletionTests`
  - Expected: PASS.

### Task 3: Track Held Keyboard Hints

**Files:**
- Modify: `Sources/FrameApp/RecordingOverlayRenderer.swift`
- Test: `Tests/FrameAppTests/RecordingOverlayRendererTests.swift`

- [x] **Step 1: Write failing formatter and state tests**
  - Plain `a` with no modifier returns `A`.
  - `Command+Shift+P` returns `⌘⇧P`.
  - Space, Escape, Return, Tab, Delete, and arrow keys produce named labels without requiring a modifier.
  - Active state progresses from `⌘` to `⌘⇧` to `⌘⇧A`, removes `A` on key-up, and hides after all modifiers are released.
  - Run: `swift test --filter RecordingOverlayRendererTests`
  - Expected: FAIL for ordinary key display and missing active key state.

- [x] **Step 2: Implement active key state**
  - Keep Command, Option, Control, and Shift modifier state from `flagsChanged`.
  - Track `keyDown` and `keyUp` by key code so currently held keys remain visible until released.
  - Allow ordinary text keys, named non-text keys, function keys, and arrow keys.
  - Keep transient shortcut fallback hints only as a backup path.

- [x] **Step 3: Verify**
  - Run: `swift test --filter RecordingOverlayRendererTests`
  - Expected: PASS.

### Task 4: Prevent Shortcut Re-Entry

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Test: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [x] **Step 1: Write failing busy-state tests**
  - Assert `startCaptureFlowForTesting()` starts once and ignores a second call while selection is active.
  - Assert capture is ignored while recording is active.
  - Run: `swift test --filter AppDelegateRecordingTests`
  - Expected: FAIL because no busy-state testing hook exists and capture entry is not guarded.

- [x] **Step 2: Implement guard**
  - Add `SelectionOverlayController.isSelecting`.
  - Add `AppDelegate.isCaptureFlowBusy`.
  - At the start of `startCaptureFlow()`, beep and return when busy.
  - Add test hooks that count started selection flows without opening real overlay windows.

- [x] **Step 3: Verify**
  - Run: `swift test --filter AppDelegateRecordingTests`
  - Expected: PASS.

### Task 5: Full Verification And Packaging

**Files:**
- Modify docs only if verification exposes durable behavior that is not already covered by specs.

- [x] Run: `swift test`
- [x] Run: `swift build`
- [x] Run: `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh`
- [x] Replace local test app with stable signature:

```sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

- [x] Verify signature:

```sh
codesign -dv --verbose=2 ~/Applications/Frame.app
```

Expected: output contains `Authority=Frame Local Dev CLI`.
