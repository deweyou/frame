# Scrolling Screenshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual-default vertical scrolling screenshots with optional small-step automatic scrolling assist. The session stitches repeated captures of one fixed selected region into a single long PNG after Finish and routes it through the normal screenshot output path.

**Architecture:** Keep deterministic stitching in `FrameCore`, using simple RGBA bitmap comparison and canvas composition. Keep AppKit side effects in `FrameApp`: HUD entry, non-interactive boundary, manual-default capture sampling, optional small-step scroll-wheel assist, and output routing through existing `CapturedScreenshot`.

**Tech Stack:** Swift 6.1, AppKit, CoreGraphics, XCTest, existing `CaptureService`, `SelectionOverlayWindow`, `AppDelegate`, Quick Access, and capture history.

---

## File Structure

- Create `Sources/FrameCore/ScrollingScreenshotStitcher.swift`
  - Owns `ScrollingScreenshotFrame`, `ScrollingScreenshotStitchingError`, overlap detection, duplicate skipping, and final `CGImage` composition.
- Create `Tests/FrameCoreTests/ScrollingScreenshotStitcherTests.swift`
  - Builds small deterministic bitmap images and verifies red-green stitching behavior.
- Modify `Sources/FrameApp/SelectionOverlayCompletion.swift`
  - Adds `.scrollingScreenshot(SelectionCapture)` and keeps `selection` exposing it.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift`
  - Adds a scrolling screenshot HUD icon, tooltip/accessibility label, test routing, and click handler.
- Modify `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`
  - Covers completion shape and HUD button exposure.
- Create `Sources/FrameApp/ScrollingScreenshotSessionController.swift`
  - Owns active scrolling capture session, periodic sampling, optional automatic scroll assist, boundary overlay, final stitching, and test seams.
- Create `Tests/FrameAppTests/ScrollingScreenshotSessionControllerTests.swift`
  - Covers session start, sampled frames, finish success, cancel cleanup, and failure routing without live desktop capture.
- Modify `Sources/FrameApp/AppDelegate.swift`
  - Instantiates session controller, routes new completion, stores/outputs stitched screenshot, and blocks repeated shortcuts while scrolling is active.
- Modify `Tests/FrameAppTests/AppDelegateRecordingTests.swift`
  - Adds AppDelegate routing/busy-flow coverage using a fake scrolling controller.
- Modify `Sources/FrameApp/AppStrings.swift`
  - Adds localized strings for HUD label, Finish, Cancel, and failure messages.
- Modify `docs/architecture.md`, `README.md`, and `README_ZH.md`
  - Documents that manual-default scrolling screenshot with automatic assist is now implemented.

## Task 1: FrameCore Stitcher

**Files:**
- Create: `Sources/FrameCore/ScrollingScreenshotStitcher.swift`
- Create: `Tests/FrameCoreTests/ScrollingScreenshotStitcherTests.swift`

- [ ] **Step 1: Write failing stitcher tests**

Add tests with helper images whose rows encode distinct colors:

```swift
func testStitchesTwoFramesWithKnownVerticalOverlap() throws {
    let first = try makeStripedImage(rows: [
        .red, .green, .blue, .yellow,
    ])
    let second = try makeStripedImage(rows: [
        .blue, .yellow, .cyan, .magenta,
    ])
    let stitcher = ScrollingScreenshotStitcher()

    let output = try stitcher.stitch([
        ScrollingScreenshotFrame(image: first, scale: 1),
        ScrollingScreenshotFrame(image: second, scale: 1),
    ])

    XCTAssertEqual(output.width, first.width)
    XCTAssertEqual(output.height, 6)
    XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan, .magenta])
}

func testSkipsIdenticalFramesAsNoProgress() throws {
    let first = try makeStripedImage(rows: [.red, .green, .blue])
    let stitcher = ScrollingScreenshotStitcher()

    let output = try stitcher.stitch([
        ScrollingScreenshotFrame(image: first, scale: 1),
        ScrollingScreenshotFrame(image: first, scale: 1),
        ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.blue, .yellow, .cyan]), scale: 1),
    ])

    XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan])
}

func testFailsWhenThereIsNoReliableOverlap() throws {
    let stitcher = ScrollingScreenshotStitcher()

    XCTAssertThrowsError(try stitcher.stitch([
        ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.red, .green]), scale: 1),
        ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.cyan, .magenta]), scale: 1),
    ])) { error in
        XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .noReliableOverlap)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```sh
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: compile fails because `ScrollingScreenshotStitcher`, `ScrollingScreenshotFrame`, and `ScrollingScreenshotStitchingError` do not exist.

- [ ] **Step 3: Implement minimal stitcher**

Create public types:

```swift
public struct ScrollingScreenshotFrame: Equatable {
    public let image: CGImage
    public let scale: CGFloat

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }
}

public enum ScrollingScreenshotStitchingError: Error, Equatable {
    case insufficientFrames
    case noScrollProgress
    case noReliableOverlap
    case outputEncodingFailed
}

public final class ScrollingScreenshotStitcher {
    public init() {}

    public func stitch(_ frames: [ScrollingScreenshotFrame]) throws -> CGImage {
        // Convert frames to RGBA buffers, skip identical frames, find vertical overlap,
        // and compose accepted non-duplicate rows into one output image.
    }
}
```

Implement comparison with exact row equality first. This is enough for deterministic tests and can be refined after real sampling proves tolerance is needed.

- [ ] **Step 4: Run GREEN**

Run:

```sh
swift test --filter ScrollingScreenshotStitcherTests
```

Expected: all stitcher tests pass.

## Task 2: HUD Completion Entry

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayCompletion.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [ ] **Step 1: Write failing completion/HUD tests**

Add completion coverage:

```swift
func testScrollingScreenshotCompletionExposesSelection() {
    let selection = SelectionCapture(rect: CGRect(x: 10, y: 20, width: 120, height: 80), kind: .region)

    let completion = SelectionOverlayCompletion.scrollingScreenshot(selection)

    XCTAssertEqual(completion.selection?.rect, selection.rect)
    XCTAssertEqual(completion.selection?.kind, selection.kind)
}
```

Update HUD expectations:

```swift
XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("滚动长截图"))
XCTAssertEqual(
    window.hudButtonImageDescriptionsForTesting(),
    ["crop", "display", "timer", "scroll", "character.textbox", "record.circle"]
)
```

Add action routing:

```swift
func testScrollingScreenshotButtonCompletesWithActiveSelection() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    var completion: SelectionOverlayCompletion?
    let selectionRect = CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 20, width: 240, height: 160)
    let window = try makeOverlayWindowForTesting(initialGlobalRect: selectionRect) { completion = $0 }

    XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "滚动长截图"))

    guard case let .scrollingScreenshot(selection) = completion else {
        return XCTFail("Expected scrolling screenshot completion")
    }
    XCTAssertEqual(selection.rect, selectionRect)
}
```

- [ ] **Step 2: Run RED**

Run:

```sh
swift test --filter SelectionOverlayCompletionTests
```

Expected: compile/test failure because `.scrollingScreenshot` and the HUD button do not exist.

- [ ] **Step 3: Add completion and HUD button**

Add case:

```swift
case scrollingScreenshot(SelectionCapture)
```

Include it in `selection`. Add `makeScrollingScreenshotButton()` using SF Symbol `scroll`, accessibility label `"滚动长截图"`, tooltip `"滚动长截图"`, and handler:

```swift
@objc private func scrollingScreenshotButtonClicked() {
    guard !isDelayCountdownActive else { return }
    guard let activeSelection, SelectionGeometry.isValidSelection(activeSelection.rect) else {
        NSSound.beep()
        return
    }
    completeSelection(with: .scrollingScreenshot(activeSelection))
}
```

Update `performHUDActionForTesting` to trigger the new handler.

- [ ] **Step 4: Run GREEN**

Run:

```sh
swift test --filter SelectionOverlayCompletionTests
```

Expected: tests pass.

## Task 3: Scrolling Session Controller

**Files:**
- Create: `Sources/FrameApp/ScrollingScreenshotSessionController.swift`
- Create: `Tests/FrameAppTests/ScrollingScreenshotSessionControllerTests.swift`

- [ ] **Step 1: Write failing session tests**

Use injected closures instead of real screen capture:

```swift
func testFinishStitchesSampledFramesAndCallsCompletion() async throws {
    let first = try makeCapturedScreenshot(rows: [.red, .green, .blue])
    let second = try makeCapturedScreenshot(rows: [.blue, .yellow, .cyan])
    let controller = ScrollingScreenshotSessionController(
        sampleInterval: 0.01,
        captureRegion: { _ in [first, second].removeFirst() },
        stitch: { screenshots in
            XCTAssertEqual(screenshots.count, 2)
            return first
        }
    )
    var completed: CapturedScreenshot?

    controller.start(selection: SelectionCapture(rect: first.rect, kind: .region), strings: AppStrings(language: .zhHans)) {
        completed = $0
    } onCancel: {
        XCTFail("Should not cancel")
    } onFailure: { error in
        XCTFail("Unexpected failure: \(error)")
    }
    controller.captureSampleForTesting()
    controller.captureSampleForTesting()
    controller.finishForTesting()

    XCTAssertEqual(completed?.rect, first.rect)
}

func testCancelClosesWithoutCompletion() throws {
    let controller = ScrollingScreenshotSessionController(captureRegion: { _ in throw CaptureServiceError.pngEncodingFailed })
    var didCancel = false
    controller.start(selection: SelectionCapture(rect: CGRect(x: 0, y: 0, width: 10, height: 10), kind: .region), strings: AppStrings(language: .zhHans), onComplete: { _ in XCTFail("Should not complete") }, onCancel: { didCancel = true }, onFailure: { _ in XCTFail("Should not fail") })

    controller.cancelForTesting()

    XCTAssertTrue(didCancel)
}
```

- [ ] **Step 2: Run RED**

Run:

```sh
swift test --filter ScrollingScreenshotSessionControllerTests
```

Expected: compile fails because controller does not exist.

- [ ] **Step 3: Implement session controller**

Create a `@MainActor final class ScrollingScreenshotSessionController` with:

```swift
typealias CaptureRegion = (CGRect) throws -> CapturedScreenshot
typealias StitchScreenshots = ([CapturedScreenshot]) throws -> CapturedScreenshot

func start(
    selection: SelectionCapture,
    strings: AppStrings,
    onComplete: @escaping (CapturedScreenshot) -> Void,
    onCancel: @escaping () -> Void,
    onFailure: @escaping (Error) -> Void
)
func finish()
func cancel()
var isActive: Bool { get }
```

Use a repeating `Timer` on `.common` run loop to call `captureRegion(selection.rect)`. Keep an initial immediate sample on start. Show a compact `NSPanel` HUD with Finish and Cancel buttons and a non-interactive boundary panel. The first implementation can reuse the recording boundary style by extracting a shared `SelectionBoundaryOverlayController` if needed; keep recording-specific `preparationState` names out of scrolling code.

- [ ] **Step 4: Run GREEN**

Run:

```sh
swift test --filter ScrollingScreenshotSessionControllerTests
```

Expected: tests pass.

## Task 4: AppDelegate Routing And Busy State

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [ ] **Step 1: Add failing AppDelegate tests**

Extend `SpySelectionOverlayController` or add a fake completion path so `startCaptureFlowForTesting()` can emit `.scrollingScreenshot(selection)`. Add tests:

```swift
func testScrollingScreenshotCompletionStartsScrollingSession() {
    _ = NSApplication.shared
    let selection = SelectionCapture(rect: CGRect(x: 40, y: 60, width: 320, height: 180), kind: .region)
    let selectionOverlay = SpySelectionOverlayController()
    selectionOverlay.completionToEmit = .scrollingScreenshot(selection)
    let scrollingController = SpyScrollingScreenshotSessionController()
    let delegate = AppDelegate(
        selectionOverlayController: selectionOverlay,
        scrollingScreenshotSessionController: scrollingController,
        hasScreenRecordingAccess: { true },
        showMissingScreenRecordingPermission: {},
        playInvalidActionFeedback: {}
    )

    XCTAssertTrue(delegate.startCaptureFlowForTesting())
    selectionOverlay.emitStoredCompletion()

    XCTAssertEqual(scrollingController.startedSelections, [selection])
}

func testCaptureFlowIgnoresShortcutWhileScrollingSessionIsActive() {
    _ = NSApplication.shared
    let scrollingController = SpyScrollingScreenshotSessionController()
    scrollingController.isActive = true
    var beepCount = 0
    let delegate = AppDelegate(
        scrollingScreenshotSessionController: scrollingController,
        hasScreenRecordingAccess: { true },
        showMissingScreenRecordingPermission: {},
        playInvalidActionFeedback: { beepCount += 1 }
    )

    XCTAssertFalse(delegate.startCaptureFlowForTesting())

    XCTAssertEqual(beepCount, 1)
}

func testFinishedScrollingScreenshotShowsQuickAccessPreview() {
    _ = NSApplication.shared
    let selection = SelectionCapture(rect: CGRect(x: 40, y: 60, width: 320, height: 180), kind: .region)
    let selectionOverlay = SpySelectionOverlayController()
    selectionOverlay.completionToEmit = .scrollingScreenshot(selection)
    let scrollingController = SpyScrollingScreenshotSessionController()
    let delegate = AppDelegate(
        selectionOverlayController: selectionOverlay,
        scrollingScreenshotSessionController: scrollingController,
        captureHistoryStore: CaptureHistoryStore(rootDirectory: makeTemporaryDirectory()),
        hasScreenRecordingAccess: { true },
        showMissingScreenRecordingPermission: {},
        playInvalidActionFeedback: {}
    )
    let screenshot = CapturedScreenshot(
        pngData: Data([1, 2, 3]),
        image: NSImage(size: CGSize(width: 32, height: 64)),
        rect: selection.rect
    )

    XCTAssertTrue(delegate.startCaptureFlowForTesting())
    selectionOverlay.emitStoredCompletion()
    scrollingController.complete(with: screenshot)

    XCTAssertEqual(delegate.quickAccessScreenshotCountForTesting(), 1)
}
```

Expected assertions:

- The fake scrolling controller receives the same `SelectionCapture`.
- A second screenshot shortcut returns `false` and beeps while scrolling is active.
- Completing with a stitched `CapturedScreenshot` adds one screenshot Quick Access item.

- [ ] **Step 2: Run RED**

Run:

```sh
swift test --filter AppDelegateRecordingTests
```

Expected: compile/test failure because AppDelegate cannot inject or route a scrolling session.

- [ ] **Step 3: Add routing**

Add a protocol:

```swift
@MainActor
protocol ScrollingScreenshotSessionControlling: AnyObject {
    var isActive: Bool { get }
    func start(selection: SelectionCapture, strings: AppStrings, onComplete: @escaping (CapturedScreenshot) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void)
}
```

Inject it into `AppDelegate`, include `scrollingScreenshotSessionController.isActive` in `isCaptureFlowBusy`, and route:

```swift
case let .scrollingScreenshot(selection):
    self.startScrollingScreenshot(selection: selection, anchor: quickAccessAnchor)
```

On complete, call `storeInCaptureHistory(screenshot)`, restore temporarily hidden previews, and `showQuickAccess(for:anchor:)`.

- [ ] **Step 4: Run GREEN**

Run:

```sh
swift test --filter AppDelegateRecordingTests
```

Expected: tests pass.

## Task 5: Strings, Failure Copy, And Output Polish

**Files:**
- Modify: `Sources/FrameApp/AppStrings.swift`
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`
- Modify: `Sources/FrameApp/ScrollingScreenshotSessionController.swift`

- [ ] **Step 1: Write failing string tests**

Add tests asserting Chinese and English values for:

- `scrollingScreenshotAction`
- `scrollingScreenshotFailedTitle`
- `scrollingScreenshotInsufficientProgress`

- [ ] **Step 2: Run RED**

Run:

```sh
swift test --filter AppStringsTests
```

Expected: compile failure for missing properties.

- [ ] **Step 3: Add localized strings and use them**

Add concise values:

```swift
var scrollingScreenshotAction: String { zh: "滚动长截图", en: "Scrolling Screenshot" }
var scrollingScreenshotFailedTitle: String { zh: "滚动截图失败", en: "Scrolling screenshot failed" }
var scrollingScreenshotInsufficientProgress: String { zh: "请滚动内容后再完成。", en: "Scroll the content before finishing." }
```

Use strings in the HUD and failure alert path.

- [ ] **Step 4: Run GREEN**

Run:

```sh
swift test --filter AppStringsTests
```

Expected: tests pass.

## Task 6: Documentation And README

**Files:**
- Modify: `docs/architecture.md`
- Modify: `README.md`
- Modify: `README_ZH.md`

- [ ] **Step 1: Update architecture**

Add scrolling screenshot to the architecture flow: `Selection -> ScrollingCapture -> Capture -> History/QuickAccess`. Record that `FrameCore` owns deterministic stitching and `FrameApp` owns sampling/session lifecycle.

- [ ] **Step 2: Update README pair**

Move scrolling capture out of future features and into implemented screenshot capabilities in both English and Chinese. Keep both documents aligned.

- [ ] **Step 3: Inspect docs diff**

Run:

```sh
git diff -- docs/architecture.md README.md README_ZH.md
```

Expected: docs describe automatic vertical scrolling screenshots.

## Task 7: Full Verification And Local App Package

**Files:**
- No new files unless verification reveals defects.

- [ ] **Step 1: Run targeted tests**

Run:

```sh
swift test --filter ScrollingScreenshotStitcherTests
swift test --filter ScrollingScreenshotSessionControllerTests
swift test --filter SelectionOverlayCompletionTests
swift test --filter AppDelegateRecordingTests
swift test --filter AppStringsTests
```

Expected: all pass.

- [ ] **Step 2: Run required repository verification**

Run:

```sh
swift test
swift build
scripts/package-app.sh
```

Expected: all pass and `.build/app/Frame.app` is produced.

- [ ] **Step 3: GUI handoff decision**

Because this is user-facing GUI work, ask whether to replace the local test app unless replacement was already completed in the same turn. If replacing, use the stable signing flow:

```sh
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
codesign -dv --verbose=2 ~/Applications/Frame.app
```

Expected: codesign output includes `Authority=Frame Local Dev CLI`.

## Plan Self-Review

- Spec coverage: the tasks cover automatic vertical entry, fixed-region sampling, progress detection, deterministic stitching, existing screenshot output reuse, docs, and verification.
- Placeholders: no `TBD`, `TODO`, or later-only steps remain.
- Scope guard: plan now uses automatic vertical scroll-wheel capture and still excludes horizontal scrolling.
- Type consistency: `SelectionOverlayCompletion.scrollingScreenshot`, `ScrollingScreenshotSessionController`, `ScrollingScreenshotFrame`, and `ScrollingScreenshotStitcher` names are consistent across tasks.
