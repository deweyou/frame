import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class RecordingBoundaryOverlayControllerTests: XCTestCase {
    func testRecordingBoundaryIsVisibleButNonInteractiveAndExcludedFromCapture() {
        let controller = RecordingBoundaryOverlayController()
        defer {
            controller.close()
        }

        let rect = CGRect(x: 40, y: 60, width: 320, height: 180)
        controller.show(rect: rect)

        XCTAssertEqual(controller.frameForTesting(), rect.integral)
        XCTAssertEqual(controller.ignoresMouseEventsForTesting(), true)
        XCTAssertEqual(controller.sharingTypeForTesting(), NSWindow.SharingType.none)
    }
}
