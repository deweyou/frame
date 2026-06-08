import AppKit
import XCTest
@testable import FrameApp

final class RecordingLiveOverlayControllerTests: XCTestCase {
    @MainActor
    func testLiveOverlayUsesPassiveNonCapturableWindow() {
        let controller = RecordingLiveOverlayController()
        let eventStore = RecordingOverlayEventStore()
        let screenFrame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let selectionRect = CGRect(x: 40, y: 40, width: 120, height: 80)

        controller.show(
            screenFrame: screenFrame,
            selectionRect: selectionRect,
            pixelSize: CGSize(width: 240, height: 160),
            eventStore: eventStore
        )

        XCTAssertTrue(controller.isVisibleForTesting())
        XCTAssertEqual(controller.frameForTesting(), screenFrame)
        XCTAssertEqual(controller.ignoresMouseEventsForTesting(), true)
        XCTAssertEqual(controller.sharingTypeForTesting(), NSWindow.SharingType.none)
        XCTAssertNotNil(controller.windowNumber)

        controller.close()
    }

    func testCaptureExclusionMatchesOnlyLiveOverlayWindowNumber() {
        XCTAssertTrue(
            RecordingOverlayCaptureExclusion.shouldExclude(
                windowID: CGWindowID(42),
                liveOverlayWindowNumber: 42
            )
        )
        XCTAssertFalse(
            RecordingOverlayCaptureExclusion.shouldExclude(
                windowID: CGWindowID(41),
                liveOverlayWindowNumber: 42
            )
        )
        XCTAssertFalse(
            RecordingOverlayCaptureExclusion.shouldExclude(
                windowID: CGWindowID(42),
                liveOverlayWindowNumber: nil
            )
        )
    }
}
