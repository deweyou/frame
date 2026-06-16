# Screenshot Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build object-based screenshot annotation editing in the existing Image Workspace.

**Architecture:** Put deterministic annotation state and undo/redo in `FrameCore`; keep drawing, event handling, dropdown menus, rendering, clipboard, and file output in `FrameApp`. `ImageWorkspacePanelController` remains the workspace owner but delegates canvas behavior and final composition to focused files.

**Tech Stack:** Swift 6.1, AppKit `NSView`/`NSPanel`/`NSMenu`, CoreGraphics drawing, XCTest.

---

### Task 1: Core Annotation Model

**Files:**
- Create: `Sources/FrameCore/ImageAnnotationDocument.swift`
- Modify: `Sources/FrameCore/ImageWorkspaceState.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [x] Add failing tests for annotation style defaults, document add/select/move/resize/delete, hit testing, undo, redo, and tool option changes.
- [x] Implement `ImageAnnotationColor`, `ImageAnnotationStyle`, `ImageAnnotationElement`, `ImageAnnotationDocument`, shape kinds, mosaic modes, and editing options.
- [x] Keep existing workspace close-policy behavior intact.
- [x] Run `swift test --filter ZFrameCoreTests/testImageAnnotation`.

### Task 2: Renderer

**Files:**
- Create: `Sources/FrameApp/ImageAnnotationRenderer.swift`
- Modify: `Sources/FrameApp/CaptureService.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add failing tests that a rendered rectangle/text/mosaic output changes PNG pixels and preserves the screenshot ID when requested.
- [x] Add an explicit `CapturedScreenshot` initializer with injectable ID.
- [x] Implement AppKit rendering for shapes, brush, highlight, text, and mosaic.
- [x] Run renderer-specific tests.

### Task 3: Editing Canvas

**Files:**
- Create: `Sources/FrameApp/ImageAnnotationCanvasView.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add failing component tests for shape creation, object selection/move/resize/delete, undo/redo callbacks, mosaic mode creation, and text re-edit.
- [x] Implement image-coordinate mapping, drawing, draft creation, selection handles, move, bottom-right resize, delete key, undo/redo key handling, and inline text editing.
- [x] Run `swift test --filter ImageWorkspacePanelControllerTests`.

### Task 4: Workspace Toolbar And Output Wiring

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`

- [x] Add failing tests that editing buttons are enabled, tool dropdown menus contain expected options, Save Current updates the workspace current screenshot without external save, Copy/Download use rendered edited screenshots, and pinned windows stay image-only.
- [x] Change workspace output closures to accept the current rendered screenshot.
- [x] Add toolbar select, undo, redo, tool dropdowns, Save Current, Copy, and Download actions.
- [x] Wire localized labels through `AppStrings`.
- [x] Run focused AppKit tests.

### Task 5: Docs, README, Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `DESIGN.md`
- Modify: `docs/development.md`
- Modify: `docs/testing.md`
- Modify: `README.md`
- Modify: `README_ZH.md`

- [x] Update product and architecture docs for screenshot editing.
- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `scripts/package-app.sh`.
- [ ] For GUI handoff, ask whether to replace the local test app unless replacement has already been done in the same turn.

### Task 6: Split Tool Buttons And Deferred Rectangular Mosaic

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/ImageAnnotationCanvasView.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Modify: `docs/superpowers/specs/2026-06-14-screenshot-editor-design.md`

- [ ] Add failing tests that clicking a tool's main button selects the tool
      without opening its option menu, and that option menus remain available
      from a separate chevron button.
- [ ] Add a failing canvas test that rectangular mosaic drag preview does not
      pixelate until mouse-up commits the object.
- [ ] Implement compact split controls for tools with options; keep Select as a
      single button.
- [ ] Change rectangular mosaic draft drawing to a lightweight dashed/outlined
      selection rectangle while preserving final rendered mosaic output.
- [ ] Run `swift test --filter ImageWorkspacePanelControllerTests`.
