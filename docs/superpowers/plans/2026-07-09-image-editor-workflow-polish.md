# Image Editor Workflow Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Frame's screenshot editor faster by adding a lightweight header style control, object-context double-click behavior, canvas tool shortcuts, and a configurable Save Current default.

**Architecture:** Keep `ImageAnnotationDocument` as the annotation source of truth. Add durable preference/state types in `FrameCore` and `SettingsStore`, then wire AppKit UI through `ImageWorkspacePanelController`, `ImageAnnotationCanvasView`, and focused tests in `ImageWorkspacePanelControllerTests`.

**Tech Stack:** Swift 6.1, AppKit `NSView`/`NSPanel`/`NSMenu`/`NSButton`, XCTest, existing Frame settings and workspace infrastructure.

---

### Task 1: Save Current Default Behavior

**Files:**
- Modify: `Sources/FrameCore/ImageWorkspaceState.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/SettingsWindowController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameCoreTests/FrameCoreTests.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`
- Test: `Tests/FrameAppTests/SettingsWindowControllerTests.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add failing FrameCore tests for an `ImageWorkspaceSaveCurrentBehavior` enum with `askEveryTime`, `replaceCurrent`, and `saveAsNew`.
- [x] Add failing SettingsStore tests proving the behavior defaults to `replaceCurrent`, persists all three values, and falls back to `replaceCurrent` for unknown storage.
- [x] Add failing workspace tests proving Save Current primary click obeys each configured behavior.
- [x] Implement `ImageWorkspaceSaveCurrentBehavior` in `FrameCore`.
- [x] Add SettingsStore read/write helpers and storage key.
- [x] Add Settings UI copy and a compact settings control under screenshot editing preferences.
- [x] Change Save Current primary click to execute the configured default; keep the existing menu for one-off Replace Current and Save As New actions.
- [x] Run `swift test --filter 'ZFrameCoreTests/testImageWorkspaceSaveCurrentBehavior|SettingsStoreTests|SettingsWindowControllerTests|ImageWorkspacePanelControllerTests/testWorkspaceSaveCurrent'`.

### Task 2: Canvas Tool Shortcuts And Object Context Switching

**Files:**
- Modify: `Sources/FrameApp/ImageAnnotationCanvasView.swift`
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [ ] Add failing tests for `V`, `R`, `O`, `L`, `A`, `B`, `T`, `H`, and `M` selecting the expected tool or shape/mosaic subtype when the canvas is focused.
- [x] Add failing tests for `[` and `]` stepping the current contextual size.
- [ ] Add failing tests proving tool shortcuts are ignored by the canvas while an inline text editor is active.
- [ ] Add failing tests for double-clicking text, arrow, rectangle, ellipse, line, brush, highlight, and mosaic objects entering the matching context while preserving selection.
- [x] Implement canvas key handling for tool shortcuts, scoped to the workspace responder chain.
- [x] Implement reusable context-switching helpers so mouse double-click and keyboard shortcuts share the same tool-selection path.
- [ ] Update tooltips or menu titles to include discoverable shortcuts where space allows.
- [ ] Run `swift test --filter ImageWorkspacePanelControllerTests`.

### Task 3: Lightweight Header Style Control

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/ImageAnnotationCanvasView.swift`
- Modify: `Sources/FrameApp/ImageAnnotationTextStyle.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add failing tests proving the header style control is present in temporary editor workspaces only for style contexts and absent from pinned image-only workspaces.
- [ ] Add failing tests proving header color selection updates the selected object style.
- [x] Add failing tests proving header color selection with no selected object updates the current tool default.
- [ ] Add failing tests proving header size changes update selected text font size, selected shape stroke width, and current tool defaults.
- [ ] Add failing tests proving the header style control reflects the selected object's color and size when selection changes.
- [x] Implement the header style control as a compact AppKit view with an icon-only tiled color palette and contextual size slider.
- [x] Wire header style callbacks into `ImageWorkspacePanelController` using existing document `setStyle` and `updateSelectedStyle` paths.
- [x] Replace the old Color and Thickness/Font Size toolbar menu buttons with the header style control.
- [x] Run `swift test --filter ImageWorkspacePanelControllerTests`.

### Task 4: Documentation And Manual Smoke Updates

**Files:**
- Modify: `DESIGN.md`
- Modify: `docs/development.md`
- Modify: `docs/superpowers/specs/2026-06-14-screenshot-editor-design.md`
- Modify: `docs/superpowers/specs/2026-07-09-image-editor-workflow-polish-design.md`

- [x] Update `DESIGN.md` to replace the old floating-property-bar and separate style menu rules with the new lightweight header style control rule.
- [x] Update `DESIGN.md` Save Current behavior to describe the configurable default and one-off menu actions.
- [x] Update `docs/development.md` manual smoke steps for the header style control, double-click context switching, tool shortcuts, and Save Current default settings.
- [x] Update the old screenshot editor spec so future readers see that this plan supersedes the original Save Current and toolbar-only style decisions.
- [x] Run `rg -n "Save Current|header style|shortcut|double-click|floating property" DESIGN.md docs/development.md docs/superpowers/specs/2026-06-14-screenshot-editor-design.md docs/superpowers/specs/2026-07-09-image-editor-workflow-polish-design.md` and inspect the output.

### Task 5: Follow-up Editor And Capture Polish

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/ImageAnnotationCanvasView.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [x] Replace the unsaved-close Replace Current / Save As New prompt with Save,
  Don't Save, and Cancel for direct Save Current defaults; retain explicit
  choices only for Ask Every Time.
- [x] Expand contextual text sizing through 96 pt and persist those values.
- [x] Use a fully opaque black image canvas backdrop.
- [x] Hide the selection HUD while a delayed screenshot countdown is active.
- [x] Persist the last confirmed screenshot selection for ten minutes. Restore
  region bounds directly, revalidate window IDs against the current global window
  list before reuse, and suppress hover preselection while it remains valid.
- [x] Add focused regression coverage for each behavior.

### Task 6: Full Verification And Local App Replacement

**Files:**
- No source files unless verification exposes a bug.

- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh`.
- [x] Replace the local app with:
  ```sh
  mkdir -p ~/Applications
  rm -rf ~/Applications/Frame.app
  ditto .build/app/Frame.app ~/Applications/Frame.app
  open ~/Applications/Frame.app
  ```
- [x] Verify `codesign -dv --verbose=2 ~/Applications/Frame.app` reports `Authority=Frame Local Dev CLI`.
- [x] Verify the running app process was restarted with `pgrep -ax Frame` and `ps -p <pid> -o pid,lstart,command`.

### Task 7: Workspace Toolbar Visual System

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Modify: `DESIGN.md`
- Modify: `docs/development.md`
- Modify: `CHANGELOG.md`

- [x] Add regression coverage for semantic toolbar groups, the wider mosaic
  option target, dark toolbar appearance, and the selected/disabled visual
  states.
- [x] Replace per-button symbol configuration with a shared primary-toolbar
  visual-metrics catalog and route dynamic mosaic symbols through it.
- [x] Separate History, Tools, Contextual Style, and Output with short
  low-contrast dividers while preserving trailing output placement.
- [x] Stabilize the toolbar material with dark backing, light primary glyphs,
  compact accent selection, and quiet hover feedback.
- [x] Update the durable design and manual smoke documentation.
- [x] Run the full test/build/package sequence and replace the local Frame app.

### Task 8: Attached Mosaic Split Control

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Modify: `DESIGN.md`
- Modify: `docs/development.md`
- Modify: `CHANGELOG.md`

- [x] Add regression coverage for one shared split-control frame, shared hover,
  selected state, and independent primary/menu targets.
- [x] Replace the floating Mosaic primary/menu pair with an attached split
  control and a quiet inner divider.
- [x] Update the durable design and manual smoke documentation.
- [x] Run the full test/build/package sequence and replace the local Frame app.
