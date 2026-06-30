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

        controller.finish()
        pendingStep?()

        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(scrollCount, 0)
        XCTAssertFalse(controller.isActive)

        pendingStitch?()

        wait(for: [completionExpectation], timeout: 1)
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

    func testStitchFailureReportsFailure() {
        let failureExpectation = expectation(description: "stitch failure reports failure")
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
            stitch: { _ in throw ScrollingScreenshotStitchingError.noReliableOverlap }
        )
        var reportedError: Error?

        controller.start(
            selection: SelectionCapture(rect: CGRect(x: 10, y: 20, width: 20, height: 20), kind: .region),
            strings: AppStrings(language: .zhHans),
            onComplete: { _ in XCTFail("Should not complete") },
            onCancel: { XCTFail("Should not cancel") },
            onFailure: { error in
                reportedError = error
                failureExpectation.fulfill()
            }
        )
        controller.beginScrolling()
        pendingStep?()
        controller.finish()

        wait(for: [failureExpectation], timeout: 1)

        XCTAssertEqual(reportedError as? ScrollingScreenshotStitchingError, .noReliableOverlap)
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
