import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class ScrollingScreenshotIncrementalSessionControllerTests: XCTestCase {
    func testDefaultBackgroundExecutorIngestsAndFinishesWithoutActorViolation() async throws {
        let previewExpectation = expectation(description: "background ingest publishes preview")
        let completionExpectation = expectation(description: "background finish publishes screenshot")
        let controller = ScrollingScreenshotSessionController(
            showsInterface: false,
            captureRegion: { rect in try self.makeCapturedFrame(rect: rect) },
            scheduleStep: { _, _ in },
            incrementalPipelineFactory: {
                ScrollingScreenshotIncrementalPipeline(previewMaximumPixelWidth: 4)
            }
        )
        controller.start(
            selection: SelectionCapture(
                rect: CGRect(x: 10, y: 20, width: 4, height: 4),
                kind: .region
            ),
            strings: AppStrings(language: .zhHans),
            onPreviewUpdate: { _ in previewExpectation.fulfill() },
            onFinishStarted: { _ in },
            onComplete: { _ in completionExpectation.fulfill() },
            onCancel: {},
            onRetryableFailure: { error in XCTFail("Unexpected retry: \(error)") },
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )

        controller.beginScrolling()
        await fulfillment(of: [previewExpectation], timeout: 1)
        controller.finish()
        await fulfillment(of: [completionExpectation], timeout: 1)
        XCTAssertFalse(controller.isActive)
    }

    func testDefaultControllerUsesIncrementalPipeline() {
        let controller = ScrollingScreenshotSessionController()

        start(controller)

        XCTAssertTrue(controller.usesIncrementalPipelineForTesting())
        controller.cancel()
    }

    func testAutomaticScrollWaitsForCurrentFrameClassification() async throws {
        let pipeline = IncrementalPipelineStub(states: [.initialized, .appended])
        let harness = IncrementalControllerHarness()
        let controller = makeController(pipeline: pipeline, harness: harness)

        start(controller)
        controller.beginScrolling()
        XCTAssertEqual(harness.pendingWork.count, 1)
        XCTAssertEqual(harness.scrolledRects.count, 0)

        controller.toggleAutoScroll()
        XCTAssertEqual(harness.scrolledRects.count, 0)

        harness.pendingWork.removeFirst()()
        await settleMainActor()
        XCTAssertEqual(harness.scrolledRects.count, 1)
        XCTAssertEqual(harness.pendingSteps.count, 1)

        harness.pendingSteps.removeLast()()
        XCTAssertEqual(harness.pendingWork.count, 1)
        XCTAssertEqual(harness.scrolledRects.count, 1)

        harness.pendingWork.removeFirst()()
        await settleMainActor()
        XCTAssertEqual(harness.scrolledRects.count, 2)
        controller.cancel()
    }

    func testAutomaticScrollConfirmsBottomWithoutSendingMoreScrollEvents() async throws {
        let pipeline = IncrementalPipelineStub(
            states: [.initialized, .noProgress, .noProgress, .noProgress]
        )
        let harness = IncrementalControllerHarness()
        let controller = makeController(pipeline: pipeline, harness: harness)

        start(controller)
        controller.beginScrolling()
        harness.pendingWork.removeFirst()()
        await settleMainActor()
        controller.toggleAutoScroll()
        XCTAssertEqual(harness.scrolledRects.count, 1)

        for _ in 0..<3 {
            harness.pendingSteps.removeLast()()
            harness.pendingWork.removeFirst()()
            await settleMainActor()
        }

        XCTAssertEqual(harness.scrolledRects.count, 1)
        XCTAssertFalse(controller.isAutoScrollingEnabledForTesting())
        XCTAssertTrue(controller.isActive)
        controller.cancel()
    }

    func testHistoricalRepeatStopsAutomaticScrollImmediately() async throws {
        let pipeline = IncrementalPipelineStub(states: [.initialized, .historicalRepeat])
        let harness = IncrementalControllerHarness()
        let controller = makeController(pipeline: pipeline, harness: harness)

        start(controller)
        controller.beginScrolling()
        harness.pendingWork.removeFirst()()
        await settleMainActor()
        controller.toggleAutoScroll()
        harness.pendingSteps.removeLast()()
        harness.pendingWork.removeFirst()()
        await settleMainActor()

        XCTAssertEqual(harness.scrolledRects.count, 1)
        XCTAssertFalse(controller.isAutoScrollingEnabledForTesting())
        controller.cancel()
    }

    func testUnreliableOverlapPausesAutomaticScrollAndPreservesSession() async throws {
        let pipeline = IncrementalPipelineStub(states: [.initialized, .unreliableOverlap])
        let harness = IncrementalControllerHarness()
        let controller = makeController(pipeline: pipeline, harness: harness)

        start(controller)
        controller.beginScrolling()
        harness.pendingWork.removeFirst()()
        await settleMainActor()
        controller.toggleAutoScroll()
        harness.pendingSteps.removeLast()()
        harness.pendingWork.removeFirst()()
        await settleMainActor()

        XCTAssertFalse(controller.isAutoScrollingEnabledForTesting())
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(harness.scrolledRects.count, 1)
        controller.cancel()
    }

    func testFinishUsesAcceptedAccumulatorWithoutCallingBatchStitcher() async throws {
        let pipeline = IncrementalPipelineStub(states: [.initialized])
        let harness = IncrementalControllerHarness()
        var completedScreenshot: CapturedScreenshot?
        let controller = makeController(pipeline: pipeline, harness: harness)

        start(controller, onComplete: { completedScreenshot = $0 })
        controller.beginScrolling()
        harness.pendingWork.removeFirst()()
        await settleMainActor()

        controller.finish()
        XCTAssertEqual(harness.pendingWork.count, 1)
        harness.pendingWork.removeFirst()()
        await settleMainActor()

        XCTAssertEqual(pipeline.finishCallCount, 1)
        XCTAssertNotNil(completedScreenshot)
        XCTAssertFalse(controller.isActive)
    }

    private func makeController(
        pipeline: IncrementalPipelineStub,
        harness: IncrementalControllerHarness
    ) -> ScrollingScreenshotSessionController {
        ScrollingScreenshotSessionController(
            stepDelay: 60,
            showsInterface: false,
            captureRegion: { rect in try self.makeCapturedFrame(rect: rect) },
            scrollRegion: { rect in harness.scrolledRects.append(rect) },
            scheduleStep: { _, step in harness.pendingSteps.append(step) },
            stitch: { _ in
                XCTFail("The live incremental path must not invoke batch stitching")
                throw ScrollingScreenshotStitchingError.noReliableOverlap
            },
            performStitch: { work in harness.pendingWork.append(work) },
            incrementalPipelineFactory: { pipeline }
        )
    }

    private func start(
        _ controller: ScrollingScreenshotSessionController,
        onComplete: @escaping (CapturedScreenshot) -> Void = { _ in }
    ) {
        controller.start(
            selection: SelectionCapture(
                rect: CGRect(x: 10, y: 20, width: 4, height: 4),
                kind: .region
            ),
            strings: AppStrings(language: .zhHans),
            onComplete: onComplete,
            onCancel: {},
            onFailure: { error in XCTFail("Unexpected failure: \(error)") }
        )
    }

    private func makeCapturedFrame(rect: CGRect) throws -> CapturedScreenshot {
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = 20
            pixels[offset + 1] = 40
            pixels[offset + 2] = 60
            pixels[offset + 3] = 255
        }
        guard let context = CGContext(
            data: &pixels,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }
        return CapturedScreenshot(
            pngData: Data(),
            image: NSImage(cgImage: image, size: rect.size),
            rect: rect
        )
    }

    private func settleMainActor() async {
        await Task.yield()
        await Task.yield()
    }
}

@MainActor
private final class IncrementalControllerHarness {
    var pendingSteps: [@MainActor @Sendable () -> Void] = []
    var pendingWork: [() -> Void] = []
    var scrolledRects: [CGRect] = []
}

private final class IncrementalPipelineStub: ScrollingScreenshotIncrementalProcessing, @unchecked Sendable {
    private var states: [ScrollingScreenshotIngestState]
    private let previewImage: NSImage
    private(set) var finishCallCount = 0

    init(states: [ScrollingScreenshotIngestState]) {
        self.states = states
        previewImage = NSImage(size: CGSize(width: 4, height: 4))
    }

    func ingest(_ frame: ScrollingScreenshotProcessingFrame) throws -> ScrollingScreenshotProcessedSample {
        let state = states.removeFirst()
        let totalHeight = state == .appended ? 6 : 4
        return ScrollingScreenshotProcessedSample(
            progress: ScrollingScreenshotIngestResult(
                state: state,
                appendedPixelHeight: state == .appended ? 2 : 0,
                totalPixelHeight: totalHeight,
                verticalDisplacement: state == .appended ? 2 : nil,
                confidence: state == .unreliableOverlap ? 0 : 1
            ),
            previewImage: state == .initialized || state == .appended ? previewImage : nil
        )
    }

    func finish(outputID: UUID) throws -> CapturedScreenshot {
        finishCallCount += 1
        return CapturedScreenshot(
            id: outputID,
            pngData: Data([1]),
            image: previewImage,
            rect: CGRect(x: 10, y: 20, width: 4, height: 4)
        )
    }
}
