# Local Capture History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local capture history so recent screenshots can be recovered after Quick Access is closed, with a polished preview-grid history window.

**Architecture:** `CaptureHistoryStore` owns Frame-owned cached files and JSON metadata under `Application Support/Frame/History`. `AppDelegate` records screenshots after successful capture, `StatusItemController` exposes the history entry, `CaptureHistoryWindowController` presents recent records in an AppKit collection-style preview grid, and `SettingsWindowController` exposes retention, capacity, enablement, and clear controls.

**Tech Stack:** Swift 6.1, AppKit, SwiftUI settings, `UserDefaults`, JSON index files, XCTest.

---

## Scope Guardrails

- Build a recovery cache, not a gallery.
- Do not add search, tags, favorites, OCR indexing, cloud sync, or auto-classification.
- Do not let history cleanup touch files explicitly saved by the user.
- Keep recording support as a metadata/type placeholder only; no recording capture implementation in this plan.

## File Structure

- Create `Sources/FrameApp/CaptureHistoryStore.swift`
  Owns `CaptureHistoryRecord`, `CaptureHistoryKind`, `CaptureHistoryRetention`, `CaptureHistorySizeLimit`, `CaptureHistoryConfiguration`, root paths, JSON index I/O, cached data writes, list/read/delete/clear, and cleanup.
- Create `Sources/FrameApp/CaptureHistoryWindowController.swift`
  Owns the AppKit history window, transparent titlebar, type segmented control, preview grid, hover HUD, empty state, and tile action callbacks.
- Modify `Sources/FrameApp/AppDelegate.swift`
  Instantiates the history store/window, records successful screenshots, opens history from menu, and maps history actions to existing preview/copy/save/delete behavior.
- Modify `Sources/FrameApp/StatusItemController.swift`
  Adds the Capture History menu item and callback.
- Modify `Sources/FrameApp/SettingsStore.swift`
  Persists history enabled, retention, and size limit values.
- Modify `Sources/FrameApp/SettingsWindowController.swift`
  Adds local history controls and clear action.
- Modify `Sources/FrameApp/AppStrings.swift`
  Adds localized strings for menu, settings, history title, filters, row actions, and record kinds.
- Modify `README.md`, `README_ZH.md`, and `docs/architecture.md`
  Documents the local-only history behavior and cache boundary.
- Add `Tests/FrameAppTests/CaptureHistoryStoreTests.swift`
  Covers store behavior and cleanup rules.
- Add `Tests/FrameAppTests/CaptureHistoryWindowControllerTests.swift`
  Covers window creation, collection-style preview presentation, absence of table columns, filtering, and tile action callbacks.
- Add `Tests/FrameAppTests/StatusItemControllerTests.swift`
  Covers the menu entry.
- Modify existing settings/string tests for new persisted settings and localization.

## Task 1: History Settings And Store

- [x] **Step 1: Write failing `SettingsStoreTests` for history defaults.**
  Expected default behavior: enabled, `.sevenDays`, `.twoGB`.

- [x] **Step 2: Run the focused tests and confirm RED.**
  Run: `swift test --filter 'SettingsStoreTests|CaptureHistoryStoreTests'`
  Expected before implementation: compile failure for missing history setting APIs and missing `CaptureHistoryStore`.

- [x] **Step 3: Add history settings types and accessors.**
  Add `CaptureHistoryRetention`, `CaptureHistorySizeLimit`, `CaptureHistoryConfiguration`, and `SettingsStore` accessors for enabled, retention, and size limit.

- [x] **Step 4: Write failing `CaptureHistoryStoreTests`.**
  Covered behaviors:
  - add screenshot stores metadata and PNG data
  - disabled history stores nothing
  - delete removes metadata and cached file
  - clear removes records and files
  - retention cleanup removes records older than the configured window
  - capacity cleanup removes oldest records while preserving newest
  - oversized single file is not stored

- [x] **Step 5: Implement `CaptureHistoryStore`.**
  Store files under `Application Support/Frame/History/Captures`, store metadata in `index.json`, write data atomically, and expose add/list/read/fileURL/delete/clear/cleanup.

- [x] **Step 6: Run focused verification.**
  Run: `swift test --filter 'SettingsStoreTests|CaptureHistoryStoreTests'`
  Result: 19 selected tests passed.

## Task 2: History Window

- [x] **Step 1: Write failing `CaptureHistoryWindowControllerTests`.**
  Covered behaviors:
  - showing the controller creates a visible window with records
  - the visible table exposes a thumbnail column
  - filter can show all, screenshots, and recordings
  - open/copy/save/delete row actions call configured handlers

- [x] **Step 2: Run focused tests and confirm RED.**
  Run: `swift test --filter CaptureHistoryWindowControllerTests`
  Expected before implementation: compile failure for missing controller and missing generic store add API.

- [x] **Step 3: Implement `CaptureHistoryWindowController`.**
  Add a native AppKit window with segmented filter, table rows, thumbnail column, created time, kind, dimensions, file size, and icon-only action buttons.

- [x] **Step 4: Add generic `CaptureHistoryStore.addCapture`.**
  This supports the recording placeholder type in tests and future recording data without adding recording capture.

- [x] **Step 5: Run focused verification.**
  Run: `swift test --filter CaptureHistoryWindowControllerTests`
  Result: 3 selected tests passed.

## Task 3: App Integration And Settings UI

- [x] **Step 1: Write failing menu/localization tests.**
  Add `StatusItemControllerTests.testMenuIncludesCaptureHistoryItem` and extend `AppStringsTests` for history strings.

- [x] **Step 2: Run focused tests and confirm RED.**
  Run: `swift test --filter 'AppStringsTests|StatusItemControllerTests'`
  Expected before implementation: compile failure for missing `onHistory` callback or missing strings.

- [x] **Step 3: Add the Capture History menu item.**
  `StatusItemController` now accepts `onHistory` and places Capture History before Settings.

- [x] **Step 4: Record screenshots after successful capture.**
  `AppDelegate` calls `captureHistoryStore.addScreenshot` after `CaptureService` succeeds and before Quick Access is restored/shown.

- [x] **Step 5: Wire history row actions.**
  Screenshot rows decode cached PNG data into `CapturedScreenshot` and reuse existing preview workspace, clipboard, and save flows. Delete removes the cached history record.

- [x] **Step 6: Add settings controls.**
  Settings now include local history enablement, retention picker, size limit picker, and clear history action.

- [x] **Step 7: Run integration-focused verification.**
  Run: `swift test --filter 'ScreenshotDragItemProviderTests|SettingsWindowControllerTests|CaptureHistoryWindowControllerTests|StatusItemControllerTests|AppStringsTests|CaptureHistoryStoreTests|SettingsStoreTests'`
  Result: 41 selected tests passed.

## Task 4: Documentation And Full Verification

- [x] **Step 1: Update documentation.**
  Update `README.md`, `README_ZH.md`, and `docs/architecture.md` to describe local history, privacy boundary, retention, and cache ownership.

- [x] **Step 2: Run full tests.**
  Run: `swift test`
  Result: 98 XCTest tests and 31 Swift Testing tests passed.

- [x] **Step 3: Run build.**
  Run: `swift build`
  Result: build passed.

- [x] **Step 4: Run package script.**
  Run: `scripts/package-app.sh`
  Result: packaged `.build/app/Frame.app`; ad-hoc signing succeeded.

## Plan Self-Review

- Spec coverage: covered local cache, 7-day default, 2 GB default, oversized rejection, capacity cleanup, Quick Access independence, menu entry, history window, settings, type filter, documentation, and tests.
- Scope check: no search, tags, favorites, OCR indexing, cloud, or recording capture was added.
- Type consistency: `CaptureHistoryStore`, `CaptureHistoryRecord`, `CaptureHistoryKind`, `CaptureHistoryRetention`, `CaptureHistorySizeLimit`, `CaptureHistoryWindowController`, and `CaptureHistoryFilter` are used consistently across implementation and tests.

## Task 5: Redesign History Window As Preview Grid

**Files:**
- Modify: `Sources/FrameApp/CaptureHistoryWindowController.swift`
- Modify: `Tests/FrameAppTests/CaptureHistoryWindowControllerTests.swift`
- Modify if needed: `Sources/FrameApp/AppStrings.swift`
- Modify if needed: `Tests/FrameAppTests/AppStringsTests.swift`
- Modify if needed: `DESIGN.md`

- [x] **Step 1: Replace table-oriented tests with preview-grid tests.**

  Update `Tests/FrameAppTests/CaptureHistoryWindowControllerTests.swift` so the first test no longer expects a thumbnail table column. It should verify a visible native window, loaded records, preview-grid presentation, and no table-column identifiers.

  ```swift
  @MainActor
  func testShowCreatesWindowWithPreviewGrid() throws {
      _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
      let controller = CaptureHistoryWindowController(store: store)

      controller.show(strings: AppStrings(language: .en))
      defer { controller.close() }

      XCTAssertTrue(controller.isWindowVisible)
      XCTAssertEqual(controller.visibleRecords().count, 1)
      XCTAssertEqual(controller.selectedFilter, .all)
      XCTAssertEqual(controller.visibleColumnIdentifiers(), [])
      XCTAssertEqual(controller.visibleTileCount(), 1)
      XCTAssertTrue(controller.usesTransparentTitlebar)
  }
  ```

- [x] **Step 2: Add hover-HUD component tests.**

  Add a test that verifies tile actions are hidden by default and become visible when the controller exposes the hovered state for a record. Keep this at component boundary so it does not require full mouse-event e2e.

  ```swift
  @MainActor
  func testTileActionsAreVisibleOnlyWhenHovered() throws {
      let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
      let controller = CaptureHistoryWindowController(store: store)

      controller.show(strings: AppStrings(language: .en))
      defer { controller.close() }

      XCTAssertFalse(controller.areActionsVisible(for: record))
      controller.setActionsVisible(true, for: record)
      XCTAssertTrue(controller.areActionsVisible(for: record))
      controller.setActionsVisible(false, for: record)
      XCTAssertFalse(controller.areActionsVisible(for: record))
  }
  ```

- [x] **Step 3: Run the focused tests and confirm RED.**

  Run:

  ```sh
  swift test --filter CaptureHistoryWindowControllerTests
  ```

  Expected before implementation: compile failures for `visibleTileCount`, `usesTransparentTitlebar`, `areActionsVisible(for:)`, and `setActionsVisible(_:for:)`, plus old table UI assertions removed.

- [x] **Step 4: Convert the history window chrome to transparent native macOS style.**

  In `CaptureHistoryWindowController.show(strings:)`, keep a normal `NSWindow` but configure titlebar integration:

  ```swift
  window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
  window.titleVisibility = .hidden
  window.titlebarAppearsTransparent = true
  window.isMovableByWindowBackground = true
  window.backgroundColor = .clear
  window.isOpaque = false
  ```

  The implementation must preserve system traffic-light controls and normal window shadow/resizing behavior.

- [x] **Step 5: Replace `NSTableView` with collection-style preview content.**

  In `CaptureHistoryWindowController`, remove `NSTableViewDataSource` and `NSTableViewDelegate` conformance. Replace `tableView` storage with a scroll view containing a grid view, and expose compatibility helpers for tests:

  ```swift
  private var gridView: NSStackView?
  private var tileViewsByRecordID: [UUID: CaptureHistoryTileView] = [:]

  func visibleTileCount() -> Int {
      tileViewsByRecordID.count
  }

  func visibleColumnIdentifiers() -> [NSUserInterfaceItemIdentifier] {
      []
  }
  ```

  The grid should recompute columns from available width, keep stable tile sizing, and fall back to one column at narrow window widths.

- [x] **Step 6: Implement preview tiles aligned with Quick Access.**

  Add a private `CaptureHistoryTileView` in `CaptureHistoryWindowController.swift`. It should own the preview image, metadata label, and hover HUD. Use rounded preview image styling close to Quick Access:

  ```swift
  imageView.layer?.cornerRadius = 12
  imageView.layer?.cornerCurve = .continuous
  imageView.layer?.masksToBounds = true
  imageView.layer?.borderWidth = 0.5
  imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
  ```

  The HUD buttons are icon-only for save, copy, open preview, and delete. Each button must have `toolTip`, accessibility label, and record identifier routing.

- [x] **Step 7: Wire tile hover and actions.**

  Add a tracking area to `CaptureHistoryTileView` and toggle HUD alpha on mouse enter/exit. Add test-facing methods to the controller:

  ```swift
  func areActionsVisible(for record: CaptureHistoryRecord) -> Bool {
      tileViewsByRecordID[record.id]?.areActionsVisible == true
  }

  func setActionsVisible(_ isVisible: Bool, for record: CaptureHistoryRecord) {
      tileViewsByRecordID[record.id]?.setActionsVisible(isVisible)
  }
  ```

  Existing `openRecord`, `copyRecord`, `saveRecord`, and `deleteRecord` remain the action boundary. Deleting a record reloads the grid.

- [x] **Step 8: Add empty state and metadata formatting.**

  If `records` is empty after filtering, show a centered native text label inside the visual-effect content area. Tile metadata should be one compact line using existing strings where possible:

  ```swift
  private func metadataText(for record: CaptureHistoryRecord) -> String {
      let size = ByteCountFormatter.string(fromByteCount: Int64(record.byteSize), countStyle: .file)
      return "\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(record.pixelWidth) x \(record.pixelHeight) • \(size)"
  }
  ```

  Add localized empty-state strings only if the implementation needs visible text beyond the existing title/filter/action strings.

- [x] **Step 9: Run focused verification.**

  Run:

  ```sh
  swift test --filter CaptureHistoryWindowControllerTests
  ```

  Expected: all `CaptureHistoryWindowControllerTests` pass.

- [x] **Step 10: Run integration verification for touched surfaces.**

  Run:

  ```sh
  swift test --filter 'CaptureHistoryWindowControllerTests|StatusItemControllerTests|AppStringsTests'
  ```

  Expected: selected tests pass.

- [x] **Step 11: Update durable design documentation if the implementation introduces reusable visual rules.**

  If the final window chrome or tile HUD adds rules not already covered by `DESIGN.md`, update the `HUD And Workspace Chrome` or `Quick Access` sections. Do not duplicate the spec; document only durable visual principles.

- [x] **Step 12: Run full verification before handoff.**

  Run:

  ```sh
  swift test
  swift build
  scripts/package-app.sh
  ```

  Expected: tests pass, build passes, and `.build/app/Frame.app` packages successfully.

  Result:
  - `swift test --filter CaptureHistoryWindowControllerTests`: 4 selected tests passed.
  - `swift test --filter 'CaptureHistoryWindowControllerTests|StatusItemControllerTests|AppStringsTests'`: 11 selected tests passed.
  - `swift test --skip HUDSizeControlTests`: 92 XCTest tests and 31 Swift Testing tests passed.
  - `swift test --filter HUDSizeControlTests`: 11 selected tests passed.
  - `swift test`: hit signal 11 when `HUDSizeControlTests` runs before `ImageWorkspacePanelControllerTests/testTemporaryWorkspaceAutomaticallyLoadsOCRTextOverlay`. The same failure reproduces without the capture-history tests and the affected suites pass independently, so it is tracked as an existing AppKit test-order issue rather than a capture-history regression.
  - `swift build`: build passed.
  - `scripts/package-app.sh`: packaged `.build/app/Frame.app`; ad-hoc signing succeeded.

## Task 5 Plan Self-Review

- Spec coverage: covers adaptive preview grid, transparent titlebar, traffic-light preservation, Quick Access-aligned tiles, hover HUD actions, compact metadata, empty state, filter retention, no table UI, and no search/grouping/favorites.
- Scope check: keeps the feature in AppKit and does not add recording capture, search, grouping, tags, favorites, or cloud behavior.
- Type consistency: uses existing `CaptureHistoryWindowController`, `CaptureHistoryRecord`, `CaptureHistoryFilter`, and existing action boundary methods; new test helpers are `visibleTileCount`, `usesTransparentTitlebar`, `areActionsVisible(for:)`, and `setActionsVisible(_:for:)`.
