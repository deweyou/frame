import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class ScrollingScreenshotSessionControllerTests: XCTestCase {
    func testStartShowsBoundaryOverlayAroundSelection() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )

        XCTAssertEqual(controller.boundaryOverlayFrameForTesting(), screenFrame.integral)
        XCTAssertEqual(
            controller.boundaryOverlaySelectionRectForTesting(),
            selectionRect.integral.offsetBy(dx: -screenFrame.integral.minX, dy: -screenFrame.integral.minY)
        )

        controller.cancel()
        XCTAssertNil(controller.boundaryOverlayFrameForTesting())
        XCTAssertNil(controller.boundaryOverlaySelectionRectForTesting())
    }

    func testHUDUsesSharedDeepGlassChromeAndIconButtons() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )

        let chromeColors = try XCTUnwrap(controller.hudChromeColorsForTesting())
        XCTAssertEqual(colorComponents(chromeColors.background), colorComponents(HUDChromePalette.deepGlassBackgroundColor))
        XCTAssertEqual(colorComponents(chromeColors.border), colorComponents(HUDChromePalette.deepGlassBorderColor))

        let buttons = controller.hudButtonAttributesForTesting()
        XCTAssertEqual(buttons.map(\.label), ["开始", "取消"])
        for button in buttons {
            XCTAssertEqual(colorComponents(try XCTUnwrap(button.tintColor)), colorComponents(HUDChromePalette.deepGlassForegroundColor))
            XCTAssertEqual(button.imagePosition, .imageOnly)
            XCTAssertEqual(button.bezelStyle, .regularSquare)
        }

        controller.cancel()
    }

    func testRunningHUDShowsAutoScrollToggle() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()

        XCTAssertEqual(controller.hudButtonAttributesForTesting().map(\.label), ["完成", "自动滚动", "取消"])
        XCTAssertEqual(controller.hudButtonAttributesForTesting().map(\.symbolName), ["checkmark", "arrow.down.circle.fill", "xmark"])

        controller.toggleAutoScroll()

        XCTAssertEqual(controller.hudButtonAttributesForTesting().map(\.label), ["完成", "停止滚动", "取消"])
        XCTAssertEqual(controller.hudButtonAttributesForTesting().map(\.symbolName), ["checkmark", "stop.circle.fill", "xmark"])

        controller.cancel()
    }

    func testFinishImmediatelyClosesCaptureHUDWhileFinalStitchRuns() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var pendingStitch: (() -> Void)?
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in screenshots[0] },
            performStitch: { work in pendingStitch = work }
        )

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()

        controller.clickFinishButtonForTesting()

        XCTAssertTrue(controller.isActive)
        XCTAssertNotNil(pendingStitch)
        XCTAssertFalse(controller.hudPanelExistsForTesting())
        XCTAssertFalse(controller.hudPanelIsVisibleForTesting())
        XCTAssertNil(controller.boundaryOverlayFrameForTesting())

        controller.cancel()
        XCTAssertFalse(controller.hudPanelExistsForTesting())
    }

    func testPersistentFinalStitchFailureRestoresRunningHUD() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let retryExpectation = expectation(description: "capture resumes after final stitch failure")
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap },
            recoverStitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap }
        )

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onPreviewUpdate: { _ in },
            onFinishStarted: { _ in },
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onRetryableFailure: { _ in retryExpectation.fulfill() },
            onFailure: { error in XCTFail("Unexpected terminal failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [retryExpectation], timeout: 1)

        XCTAssertEqual(controller.hudButtonAttributesForTesting().map(\.label), ["完成", "自动滚动", "取消"])
        XCTAssertNotNil(controller.boundaryOverlayFrameForTesting())
        controller.cancel()
    }

    func testFinishButtonCompletesDefaultFinalPipelineWhilePreviewWorkIsActive() throws {
        let screenFrame = try XCTUnwrap(NSScreen.screens.first?.frame)
        let selectionRect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 50,
            width: min(120, screenFrame.width - 80),
            height: min(90, screenFrame.height - 100)
        )
        var screenshots = [
            try makeStripedCapturedScreenshot(rows: [
                [255, 0, 0, 255],
                [0, 255, 0, 255],
                [0, 0, 255, 255],
                [255, 255, 0, 255],
            ]),
            try makeStripedCapturedScreenshot(rows: [
                [0, 0, 255, 255],
                [255, 255, 0, 255],
                [255, 0, 255, 255],
                [0, 255, 255, 255],
            ]),
        ]
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let completionExpectation = expectation(description: "default final stitch completes")
        let controller = ScrollingScreenshotSessionController(
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step }
        )
        var completedScreenshot: CapturedScreenshot?

        controller.start(
            selection: SelectionCapture(rect: selectionRect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: {
                completedScreenshot = $0
                completionExpectation.fulfill()
            },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.clickFinishButtonForTesting()

        wait(for: [completionExpectation], timeout: 2)

        XCTAssertFalse(completedScreenshot?.pngData.isEmpty ?? true)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.hudPanelExistsForTesting())
    }

    func testStartWaitsForUserBeforeCapturing() {
        var captureCount = 0
        var didCancel = false
        let controller = ScrollingScreenshotSessionController(
            showsInterface: false,
            captureRegion: { rect in
                captureCount += 1
                return self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { didCancel = true },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(captureCount, 0)

        controller.cancel()

        XCTAssertTrue(didCancel)
        XCTAssertFalse(controller.isActive)
    }

    func testDefaultScrollDeltaKeepsGenerousOverlapBetweenSamples() {
        XCTAssertEqual(
            ScrollingScreenshotSessionController.scrollWheelDeltaForTesting(
                rect: CGRect(x: 0, y: 0, width: 320, height: 1_000)
            ),
            220
        )
        XCTAssertEqual(
            ScrollingScreenshotSessionController.scrollWheelDeltaForTesting(
                rect: CGRect(x: 0, y: 0, width: 320, height: 80)
            ),
            24
        )
    }

    func testStartSamplesWithoutAutoScrollingAndFinishUsesCapturedRange() throws {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var screenshots = [
            makeCapturedScreenshot(size: CGSize(width: 20, height: 20), rect: CGRect(x: 10, y: 20, width: 20, height: 20)),
            makeCapturedScreenshot(size: CGSize(width: 20, height: 30), rect: CGRect(x: 10, y: 20, width: 20, height: 30)),
        ]
        var stitchedInputCount = 0
        var scrolledRects: [CGRect] = []
        let completionExpectation = expectation(description: "manual scrolling screenshot completes")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { rect in scrolledRects.append(rect) },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in
                stitchedInputCount = screenshots.count
                return screenshots[0]
            }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in completionExpectation.fulfill() },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(scrolledRects, [])
        XCTAssertEqual(stitchedInputCount, 2)
        XCTAssertFalse(controller.isActive)
    }

    func testAutoScrollToggleAddsSmallScrollSteps() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var captureCount = 0
        var scrolledRects: [CGRect] = []
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in
                captureCount += 1
                return self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { rect in scrolledRects.append(rect) },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in screenshots[0] }
        )
        let selection = SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region)

        controller.start(
            selection: selection,
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()

        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(scrolledRects, [])

        controller.toggleAutoScroll()
        pendingStep?()

        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(scrolledRects, [selection.rect, selection.rect])

        controller.cancel()
    }

    func testSamplingKeepsFramesWhenProgressDetectorMissesSparseManualScroll() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var captureCount = 0
        var stitchedInputCount = 0
        let completionExpectation = expectation(description: "manual scrolling screenshot preserves sparse intermediate samples")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in
                captureCount += 1
                return self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in
                stitchedInputCount = screenshots.count
                return screenshots[0]
            }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in completionExpectation.fulfill() },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        pendingStep?()
        controller.finish()

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(captureCount, 3)
        XCTAssertEqual(stitchedInputCount, 3)
        XCTAssertFalse(controller.isActive)
    }

    func testSamplingUpdatesLivePreviewAfterReliableStitch() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var pendingPreviewWork: (() -> Void)?
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let initialScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 20),
            rect: CGRect(x: 10, y: 20, width: 20, height: 20)
        )
        let nextScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 30),
            rect: CGRect(x: 10, y: 20, width: 20, height: 30)
        )
        let previewScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 42),
            rect: CGRect(x: 10, y: 20, width: 20, height: 42)
        )
        var screenshots = [initialScreenshot, nextScreenshot]
        let previewUpdated = expectation(description: "stitched preview updates")
        previewPresenter.onUpdate = { status, pixelHeight in
            if status == .capturing, pixelHeight == 42 {
                previewUpdated.fulfill()
            }
        }
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewStitch: { _ in
                ScrollingScreenshotPreviewSnapshot(image: previewScreenshot.image, pixelHeight: 42)
            },
            performPreviewStitch: { work in pendingPreviewWork = work },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: initialScreenshot.rect, kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()

        XCTAssertEqual(previewPresenter.statuses, [.waiting, .capturing])
        XCTAssertEqual(previewPresenter.pixelHeights, [0, 20])

        pendingStep?()
        XCTAssertNotNil(pendingPreviewWork)
        pendingPreviewWork?()

        wait(for: [previewUpdated], timeout: 1)
        XCTAssertEqual(previewPresenter.statuses, [.waiting, .capturing, .capturing])
        XCTAssertEqual(previewPresenter.pixelHeights, [0, 20, 42])

        controller.cancel()
        XCTAssertEqual(previewPresenter.closeCallCount, 1)
    }

    func testDefaultPreviewPipelineRunsOnBackgroundQueueWithoutActorViolation() throws {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let previewUpdated = expectation(description: "default background preview updates")
        previewPresenter.onUpdate = { status, pixelHeight in
            if status == .capturing, pixelHeight == 6 {
                previewUpdated.fulfill()
            }
        }
        var screenshots = [
            try makeStripedCapturedScreenshot(rows: [
                [255, 0, 0, 255],
                [0, 255, 0, 255],
                [0, 0, 255, 255],
                [255, 255, 0, 255],
            ]),
            try makeStripedCapturedScreenshot(rows: [
                [0, 0, 255, 255],
                [255, 255, 0, 255],
                [0, 255, 255, 255],
                [255, 0, 255, 255],
            ]),
        ]
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 3, height: 4), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()

        wait(for: [previewUpdated], timeout: 1)
        XCTAssertTrue(controller.isActive)
        controller.cancel()
    }

    func testDefaultPreviewRecoversAfterIsolatedUnmatchedFrame() throws {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let previewFailed = expectation(description: "isolated bad frame interrupts preview")
        let previewRecovered = expectation(description: "new good frame restores preview")
        var didObservePreviewFailure = false
        previewPresenter.onUpdate = { status, pixelHeight in
            if status == .unreliableOverlap, !didObservePreviewFailure {
                didObservePreviewFailure = true
                previewFailed.fulfill()
            }
            if status == .capturing, pixelHeight == 6 {
                previewRecovered.fulfill()
            }
        }
        var screenshots = [
            try makeStripedCapturedScreenshot(rows: [
                [255, 0, 0, 255],
                [0, 255, 0, 255],
                [0, 0, 255, 255],
                [255, 255, 0, 255],
            ]),
            try makeStripedCapturedScreenshot(rows: [
                [255, 255, 255, 255],
                [255, 0, 0, 255],
                [0, 0, 0, 255],
                [0, 255, 0, 255],
            ], width: 4),
            try makeStripedCapturedScreenshot(rows: [
                [0, 0, 255, 255],
                [255, 255, 0, 255],
                [0, 255, 255, 255],
                [255, 0, 255, 255],
            ]),
        ]
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 0, y: 0, width: 3, height: 4), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()

        wait(for: [previewFailed], timeout: 1)
        pendingStep?()

        wait(for: [previewRecovered], timeout: 1)
        XCTAssertEqual(previewPresenter.statuses, [.waiting, .capturing, .unreliableOverlap, .capturing])
        XCTAssertEqual(previewPresenter.pixelHeights, [0, 4, 0, 6])
        XCTAssertTrue(controller.isActive)
        controller.cancel()
    }

    func testPreviewFailurePreservesLastKnownGoodImageAndShowsInterruptedState() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let previewFailed = expectation(description: "preview failure is shown")
        previewPresenter.onUpdate = { status, _ in
            if status == .unreliableOverlap {
                previewFailed.fulfill()
            }
        }
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewStitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap },
            performPreviewStitch: { work in work() },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Preview failure should not end the session: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()

        wait(for: [previewFailed], timeout: 1)
        XCTAssertEqual(previewPresenter.imageUpdateCount, 1)
        XCTAssertEqual(previewPresenter.statuses.last, .unreliableOverlap)
        XCTAssertTrue(controller.isActive)

        controller.cancel()
    }

    func testPreviewRenderingCoalescesPendingSamplesIntoNewestRequest() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var previewWork: [() -> Void] = []
        var stitchedInputCounts: [Int] = []
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let newestPreviewUpdated = expectation(description: "newest coalesced preview updates")
        previewPresenter.onUpdate = { status, pixelHeight in
            if status == .capturing, pixelHeight == 40 {
                newestPreviewUpdated.fulfill()
            }
        }
        var screenshots = [20, 30, 40].map { height in
            makeCapturedScreenshot(
                size: CGSize(width: 20, height: height),
                rect: CGRect(x: 10, y: 20, width: 20, height: height)
            )
        }
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewStitch: { screenshots in
                stitchedInputCounts.append(screenshots.count)
                let screenshot = screenshots.last!
                return ScrollingScreenshotPreviewSnapshot(
                    image: screenshot.image,
                    pixelHeight: Int(screenshot.image.size.height)
                )
            },
            performPreviewStitch: { work in previewWork.append(work) },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        pendingStep?()

        XCTAssertEqual(previewWork.count, 1)
        previewWork[0]()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(previewWork.count, 2)
        XCTAssertEqual(stitchedInputCounts, [2])
        previewWork[1]()

        wait(for: [newestPreviewUpdated], timeout: 1)
        XCTAssertEqual(stitchedInputCounts, [2, 3])

        controller.cancel()
    }

    func testCancelledSessionIgnoresStalePreviewCompletion() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var pendingPreviewWork: (() -> Void)?
        let previewPresenter = ScrollingScreenshotPreviewPresenterSpy()
        let previewScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 40),
            rect: CGRect(x: 10, y: 20, width: 20, height: 40)
        )
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            previewStitch: { _ in
                ScrollingScreenshotPreviewSnapshot(image: previewScreenshot.image, pixelHeight: 40)
            },
            performPreviewStitch: { work in pendingPreviewWork = work },
            previewPresenter: previewPresenter
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        let statusCountBeforeCancel = previewPresenter.statuses.count

        controller.cancel()
        pendingPreviewWork?()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(previewPresenter.statuses.count, statusCountBeforeCancel)
        XCTAssertFalse(controller.isActive)
    }

    func testFinishStopsScrollingImmediatelyAndStitchesLater() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var captureCount = 0
        var scrollCount = 0
        var pendingStitch: (() -> Void)?
        let completionExpectation = expectation(description: "stitch completion is delivered after deferred work")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in
                captureCount += 1
                return self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in scrollCount += 1 },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in screenshots[0] },
            performStitch: { work in pendingStitch = work }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in completionExpectation.fulfill() },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()

        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(scrollCount, 0)

        pendingStep?()
        controller.finish()
        pendingStep?()

        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(scrollCount, 0)
        XCTAssertTrue(controller.isActive)

        pendingStitch?()

        wait(for: [completionExpectation], timeout: 1)
        XCTAssertFalse(controller.isActive)
    }

    func testFinishUsesCapturedRangeOnly() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var screenshots = [
            makeCapturedScreenshot(size: CGSize(width: 20, height: 20), rect: CGRect(x: 10, y: 20, width: 20, height: 20)),
            makeCapturedScreenshot(size: CGSize(width: 20, height: 30), rect: CGRect(x: 10, y: 20, width: 20, height: 30)),
            makeCapturedScreenshot(size: CGSize(width: 20, height: 40), rect: CGRect(x: 10, y: 20, width: 20, height: 40)),
        ]
        var stitchedInputCount = 0
        let completionExpectation = expectation(description: "manual finish completes current range")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in screenshots.removeFirst() },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in
                stitchedInputCount = screenshots.count
                return screenshots[0]
            }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in completionExpectation.fulfill() },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(stitchedInputCount, 2)
        XCTAssertFalse(controller.isActive)
    }

    func testFinishWithOnlyInitialSampleCompletesSingleCapture() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let initialScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 20),
            rect: CGRect(x: 10, y: 20, width: 20, height: 20)
        )
        let completionExpectation = expectation(description: "single sample finish completes")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in initialScreenshot },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { _ in
                XCTFail("Single sample finish should not invoke stitcher")
                return initialScreenshot
            }
        )
        var completedScreenshot: CapturedScreenshot?

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { screenshot in
                completedScreenshot = screenshot
                completionExpectation.fulfill()
            },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        controller.finish()
        pendingStep?()

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(completedScreenshot?.rect, initialScreenshot.rect)
        XCTAssertFalse(controller.isActive)
    }

    func testAutoScrollStopsAtMaximumStepCountWithoutFinishingSession() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var scrolledCount = 0
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            maximumScrollSteps: 2,
            showsInterface: false,
            captureRegion: { rect in
                return self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in scrolledCount += 1 },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { screenshots in screenshots[0] }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete automatically") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        controller.toggleAutoScroll()
        pendingStep?()
        pendingStep?()

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(scrolledCount, 2)
        controller.cancel()
    }

    func testAutoScrollStopsAfterTwoPreviewSamplesAddNoHeight() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        var previewWork: [() -> Void] = []
        var scrolledCount = 0
        let previewScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 40),
            rect: CGRect(x: 10, y: 20, width: 20, height: 40)
        )
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in
                self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in scrolledCount += 1 },
            scheduleStep: { _, step in pendingStep = step },
            previewStitch: { _ in
                ScrollingScreenshotPreviewSnapshot(image: previewScreenshot.image, pixelHeight: 40)
            },
            performPreviewStitch: { work in previewWork.append(work) }
        )

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        controller.toggleAutoScroll()

        for index in 0..<3 {
            pendingStep?()
            XCTAssertEqual(previewWork.count, index + 1)
            previewWork[index]()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        XCTAssertEqual(scrolledCount, 4)
        pendingStep?()
        XCTAssertEqual(scrolledCount, 4)
        XCTAssertTrue(controller.isActive)
        controller.cancel()
    }

    func testCancelClosesWithoutCompletion() {
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in
                self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )
        var didComplete = false
        var didCancel = false

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in didComplete = true },
            onCancel: { didCancel = true },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        controller.cancel()

        XCTAssertFalse(didComplete)
        XCTAssertTrue(didCancel)
        XCTAssertFalse(controller.isActive)
    }

    func testSamplingFailureStopsSessionAndReportsFailure() {
        struct SampleFailure: Error {}
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { _ in throw SampleFailure() },
            scrollRegion: { _ in },
            scheduleStep: { _, _ in }
        )
        var reportedError: Error?

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { reportedError = $0 }
        )
        controller.beginScrolling()

        XCTAssertTrue(reportedError is SampleFailure)
        XCTAssertFalse(controller.isActive)
    }

    func testStitchFailureResumesCaptureAndReportsRetryableFailure() {
        let failureExpectation = expectation(description: "stitch failure resumes capture")
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            maximumScrollSteps: 1,
            showsInterface: false,
            captureRegion: { rect in
                self.makeCapturedScreenshot(size: rect.size, rect: rect)
            },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap },
            recoverStitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap }
        )
        var reportedError: Error?

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onPreviewUpdate: { _ in },
            onFinishStarted: { _ in },
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { },
            onRetryableFailure: { error in
                reportedError = error
                failureExpectation.fulfill()
            },
            onFailure: { error in XCTFail("Unexpected terminal failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [failureExpectation], timeout: 1)

        XCTAssertEqual(reportedError as? ScrollingScreenshotStitchingError, .noReliableOverlap)
        XCTAssertTrue(controller.isActive)
        XCTAssertNotNil(pendingStep)
        controller.cancel()
    }

    func testStrictStitchFailureCompletesWithRecoveryStitch() {
        var pendingStep: (@MainActor @Sendable () -> Void)?
        let recoveredScreenshot = makeCapturedScreenshot(
            size: CGSize(width: 20, height: 40),
            rect: CGRect(x: 10, y: 20, width: 20, height: 40)
        )
        let completionExpectation = expectation(description: "recovery stitch completes")
        let controller = ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in self.makeCapturedScreenshot(size: rect.size, rect: rect) },
            scrollRegion: { _ in },
            scheduleStep: { _, step in pendingStep = step },
            stitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap },
            recoverStitch: { _ in recoveredScreenshot }
        )
        var completedScreenshot: CapturedScreenshot?

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: {
                completedScreenshot = $0
                completionExpectation.fulfill()
            },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [completionExpectation], timeout: 1)
        XCTAssertEqual(completedScreenshot?.rect, recoveredScreenshot.rect)
        XCTAssertFalse(controller.isActive)
    }

    private func makeCapturedScreenshot(size: CGSize, rect: CGRect) -> CapturedScreenshot {
        let image = NSImage(size: size)
        return CapturedScreenshot(
            pngData: Data([UInt8(size.width), UInt8(size.height)]),
            image: image,
            rect: rect
        )
    }

    private func makeStripedCapturedScreenshot(rows: [[UInt8]], width: Int = 3) throws -> CapturedScreenshot {
        var pixels = rows.flatMap { row in
            Array(repeating: row, count: width).flatMap { $0 }
        }
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: rows.count,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try XCTUnwrap(context.makeImage())
        let size = CGSize(width: width, height: rows.count)
        return CapturedScreenshot(
            pngData: Data(),
            image: NSImage(cgImage: cgImage, size: size),
            rect: CGRect(origin: .zero, size: size)
        )
    }

    private func colorComponents(_ color: NSColor) -> [Int] {
        let color = color.usingColorSpace(.deviceRGB) ?? color
        return [
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
            Int((color.alphaComponent * 255).rounded()),
        ]
    }
}

@MainActor
private final class ScrollingScreenshotPreviewPresenterSpy: ScrollingScreenshotPreviewPresenting {
    var statuses: [ScrollingScreenshotPreviewStatus] = []
    var pixelHeights: [Int] = []
    var imageUpdateCount = 0
    var closeCallCount = 0
    var onUpdate: ((ScrollingScreenshotPreviewStatus, Int) -> Void)?

    func show(selectionRect: CGRect) {
        update(image: nil, status: .waiting)
    }

    func update(image: NSImage?, status: ScrollingScreenshotPreviewStatus) {
        let pixelHeight = image.map { Int($0.size.height.rounded()) } ?? 0
        statuses.append(status)
        pixelHeights.append(pixelHeight)
        if image != nil {
            imageUpdateCount += 1
        }
        onUpdate?(status, pixelHeight)
    }

    func close() {
        closeCallCount += 1
    }
}
