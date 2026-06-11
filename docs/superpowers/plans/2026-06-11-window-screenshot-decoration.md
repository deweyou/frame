# Window Screenshot Decoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add selectable window screenshot decoration styles with `Soft Backdrop` as the default.

**Architecture:** Add a small AppKit/CoreGraphics compositor behind `WindowScreenshotDecorator`, persist `WindowScreenshotDecorationStyle` in `SettingsStore`, expose it in the SwiftUI settings form, and apply it only inside the `.window` capture branch. Existing screenshot output surfaces continue consuming `CapturedScreenshot`.

**Tech Stack:** Swift, AppKit, CoreGraphics, SwiftUI Settings, XCTest.

---

### Task 1: Settings Model And Strings

**Files:**
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Modify: `Sources/FrameApp/SettingsWindowController.swift`
- Modify: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [ ] Add failing tests for default, persisted, and invalid window screenshot decoration style.
- [ ] Add `WindowScreenshotDecorationStyle` with `softBackdrop`, `canvasGlow`, and `transparentShadow`.
- [ ] Add localized settings label and display names.
- [ ] Add a General settings picker bound to `SettingsStore`.

### Task 2: Screenshot Decorator

**Files:**
- Create: `Sources/FrameApp/WindowScreenshotDecorator.swift`
- Modify: `Tests/FrameAppTests/CaptureServiceTests.swift`

- [ ] Add failing tests with a synthetic image proving decorated output is larger than source.
- [ ] Add failing tests proving `transparentShadow` keeps transparent corners.
- [ ] Add failing tests proving all styles produce identical canvas geometry for the same source window while keeping distinct background pixels where applicable.
- [ ] Implement the compositor with shared deterministic padding, corner radius, and window rect, plus style-specific background and shadow parameters.

### Task 3: Capture Integration

**Files:**
- Modify: `Sources/FrameApp/CaptureService.swift`
- Modify: `docs/architecture.md`
- Modify: `README.md`
- Modify: `README_ZH.md`

- [ ] Inject the selected style into `CaptureService` through a closure defaulting to `SettingsStore.windowScreenshotDecorationStyle`.
- [ ] Apply decoration only in `captureWindow(id:rect:)`.
- [ ] Keep region and fullscreen capture paths unchanged.
- [ ] Update product docs/readmes for the user-facing window screenshot style setting.

### Task 4: Verification

**Commands:**
- `swift test --filter 'SettingsStoreTests|CaptureServiceTests'`
- `swift test`
- `swift build`
- `scripts/package-app.sh`

- [ ] Run targeted tests after implementation.
- [ ] Run full verification commands.
- [ ] For GUI-facing settings changes, ask whether to replace the local test app unless replacement has already been completed.
