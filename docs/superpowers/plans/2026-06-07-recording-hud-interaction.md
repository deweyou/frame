# Recording HUD Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine recording HUD flow so setup appears centered with a primary start action, and active recording prioritizes stop, restart, and delete.

**Architecture:** Keep setup HUD behavior in `SelectionOverlayWindow`, because it belongs to the selection overlay state. Keep active recording controls in `ActiveRecordingHUDPanelController`, because it owns the always-on-top recording panel during capture. `AppDelegate` remains the coordinator for stop/restart/delete session behavior.

**Tech Stack:** Swift, AppKit, XCTest, ScreenCaptureKit-backed recording service.

---

### Task 1: Center Recording Setup HUD

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that enter recording setup and assert the HUD is centered on the selected rect, and that `开始录制` is exposed as the primary action.

- [ ] **Step 2: Run targeted tests**

Run:

```bash
swift test --filter SelectionOverlayCompletionTests/testRecordingSetup
```

Expected: fail before implementation.

- [ ] **Step 3: Implement setup layout**

Use setup-specific placement in `positionHUD()` and expose testing hooks for setup HUD frame and primary start styling.

- [ ] **Step 4: Verify**

Run the same targeted tests. Expected: pass.

### Task 2: Active Recording HUD Controls

**Files:**
- Modify: `Sources/FrameApp/ActiveRecordingHUDPanelController.swift`
- Test: `Tests/FrameAppTests/ActiveRecordingHUDPanelControllerTests.swift`

- [ ] **Step 1: Write failing tests**

Assert active HUD button labels are `停止录制`, `重新开始`, and `删除录制`, with stop tinted red and no pause/resume.

- [ ] **Step 2: Run targeted tests**

Run:

```bash
swift test --filter ActiveRecordingHUDPanelControllerTests
```

Expected: fail before implementation.

- [ ] **Step 3: Implement active HUD actions**

Replace pause/resume rendering with stop/restart/delete rendering. Keep stop red and keep elapsed time red.

- [ ] **Step 4: Verify**

Run the same targeted tests. Expected: pass.

### Task 3: AppDelegate Restart And Delete

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Test: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [ ] **Step 1: Write failing tests**

Cover restart and delete through injected recording service spies.

- [ ] **Step 2: Implement coordinator behavior**

Restart cancels or stops current session without Quick Access, then starts the same selection/options again. Delete cancels current recording and exits without Quick Access. Delete uses HUD-level confirmation before invoking AppDelegate.

- [ ] **Step 3: Verify**

Run:

```bash
swift test --filter AppDelegateRecordingTests
```

Expected: pass.

### Task 4: Full Verification And Local Replacement

**Files:**
- No new files.

- [ ] **Step 1: Run full tests**

```bash
swift test
```

- [ ] **Step 2: Run build**

```bash
swift build
```

- [ ] **Step 3: Package and replace local app**

```bash
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
xattr -cr ~/Applications/Frame.app
open -n ~/Applications/Frame.app
```
