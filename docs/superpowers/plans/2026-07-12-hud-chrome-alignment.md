# HUD Chrome Alignment Implementation Plan

**Goal:** Align screenshot, video, and Quick Access control surfaces around one
stable deep-glass visual language without altering media content or workflows.

### Task 1: Shared Chrome Boundary

**Files:**
- Add: `Sources/FrameApp/FrameHUDChrome.swift`
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add coverage for shared dark appearance and stable surface backing.
- [x] Implement `FrameHUDChrome` with surface, icon, border, hover, and chip
  presentation values.
- [x] Replace Image Workspace's local dark-chrome palette with the shared
  boundary.

### Task 2: Video Chrome

**Files:**
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
- Modify: `Sources/FrameApp/VideoEditorBarView.swift`
- Test: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`
- Test: `Tests/FrameAppTests/VideoEditorBarViewTests.swift`

- [x] Add coverage for deep video header/editor surfaces and compact output
  controls.
- [x] Apply shared chrome to the Video Preview header and trailing output group.
- [x] Apply shared deep editor chrome, light transport/text tints, and dark speed
  token treatment to the Video Editor Bar.

### Task 3: Quick Access Chrome

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Test: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`

- [x] Add coverage for dark Quick Access overlays, accessory chips, placeholders,
  and hover preview chrome while preserving media content views.
- [x] Apply shared chrome to Quick Access controls and accessory surfaces.

### Task 4: Documentation And Delivery

**Files:**
- Modify: `DESIGN.md`
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`
- Modify: `CHANGELOG.md`

- [x] Document surface-specific deep-glass rules and manual smoke coverage.
- [x] Run `swift test`, `swift build`, and stable-signing package verification.
- [x] Replace `~/Applications/Frame.app` and verify signing plus the running
  process.
