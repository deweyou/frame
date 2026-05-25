# Window Screenshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic hover-based window screenshot selection while preserving the current region screenshot flow and last-selection memory.

**Architecture:** Put deterministic hover/session rules in `FrameCore`, keep CoreGraphics window-list parsing in a narrow `FrameApp` adapter, and let `SelectionOverlayController` coordinate one shared hover session across per-screen overlay windows. Overlay views display either the editable region or the active window candidate; confirmation returns the active rectangle through the existing capture pipeline.

**Tech Stack:** Swift 6.1, AppKit, CoreGraphics, Swift Testing, existing `FrameCore` and `FrameApp` package targets.

---

## File Structure

- Create `Sources/FrameCore/WindowHoverSelection.swift` for the deterministic automatic-hover state machine.
- Create `Sources/FrameCore/WindowCandidate.swift` for lightweight candidate identity and bounds shared by tests and AppKit adapters.
- Create `Sources/FrameApp/WindowCandidateProvider.swift` for `CGWindowListCopyWindowInfo` parsing, filtering, and coordinate conversion.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift` to add red/green tests for hover timing, movement, HUD exclusion, candidate reuse, and region-lock behavior.
- Modify `Sources/FrameApp/SelectionOverlayController.swift` to own the shared hover selector and provider, activate the overlay containing the candidate, and keep key confirmation routed through the active candidate/region.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift` to report mouse movement, suppress hover over HUD, draw window candidates, disable automatic hover after region editing begins, and confirm the candidate rectangle.
- Modify `docs/architecture.md` after implementation to record the durable window-selection boundary.

## Task 1: Core Window Hover State

**Files:**
- Create: `Sources/FrameCore/WindowCandidate.swift`
- Create: `Sources/FrameCore/WindowHoverSelection.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [ ] **Step 1: Write failing tests for hover timing and cancellation**

Add these tests to `Tests/FrameCoreTests/FrameCoreTests.swift`:

```swift
    @Test
    func testWindowHoverActivatesAfterDelayForSameCandidate() {
        let candidate = WindowCandidate(
            id: 42,
            ownerProcessID: 100,
            bounds: CGRect(x: 10, y: 20, width: 320, height: 240)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 40, y: 60),
            isOverHUD: false,
            timestamp: 1.0
        ) == nil)
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 42, y: 61),
            isOverHUD: false,
            timestamp: 1.34
        ) == nil)
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 42, y: 61),
            isOverHUD: false,
            timestamp: 1.35
        ) == candidate)
    }

    @Test
    func testWindowHoverCancelsWhenMouseEntersHUD() {
        let candidate = WindowCandidate(
            id: 8,
            ownerProcessID: 100,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 120)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        _ = selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 10, y: 10),
            isOverHUD: false,
            timestamp: 2.0
        )
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 10, y: 10),
            isOverHUD: true,
            timestamp: 2.4
        ) == nil)
        #expect(selector.activeCandidate == nil)
    }
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter FrameCoreTests/testWindowHoverActivatesAfterDelayForSameCandidate
swift test --filter FrameCoreTests/testWindowHoverCancelsWhenMouseEntersHUD
```

Expected: both fail to compile with missing `WindowCandidate` or `WindowHoverSelection`.

- [ ] **Step 3: Add minimal candidate and selector implementation**

Create `Sources/FrameCore/WindowCandidate.swift`:

```swift
import CoreGraphics
import Foundation

public struct WindowCandidate: Equatable {
    public let id: UInt32
    public let ownerProcessID: Int32
    public let bounds: CGRect

    public init(id: UInt32, ownerProcessID: Int32, bounds: CGRect) {
        self.id = id
        self.ownerProcessID = ownerProcessID
        self.bounds = bounds
    }
}
```

Create `Sources/FrameCore/WindowHoverSelection.swift`:

```swift
import CoreGraphics
import Foundation

public struct WindowHoverSelection {
    public let activationDelay: TimeInterval
    public let movementTolerance: CGFloat
    private var pendingCandidate: WindowCandidate?
    private var pendingStartedAt: TimeInterval?
    private var pendingMouseLocation: CGPoint?
    public private(set) var activeCandidate: WindowCandidate?
    public private(set) var isRegionLockedForSession = false

    public init(activationDelay: TimeInterval = 0.35, movementTolerance: CGFloat = 6) {
        self.activationDelay = activationDelay
        self.movementTolerance = movementTolerance
    }

    public mutating func update(
        candidate: WindowCandidate?,
        mouseLocation: CGPoint,
        isOverHUD: Bool,
        timestamp: TimeInterval
    ) -> WindowCandidate? {
        guard !isRegionLockedForSession, !isOverHUD, let candidate else {
            cancelPendingCandidate()
            activeCandidate = nil
            return nil
        }

        if activeCandidate == candidate, candidate.bounds.contains(mouseLocation) {
            return activeCandidate
        }

        if pendingCandidate != candidate || hasMovedPastTolerance(from: mouseLocation) {
            pendingCandidate = candidate
            pendingStartedAt = timestamp
            pendingMouseLocation = mouseLocation
            activeCandidate = nil
            return nil
        }

        guard let pendingStartedAt, timestamp - pendingStartedAt >= activationDelay else {
            return nil
        }

        activeCandidate = candidate
        return candidate
    }

    public mutating func lockRegionEditingForSession() {
        isRegionLockedForSession = true
        cancelPendingCandidate()
        activeCandidate = nil
    }

    public mutating func reset() {
        isRegionLockedForSession = false
        cancelPendingCandidate()
        activeCandidate = nil
    }

    private mutating func cancelPendingCandidate() {
        pendingCandidate = nil
        pendingStartedAt = nil
        pendingMouseLocation = nil
    }

    private func hasMovedPastTolerance(from mouseLocation: CGPoint) -> Bool {
        guard let pendingMouseLocation else {
            return false
        }

        return hypot(mouseLocation.x - pendingMouseLocation.x, mouseLocation.y - pendingMouseLocation.y) > movementTolerance
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter FrameCoreTests/testWindowHover
```

Expected: tests pass.

- [ ] **Step 5: Write failing tests for movement restart and region lock**

Add:

```swift
    @Test
    func testWindowHoverRestartsForDifferentCandidate() {
        let first = WindowCandidate(id: 1, ownerProcessID: 100, bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let second = WindowCandidate(id: 2, ownerProcessID: 101, bounds: CGRect(x: 220, y: 0, width: 200, height: 200))
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        _ = selector.update(candidate: first, mouseLocation: CGPoint(x: 20, y: 20), isOverHUD: false, timestamp: 1.0)
        #expect(selector.update(candidate: second, mouseLocation: CGPoint(x: 230, y: 20), isOverHUD: false, timestamp: 1.4) == nil)
        #expect(selector.update(candidate: second, mouseLocation: CGPoint(x: 230, y: 20), isOverHUD: false, timestamp: 1.75) == second)
    }

    @Test
    func testRegionEditingDisablesAutomaticHoverForSession() {
        let candidate = WindowCandidate(id: 3, ownerProcessID: 100, bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        selector.lockRegionEditingForSession()

        #expect(selector.update(candidate: candidate, mouseLocation: CGPoint(x: 20, y: 20), isOverHUD: false, timestamp: 1.0) == nil)
        #expect(selector.update(candidate: candidate, mouseLocation: CGPoint(x: 20, y: 20), isOverHUD: false, timestamp: 2.0) == nil)
        #expect(selector.isRegionLockedForSession)
    }
```

- [ ] **Step 6: Run the new tests and verify they pass**

Run:

```bash
swift test --filter FrameCoreTests/testWindowHoverRestartsForDifferentCandidate
swift test --filter FrameCoreTests/testRegionEditingDisablesAutomaticHoverForSession
```

Expected: both pass with the implementation from Step 3.

## Task 2: Window Candidate Provider

**Files:**
- Create: `Sources/FrameApp/WindowCandidateProvider.swift`
- Modify: `Sources/FrameApp/ActiveScreenResolver.swift`

- [ ] **Step 1: Add provider implementation behind a narrow AppKit boundary**

Create `Sources/FrameApp/WindowCandidateProvider.swift`:

```swift
import AppKit
import CoreGraphics
import FrameCore

@MainActor
struct WindowCandidateProvider {
    private let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
    private let minimumCandidateSize = CGSize(width: 48, height: 48)

    func candidate(at point: CGPoint) -> WindowCandidate? {
        windowInfos()
            .compactMap(candidate(from:))
            .first { $0.bounds.contains(point) }
    }

    private func windowInfos() -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        return windowList
    }

    private func candidate(from windowInfo: [String: Any]) -> WindowCandidate? {
        guard let ownerProcessID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              ownerProcessID != currentProcessID,
              let layer = windowInfo[kCGWindowLayer as String] as? Int,
              layer == 0,
              let windowID = windowInfo[kCGWindowNumber as String] as? UInt32,
              let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
              alpha > 0,
              let sharingState = windowInfo[kCGWindowSharingState as String] as? Int,
              sharingState != 0,
              let rect = Self.cocoaRect(forWindowInfo: windowInfo),
              rect.width >= minimumCandidateSize.width,
              rect.height >= minimumCandidateSize.height else {
            return nil
        }

        return WindowCandidate(id: windowID, ownerProcessID: ownerProcessID, bounds: rect)
    }

    static func cocoaRect(forWindowInfo windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        return cocoaRect(fromQuartzWindowRect: CGRect(x: x, y: y, width: width, height: height))
    }

    static func cocoaRect(fromQuartzWindowRect quartzRect: CGRect) -> CGRect {
        let screenUnion = NSScreen.screens.reduce(CGRect.null) { union, screen in
            union.union(screen.frame)
        }

        guard !screenUnion.isNull else {
            return quartzRect
        }

        return CGRect(
            x: quartzRect.minX,
            y: screenUnion.maxY - quartzRect.maxY + screenUnion.minY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }
}
```

- [ ] **Step 2: Reuse coordinate conversion in active screen resolver**

In `Sources/FrameApp/ActiveScreenResolver.swift`, replace `cocoaRect(forWindowInfo:)` and `cocoaRect(fromQuartzWindowRect:)` call sites with `WindowCandidateProvider.cocoaRect(forWindowInfo:)`, then delete the duplicated private conversion functions.

The frontmost window mapping should become:

```swift
        if let frontmostProcessID,
           let frontmostWindow = layerZeroWindows
               .first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == frontmostProcessID }),
           let rect = WindowCandidateProvider.cocoaRect(forWindowInfo: frontmostWindow) {
            return rect
        }

        return layerZeroWindows.compactMap(WindowCandidateProvider.cocoaRect(forWindowInfo:)).first
```

- [ ] **Step 3: Build to verify AppKit adapter compiles**

Run:

```bash
swift build
```

Expected: build succeeds.

## Task 3: Overlay Candidate Display And Confirmation

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`

- [ ] **Step 1: Extend window wrapper API for window candidates**

In `SelectionOverlayWindow`, add methods and properties that delegate to the view:

```swift
    var activeGlobalRect: CGRect? {
        overlayView.activeGlobalRect
    }

    func showWindowCandidate(_ candidate: WindowCandidate?) {
        overlayView.showWindowCandidate(candidate)
    }

    func contains(globalPoint: CGPoint) -> Bool {
        window.frame.contains(globalPoint)
    }
```

- [ ] **Step 2: Add candidate state to `SelectionOverlayView`**

Add properties:

```swift
    private var windowCandidate: WindowCandidate?
    private var isRegionLockedForSession = false
```

Add active rectangle accessors:

```swift
    var activeGlobalRect: CGRect? {
        if let windowCandidate {
            return windowCandidate.bounds
        }

        return selectedGlobalRect
    }

    func showWindowCandidate(_ candidate: WindowCandidate?) {
        windowCandidate = candidate
        updateMetrics()
        needsDisplay = true
    }
```

- [ ] **Step 3: Draw candidate rectangles without mutating the saved region**

Change `draw(_:)` to compute a display rectangle:

```swift
        let displayRect = windowCandidate.flatMap { localRect(fromGlobalRect: $0.bounds) } ?? selectionRect

        guard let displayRect else {
            NSColor.black.withAlphaComponent(0.26).setFill()
            bounds.fill()
            return
        }

        drawDimmedBackdrop(excluding: displayRect)
        drawSelectionChrome(displayRect)
```

Change `updateMetrics()` and `positionHUD()` so labels and HUD position use the candidate local rect when present:

```swift
    private var displayedLocalRect: CGRect? {
        windowCandidate.flatMap { localRect(fromGlobalRect: $0.bounds) } ?? selectionRect
    }
```

Use `displayedLocalRect` wherever those methods currently read `selectionRect` for HUD visibility, size, and placement.

- [ ] **Step 4: Confirm candidate before region**

Change `confirmSelection()` to:

```swift
    private func confirmSelection() {
        if let windowCandidate,
           SelectionGeometry.isValidSelection(windowCandidate.bounds) {
            completeSelection(with: windowCandidate.bounds)
            return
        }

        guard let selectionRect,
              SelectionGeometry.isValidSelection(selectionRect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: globalRect(fromLocalRect: selectionRect))
    }
```

- [ ] **Step 5: Build to verify overlay rendering compiles**

Run:

```bash
swift build
```

Expected: build succeeds.

## Task 4: Wire Automatic Hover Coordination

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`

- [ ] **Step 1: Add controller-owned hover selector and provider**

Add properties to `SelectionOverlayController`:

```swift
    private var hoverSelection = WindowHoverSelection()
    private let windowCandidateProvider = WindowCandidateProvider()
```

Reset selector at the start of `startSelection` after `self.completion = completion`:

```swift
        hoverSelection.reset()
```

- [ ] **Step 2: Pass hover callbacks into each overlay window**

Update `SelectionOverlayWindow` initializer and view initializer to accept:

```swift
        onMouseMoved: @escaping (CGPoint, Bool) -> Void,
        onRegionEditingStarted: @escaping () -> Void,
```

When constructing windows in `SelectionOverlayController`, pass:

```swift
                onMouseMoved: { [weak self] globalPoint, isOverHUD in
                    self?.updateWindowHover(globalPoint: globalPoint, isOverHUD: isOverHUD)
                },
                onRegionEditingStarted: { [weak self] in
                    self?.lockRegionEditingForSession()
                },
```

- [ ] **Step 3: Implement shared hover update in the controller**

Add:

```swift
    private func updateWindowHover(globalPoint: CGPoint, isOverHUD: Bool) {
        let candidate = isOverHUD ? nil : windowCandidateProvider.candidate(at: globalPoint)
        let activeCandidate = hoverSelection.update(
            candidate: candidate,
            mouseLocation: globalPoint,
            isOverHUD: isOverHUD,
            timestamp: ProcessInfo.processInfo.systemUptime
        )

        for window in overlayWindows {
            window.showWindowCandidate(activeCandidate)
        }

        guard let activeCandidate,
              let activeWindow = overlayWindows.first(where: { $0.contains(globalPoint: activeCandidate.bounds.origin) || $0.contains(globalPoint: globalPoint) }) else {
            return
        }

        activate(activeWindow)
    }

    private func lockRegionEditingForSession() {
        hoverSelection.lockRegionEditingForSession()
        for window in overlayWindows {
            window.showWindowCandidate(nil)
        }
    }
```

- [ ] **Step 4: Emit hover and lock events from the view**

In `SelectionOverlayView`, add stored callbacks matching the initializer. Implement mouse movement:

```swift
    override func mouseMoved(with event: NSEvent) {
        let point = clampedPoint(event.locationInWindow)
        onMouseMoved(globalRect(fromLocalRect: CGRect(origin: point, size: .zero)).origin, hudStackView.frame.contains(point))
    }
```

At the top of `mouseDown(with:)`, before setting `dragOperation`, add:

```swift
        windowCandidate = nil
        isRegionLockedForSession = true
        onRegionEditingStarted()
```

- [ ] **Step 5: Confirm current active rect from controller key monitor**

Change `SelectionOverlayController.confirmCurrentSelection()` to use `activeGlobalRect`:

```swift
    private func confirmCurrentSelection() {
        guard let selectedRect = overlayWindows.first(where: { $0.activeGlobalRect != nil })?.activeGlobalRect else {
            NSSound.beep()
            return
        }

        guard SelectionGeometry.isValidSelection(selectedRect) else {
            NSSound.beep()
            return
        }

        finishSelection(with: selectedRect)
    }
```

- [ ] **Step 6: Build and run core tests**

Run:

```bash
swift test
swift build
```

Expected: both succeed.

## Task 5: Polish, Docs, And Verification

**Files:**
- Modify: `docs/architecture.md`
- Review: `docs/superpowers/specs/2026-05-25-window-screenshot-design.md`

- [ ] **Step 1: Update architecture knowledge**

In `docs/architecture.md`, update the runtime flow around selection overlay and capture:

```markdown
7. `SelectionOverlayWindow` shows a single active editable selection across displays, supports drag adjustment, can temporarily display an eligible hovered application window as a candidate, follows the active rectangle with a compact native glass HUD, and returns a global Cocoa screen rectangle after keyboard confirmation.
8. `WindowCandidateProvider` adapts CoreGraphics window-list metadata into eligible ordinary application window candidates while excluding Frame's own windows and obvious non-application surfaces.
9. `CaptureService` converts the selected Cocoa rectangle into a Quartz capture rectangle and returns PNG data plus `NSImage`.
```

Add `WindowCandidateProvider` to the AppKit-specific boundary paragraph.

- [ ] **Step 2: Run full verification**

Run:

```bash
swift test
swift build
scripts/package-app.sh
```

Expected:

- `swift test` passes.
- `swift build` passes.
- `scripts/package-app.sh` creates `.build/app/Frame.app`.

- [ ] **Step 3: Manual smoke test**

Run packaged app from `.build/app/Frame.app` or copy it to the stable local app path used for Screen Recording permission. Verify:

- `Command+Shift+A` shows the previous region.
- Hovering a normal application window for about `350ms` shows the window candidate.
- Pressing Enter captures the candidate's full bounds.
- Dragging a region cancels automatic hover for the current session.
- Moving over the HUD does not trigger automatic hover.
- Stage Manager or similar system surfaces do not become candidates in the tested setup.

- [ ] **Step 4: Commit implementation**

After verification passes:

```bash
git add Sources/FrameCore/WindowCandidate.swift Sources/FrameCore/WindowHoverSelection.swift Sources/FrameApp/WindowCandidateProvider.swift Sources/FrameApp/SelectionOverlayController.swift Sources/FrameApp/SelectionOverlayWindow.swift Sources/FrameApp/ActiveScreenResolver.swift Tests/FrameCoreTests/FrameCoreTests.swift docs/architecture.md
git commit -m "feat: add window hover screenshot selection"
```

## Self-Review

- Spec coverage: automatic hover, `350ms` delay, HUD exclusion, same-candidate reuse, region-edit lock, ordinary-window filtering, rectangular capture semantics, last-selection memory, and future settings hooks are covered by tasks.
- Placeholder scan: no placeholder implementation steps remain; each task names concrete files, code, commands, and expected outcomes.
- Type consistency: `WindowCandidate`, `WindowHoverSelection`, `WindowCandidateProvider`, `activeGlobalRect`, and `showWindowCandidate(_:)` names are consistent across tasks.

